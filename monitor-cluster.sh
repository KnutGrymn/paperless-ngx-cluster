#!/bin/bash

# MIT License
# Copyright (c) 2024
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

# Load configuration
if [ -f /etc/paperless-cluster.conf ]; then
    source /etc/paperless-cluster.conf
else
    echo "Error: Configuration file not found at /etc/paperless-cluster.conf"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Status symbols
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING_SIGN="⚠"

# Monitoring configuration
ALERT_THRESHOLD_REPLICATION_LAG=60  # seconds
ALERT_THRESHOLD_DISK_USAGE=80      # percentage
ALERT_THRESHOLD_MEMORY_USAGE=85    # percentage
ALERT_THRESHOLD_CPU_USAGE=80       # percentage

# State tracking
MONITORING_STATE_FILE="/var/lib/paperless-cluster/monitoring.state"
mkdir -p $(dirname "$MONITORING_STATE_FILE")

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check system resources
check_system_resources() {
    echo -e "\n${CYAN}=== System Resources ===${NC}"
    
    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -f1 -d'%')
    if (( $(echo "$CPU_USAGE > $ALERT_THRESHOLD_CPU_USAGE" | bc -l) )); then
        echo -e "${RED}${CROSS_MARK}${NC} CPU Usage: ${RED}${CPU_USAGE}%${NC} (HIGH)"
    else
        echo -e "${GREEN}${CHECK_MARK}${NC} CPU Usage: ${GREEN}${CPU_USAGE}%${NC}"
    fi
    
    # Memory usage
    MEMORY_INFO=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
    if (( $(echo "$MEMORY_INFO > $ALERT_THRESHOLD_MEMORY_USAGE" | bc -l) )); then
        echo -e "${RED}${CROSS_MARK}${NC} Memory Usage: ${RED}${MEMORY_INFO}%${NC} (HIGH)"
    else
        echo -e "${GREEN}${CHECK_MARK}${NC} Memory Usage: ${GREEN}${MEMORY_INFO}%${NC}"
    fi
    
    # Disk usage
    echo -e "\n  Disk Usage:"
    while IFS= read -r line; do
        USAGE=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        MOUNT=$(echo "$line" | awk '{print $6}')
        if [ "$USAGE" -gt "$ALERT_THRESHOLD_DISK_USAGE" ]; then
            echo -e "  ${RED}${CROSS_MARK}${NC} $MOUNT: ${RED}${USAGE}%${NC} (HIGH)"
        else
            echo -e "  ${GREEN}${CHECK_MARK}${NC} $MOUNT: ${GREEN}${USAGE}%${NC}"
        fi
    done <<< "$(df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev')"
    
    # Load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{ print $2 }')
    echo -e "  Load Average:${CYAN}$LOAD_AVG${NC}"
}

# Check PostgreSQL status
check_postgresql() {
    echo -e "\n${CYAN}=== PostgreSQL Status ===${NC}"
    
    # Check if PostgreSQL is running
    if systemctl is-active --quiet postgresql-$PG_VERSION; then
        echo -e "${GREEN}${CHECK_MARK}${NC} PostgreSQL service: ${GREEN}Running${NC}"
        
        # Check database connectivity
        if sudo -u postgres psql -d paperless -c "SELECT 1;" &>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC} Database connectivity: ${GREEN}OK${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC} Database connectivity: ${RED}Failed${NC}"
        fi
        
        # Get database size
        DB_SIZE=$(sudo -u postgres psql -t -d paperless -c "SELECT pg_size_pretty(pg_database_size('paperless'));" | xargs)
        echo -e "  Database size: ${CYAN}$DB_SIZE${NC}"
        
        # Check active connections
        CONNECTIONS=$(sudo -u postgres psql -t -d paperless -c "SELECT count(*) FROM pg_stat_activity WHERE datname='paperless';" | xargs)
        echo -e "  Active connections: ${CYAN}$CONNECTIONS${NC}"
        
        # Check for long-running queries
        LONG_QUERIES=$(sudo -u postgres psql -t -d paperless -c "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle' AND now() - query_start > interval '1 minute';" | xargs)
        if [ "$LONG_QUERIES" -gt 0 ]; then
            echo -e "  ${YELLOW}${WARNING_SIGN}${NC} Long-running queries: ${YELLOW}$LONG_QUERIES${NC}"
        fi
        
    else
        echo -e "${RED}${CROSS_MARK}${NC} PostgreSQL service: ${RED}Not running${NC}"
    fi
}

# Check pgactive replication
check_pgactive_replication() {
    echo -e "\n${CYAN}=== pgactive Replication Status ===${NC}"
    
    if ! systemctl is-active --quiet postgresql-$PG_VERSION; then
        echo -e "${RED}${CROSS_MARK}${NC} Cannot check replication: PostgreSQL not running"
        return
    fi
    
    # Check group membership
    echo -e "\n  ${MAGENTA}Group Membership:${NC}"
    sudo -u postgres psql -d paperless -t <<EOF 2>/dev/null | while IFS='|' read -r node_name node_id is_local; do
SELECT node_name, node_id, is_local 
FROM pgactive.pgactive_monitor_group_membership();
EOF
        node_name=$(echo "$node_name" | xargs)
        node_id=$(echo "$node_id" | xargs)
        is_local=$(echo "$is_local" | xargs)
        
        if [ "$is_local" = "t" ]; then
            echo -e "  ${GREEN}${CHECK_MARK}${NC} $node_name (ID: $node_id) - ${GREEN}Local Node${NC}"
        else
            echo -e "  ${BLUE}○${NC} $node_name (ID: $node_id) - Remote Node"
        fi
    done
    
    # Check subscription status
    echo -e "\n  ${MAGENTA}Subscription Status:${NC}"
    SUBSCRIPTION_COUNT=$(sudo -u postgres psql -t -d paperless -c "SELECT count(*) FROM pgactive.pgactive_monitor_subscription_status();" 2>/dev/null | xargs)
    
    if [ "$SUBSCRIPTION_COUNT" -gt 0 ]; then
        sudo -u postgres psql -d paperless -t <<EOF 2>/dev/null | while IFS='|' read -r sub_name status received_lsn; do
SELECT subscription_name, subscription_status, received_lsn
FROM pgactive.pgactive_monitor_subscription_status();
EOF
            sub_name=$(echo "$sub_name" | xargs)
            status=$(echo "$status" | xargs)
            
            if [ "$status" = "streaming" ]; then
                echo -e "  ${GREEN}${CHECK_MARK}${NC} $sub_name: ${GREEN}$status${NC}"
            else
                echo -e "  ${YELLOW}${WARNING_SIGN}${NC} $sub_name: ${YELLOW}$status${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}${WARNING_SIGN}${NC} No active subscriptions"
    fi
    
    # Check conflict history
    CONFLICTS=$(sudo -u postgres psql -t -d paperless -c "SELECT count(*) FROM pgactive.pgactive_monitor_conflict_history() WHERE conflict_time > NOW() - INTERVAL '1 hour';" 2>/dev/null | xargs)
    if [ "$CONFLICTS" -gt 0 ]; then
        echo -e "\n  ${YELLOW}${WARNING_SIGN}${NC} Conflicts in last hour: ${YELLOW}$CONFLICTS${NC}"
        
        # Show recent conflicts
        echo -e "  Recent conflicts:"
        sudo -u postgres psql -d paperless -t <<EOF 2>/dev/null | head -5
SELECT conflict_time, conflict_type, table_name
FROM pgactive.pgactive_monitor_conflict_history()
ORDER BY conflict_time DESC
LIMIT 5;
EOF
    else
        echo -e "\n  ${GREEN}${CHECK_MARK}${NC} No conflicts in last hour"
    fi
}

# Check GlusterFS status
check_glusterfs() {
    echo -e "\n${CYAN}=== GlusterFS Status ===${NC}"
    
    # Check if GlusterFS is running
    if systemctl is-active --quiet glusterd; then
        echo -e "${GREEN}${CHECK_MARK}${NC} GlusterFS service: ${GREEN}Running${NC}"
        
        # Check volume status
        VOLUME_STATUS=$(gluster volume status $GLUSTER_VOLUME 2>/dev/null | grep "Status:" | head -1 | awk '{print $2}')
        if [ "$VOLUME_STATUS" = "Started" ]; then
            echo -e "${GREEN}${CHECK_MARK}${NC} Volume '$GLUSTER_VOLUME': ${GREEN}Started${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC} Volume '$GLUSTER_VOLUME': ${RED}$VOLUME_STATUS${NC}"
        fi
        
        # Check if mounted
        if mountpoint -q /mnt/glusterfs; then
            echo -e "${GREEN}${CHECK_MARK}${NC} Mount point: ${GREEN}Mounted${NC}"
            
            # Get volume size and usage
            VOLUME_INFO=$(df -h /mnt/glusterfs | tail -1)
            VOLUME_SIZE=$(echo "$VOLUME_INFO" | awk '{print $2}')
            VOLUME_USED=$(echo "$VOLUME_INFO" | awk '{print $3}')
            VOLUME_PERCENT=$(echo "$VOLUME_INFO" | awk '{print $5}')
            echo -e "  Volume usage: ${CYAN}$VOLUME_USED / $VOLUME_SIZE ($VOLUME_PERCENT)${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC} Mount point: ${RED}Not mounted${NC}"
        fi
        
        # Check peer status
        echo -e "\n  ${MAGENTA}Peer Status:${NC}"
        gluster peer status 2>/dev/null | grep "Hostname:" | while read -r line; do
            PEER=$(echo "$line" | awk '{print $2}')
            STATE=$(gluster peer status 2>/dev/null | grep -A1 "$PEER" | grep "State:" | awk '{print $3,$4}')
            
            if [[ "$STATE" == *"Connected"* ]]; then
                echo -e "  ${GREEN}${CHECK_MARK}${NC} $PEER: ${GREEN}$STATE${NC}"
            else
                echo -e "  ${RED}${CROSS_MARK}${NC} $PEER: ${RED}$STATE${NC}"
            fi
        done
        
        # Check heal status
        HEAL_COUNT=$(gluster volume heal $GLUSTER_VOLUME info 2>/dev/null | grep "Number of entries:" | awk '{sum+=$4} END {print sum}')
        if [ "$HEAL_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}${WARNING_SIGN}${NC} Files pending heal: ${YELLOW}$HEAL_COUNT${NC}"
        else
            echo -e "  ${GREEN}${CHECK_MARK}${NC} No files pending heal"
        fi
        
    else
        echo -e "${RED}${CROSS_MARK}${NC} GlusterFS service: ${RED}Not running${NC}"
    fi
}

# Check Docker and Paperless-ngx
check_docker_paperless() {
    echo -e "\n${CYAN}=== Docker & Paperless-ngx Status ===${NC}"
    
    # Check if Docker is running
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}${CHECK_MARK}${NC} Docker service: ${GREEN}Running${NC}"
        
        # Check Paperless containers
        cd /opt/paperless-ngx 2>/dev/null || {
            echo -e "${RED}${CROSS_MARK}${NC} Paperless-ngx directory not found"
            return
        }
        
        echo -e "\n  ${MAGENTA}Container Status:${NC}"
        
        # Check webserver
        WEBSERVER_STATUS=$(docker compose ps webserver --format "{{.State}}" 2>/dev/null)
        if [ "$WEBSERVER_STATUS" = "running" ]; then
            echo -e "  ${GREEN}${CHECK_MARK}${NC} Webserver: ${GREEN}Running${NC}"
            
            # Check if web interface is accessible
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8000" | grep -q "200\|302"; then
                echo -e "  ${GREEN}${CHECK_MARK}${NC} Web interface: ${GREEN}Accessible${NC}"
            else
                echo -e "  ${YELLOW}${WARNING_SIGN}${NC} Web interface: ${YELLOW}Not accessible${NC}"
            fi
        else
            echo -e "  ${RED}${CROSS_MARK}${NC} Webserver: ${RED}$WEBSERVER_STATUS${NC}"
        fi
        
        # Check Redis
        REDIS_STATUS=$(docker compose ps redis --format "{{.State}}" 2>/dev/null)
        if [ "$REDIS_STATUS" = "running" ]; then
            echo -e "  ${GREEN}${CHECK_MARK}${NC} Redis: ${GREEN}Running${NC}"
        else
            echo -e "  ${RED}${CROSS_MARK}${NC} Redis: ${RED}$REDIS_STATUS${NC}"
        fi
        
        # Get document statistics from Paperless
        if [ "$WEBSERVER_STATUS" = "running" ]; then
            echo -e "\n  ${MAGENTA}Document Statistics:${NC}"
            
            # Try to get document count via API (if accessible)
            DOCS_COUNT=$(docker compose exec -T webserver python3 manage.py document_count 2>/dev/null || echo "N/A")
            echo -e "  Total documents: ${CYAN}$DOCS_COUNT${NC}"
            
            # Check for pending tasks
            PENDING_TASKS=$(docker compose exec -T redis redis-cli LLEN paperless:queue:default 2>/dev/null || echo "N/A")
            if [ "$PENDING_TASKS" != "N/A" ] && [ "$PENDING_TASKS" -gt 0 ]; then
                echo -e "  ${YELLOW}${WARNING_SIGN}${NC} Pending tasks: ${YELLOW}$PENDING_TASKS${NC}"
            else
                echo -e "  ${GREEN}${CHECK_MARK}${NC} Pending tasks: 0"
            fi
        fi
        
    else
        echo -e "${RED}${CROSS_MARK}${NC} Docker service: ${RED}Not running${NC}"
    fi
}

# Check cluster connectivity
check_cluster_connectivity() {
    echo -e "\n${CYAN}=== Cluster Connectivity ===${NC}"
    
    # Parse node IPs from pgactive group membership
    if systemctl is-active --quiet postgresql-$PG_VERSION; then
        OTHER_NODES=$(sudo -u postgres psql -t -d paperless -c "
            SELECT node_dsn FROM pgactive.pgactive_monitor_group_membership() 
            WHERE NOT is_local;" 2>/dev/null | grep -oE 'host=[^ ]+' | cut -d'=' -f2)
        
        if [ ! -z "$OTHER_NODES" ]; then
            echo -e "\n  ${MAGENTA}Testing connectivity to other nodes:${NC}"
            for node_host in $OTHER_NODES; do
                # Test ping
                if ping -c 1 -W 2 "$node_host" &>/dev/null; then
                    echo -e "  ${GREEN}${CHECK_MARK}${NC} $node_host: ${GREEN}Reachable${NC}"
                    
                    # Test PostgreSQL port
                    if nc -z -w 2 "$node_host" 5432 2>/dev/null; then
                        echo -e "    PostgreSQL port: ${GREEN}Open${NC}"
                    else
                        echo -e "    PostgreSQL port: ${RED}Closed${NC}"
                    fi
                else
                    echo -e "  ${RED}${CROSS_MARK}${NC} $node_host: ${RED}Unreachable${NC}"
                fi
            done
        else
            echo -e "  ${YELLOW}${WARNING_SIGN}${NC} No other nodes found in cluster"
        fi
    fi
}

# Generate summary report
generate_summary() {
    echo -e "\n${CYAN}=== Cluster Health Summary ===${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Count issues
    CRITICAL_ISSUES=0
    WARNING_ISSUES=0
    
    # Check critical services
    for service in postgresql-$PG_VERSION glusterd docker; do
        if ! systemctl is-active --quiet $service; then
            ((CRITICAL_ISSUES++))
        fi
    done
    
    # Overall status
    if [ $CRITICAL_ISSUES -gt 0 ]; then
        echo -e "${RED}Overall Status: CRITICAL${NC}"
        echo -e "${RED}Critical issues found: $CRITICAL_ISSUES${NC}"
    elif [ $WARNING_ISSUES -gt 0 ]; then
        echo -e "${YELLOW}Overall Status: WARNING${NC}"
        echo -e "${YELLOW}Warning issues found: $WARNING_ISSUES${NC}"
    else
        echo -e "${GREEN}Overall Status: HEALTHY${NC}"
        echo -e "${GREEN}All systems operational${NC}"
    fi
    
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Node: ${CYAN}$NODE_NAME${NC} | IP: ${CYAN}$NODE_IP${NC}"
    echo -e "Time: ${CYAN}$(date)${NC}"
}

# Continuous monitoring mode
continuous_monitoring() {
    local INTERVAL=${1:-60}  # Default 60 seconds
    
    log_info "Starting continuous monitoring (interval: ${INTERVAL}s)"
    log_info "Press Ctrl+C to stop"
    
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  Paperless-ngx Cluster Monitoring Dashboard ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
        
        check_system_resources
        check_postgresql
        check_pgactive_replication
        check_glusterfs
        check_docker_paperless
        check_cluster_connectivity
        generate_summary
        
        echo -e "\n${CYAN}Next refresh in ${INTERVAL} seconds...${NC}"
        sleep $INTERVAL
    done
}

# Export metrics in Prometheus format
export_prometheus_metrics() {
    local METRICS_FILE="/var/lib/paperless-cluster/metrics.prom"
    mkdir -p $(dirname "$METRICS_FILE")
    
    {
        echo "# HELP paperless_cluster_node_info Node information"
        echo "# TYPE paperless_cluster_node_info gauge"
        echo "paperless_cluster_node_info{node=\"$NODE_NAME\",ip=\"$NODE_IP\"} 1"
        
        # PostgreSQL metrics
        if systemctl is-active --quiet postgresql-$PG_VERSION; then
            echo "# HELP paperless_postgresql_up PostgreSQL service status"
            echo "# TYPE paperless_postgresql_up gauge"
            echo "paperless_postgresql_up 1"
            
            # Database size
            DB_SIZE_BYTES=$(sudo -u postgres psql -t -d paperless -c "SELECT pg_database_size('paperless');" 2>/dev/null | xargs)
            echo "# HELP paperless_database_size_bytes Database size in bytes"
            echo "# TYPE paperless_database_size_bytes gauge"
            echo "paperless_database_size_bytes $DB_SIZE_BYTES"
        else
            echo "paperless_postgresql_up 0"
        fi
        
        # GlusterFS metrics
        if systemctl is-active --quiet glusterd; then
            echo "# HELP paperless_glusterfs_up GlusterFS service status"
            echo "# TYPE paperless_glusterfs_up gauge"
            echo "paperless_glusterfs_up 1"
        else
            echo "paperless_glusterfs_up 0"
        fi
        
        # Docker metrics
        if systemctl is-active --quiet docker; then
            echo "# HELP paperless_docker_up Docker service status"
            echo "# TYPE paperless_docker_up gauge"
            echo "paperless_docker_up 1"
        else
            echo "paperless_docker_up 0"
        fi
        
    } > "$METRICS_FILE"
    
    log_success "Metrics exported to $METRICS_FILE"
}

# Show help
show_help() {
    cat <<EOF
Paperless-ngx Cluster Monitoring Script

Usage:
    $0                      Run monitoring once
    $0 --continuous [secs]  Run continuous monitoring (default: 60s)
    $0 --export-metrics     Export metrics in Prometheus format
    $0 --help              Show this help message

Options:
    --continuous [seconds]  Run monitoring continuously with specified interval
    --export-metrics       Export metrics to /var/lib/paperless-cluster/metrics.prom
    --help                Show help message

Examples:
    # Single monitoring run
    $0
    
    # Continuous monitoring every 30 seconds
    $0 --continuous 30
    
    # Export metrics for Prometheus
    $0 --export-metrics

Environment Variables:
    ALERT_THRESHOLD_REPLICATION_LAG  Replication lag threshold (default: 60s)
    ALERT_THRESHOLD_DISK_USAGE       Disk usage threshold (default: 80%)
    ALERT_THRESHOLD_MEMORY_USAGE     Memory usage threshold (default: 85%)
    ALERT_THRESHOLD_CPU_USAGE        CPU usage threshold (default: 80%)

EOF
}

# Main execution
case "${1:-}" in
    --continuous)
        continuous_monitoring "${2:-60}"
        ;;
    --export-metrics)
        export_prometheus_metrics
        ;;
    --help)
        show_help
        ;;
    *)
        # Single run
        check_system_resources
        check_postgresql
        check_pgactive_replication
        check_glusterfs
        check_docker_paperless
        check_cluster_connectivity
        generate_summary
        ;;
esac
