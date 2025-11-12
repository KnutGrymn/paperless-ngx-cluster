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
NC='\033[0m'

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/paperless-cluster}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="paperless_backup_${NODE_NAME}_${TIMESTAMP}"

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    log_info "Backup directory created: $BACKUP_DIR/$BACKUP_NAME"
}

# Backup PostgreSQL database
backup_postgresql() {
    log_info "Starting PostgreSQL backup..."
    
    # Create database backup using pgactive-aware dump
    sudo -u postgres pg_dumpall \
        --exclude-database=template0 \
        --exclude-database=template1 \
        > "$BACKUP_DIR/$BACKUP_NAME/postgresql_dump.sql"
    
    # Backup PostgreSQL configuration
    cp -r /etc/postgresql/$PG_VERSION/main "$BACKUP_DIR/$BACKUP_NAME/postgresql_config" 2>/dev/null || \
    cp -r /var/lib/pgsql/$PG_VERSION/data/*.conf "$BACKUP_DIR/$BACKUP_NAME/postgresql_config" 2>/dev/null
    
    # Backup pgactive replication status
    sudo -u postgres psql -d paperless <<EOF > "$BACKUP_DIR/$BACKUP_NAME/pgactive_status.txt" 2>&1
SELECT * FROM pgactive.pgactive_monitor_group_membership();
SELECT * FROM pgactive.pgactive_monitor_subscription_status();
SELECT * FROM pgactive.pgactive_monitor_conflict_history();
EOF
    
    log_success "PostgreSQL backup completed"
}

# Backup GlusterFS data
backup_glusterfs() {
    log_info "Starting GlusterFS data backup..."
    
    # Create snapshot if GlusterFS supports it
    if gluster volume snapshot create backup_${TIMESTAMP} $GLUSTER_VOLUME 2>/dev/null; then
        log_success "GlusterFS snapshot created: backup_${TIMESTAMP}"
        
        # Save snapshot info
        gluster volume snapshot info backup_${TIMESTAMP} > "$BACKUP_DIR/$BACKUP_NAME/gluster_snapshot_info.txt"
    else
        log_warning "GlusterFS snapshot not supported, using file copy method"
        
        # Backup Paperless data files
        if [ -d "/mnt/glusterfs" ]; then
            log_info "Backing up Paperless data files..."
            tar -czf "$BACKUP_DIR/$BACKUP_NAME/paperless_data.tar.gz" \
                -C /mnt/glusterfs \
                --exclude='consume/*' \
                data media export 2>/dev/null || true
        fi
    fi
    
    # Backup GlusterFS configuration
    gluster volume info $GLUSTER_VOLUME > "$BACKUP_DIR/$BACKUP_NAME/gluster_volume_info.txt"
    gluster peer status > "$BACKUP_DIR/$BACKUP_NAME/gluster_peer_status.txt"
    
    log_success "GlusterFS data backup completed"
}

# Backup Docker configuration
backup_docker() {
    log_info "Starting Docker configuration backup..."
    
    # Backup docker-compose configuration
    cp -r /opt/paperless-ngx "$BACKUP_DIR/$BACKUP_NAME/docker-config"
    
    # Export Docker images list
    docker images --format "{{.Repository}}:{{.Tag}}" | grep paperless > "$BACKUP_DIR/$BACKUP_NAME/docker_images.txt" 2>/dev/null || true
    
    # Export container configuration
    cd /opt/paperless-ngx
    docker compose config > "$BACKUP_DIR/$BACKUP_NAME/docker-compose-resolved.yml"
    
    log_success "Docker configuration backup completed"
}

# Backup cluster configuration
backup_cluster_config() {
    log_info "Backing up cluster configuration..."
    
    # Copy main configuration
    cp /etc/paperless-cluster.conf "$BACKUP_DIR/$BACKUP_NAME/"
    
    # Backup monitoring logs
    if [ -f /var/log/paperless-cluster-monitor.log ]; then
        tail -n 10000 /var/log/paperless-cluster-monitor.log > "$BACKUP_DIR/$BACKUP_NAME/monitor-recent.log"
    fi
    
    # Save system information
    cat > "$BACKUP_DIR/$BACKUP_NAME/system_info.txt" <<EOF
Backup Date: $(date)
Node Name: $NODE_NAME
Node IP: $NODE_IP
PostgreSQL Version: $PG_VERSION
GlusterFS Volume: $GLUSTER_VOLUME
Docker Version: $(docker --version)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
Kernel: $(uname -r)
EOF
    
    log_success "Cluster configuration backup completed"
}

# Create compressed archive
create_archive() {
    log_info "Creating backup archive..."
    
    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    
    # Calculate checksum
    sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"
    
    # Remove uncompressed backup directory
    rm -rf "$BACKUP_NAME"
    
    # Get backup size
    BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
    
    log_success "Backup archive created: ${BACKUP_NAME}.tar.gz (Size: $BACKUP_SIZE)"
}

# Clean old backups
clean_old_backups() {
    log_info "Cleaning old backups (retention: $RETENTION_DAYS days)..."
    
    find "$BACKUP_DIR" -name "paperless_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -exec rm {} \; 2>/dev/null || true
    find "$BACKUP_DIR" -name "paperless_backup_*.tar.gz.sha256" -type f -mtime +$RETENTION_DAYS -exec rm {} \; 2>/dev/null || true
    
    # Clean old GlusterFS snapshots
    if command -v gluster &> /dev/null; then
        SNAPSHOTS=$(gluster volume snapshot list $GLUSTER_VOLUME 2>/dev/null | grep "backup_" | head -n -5)
        for snapshot in $SNAPSHOTS; do
            gluster volume snapshot delete $snapshot force 2>/dev/null || true
            log_info "Deleted old snapshot: $snapshot"
        done
    fi
    
    log_success "Old backups cleaned"
}

# Verify backup
verify_backup() {
    log_info "Verifying backup integrity..."
    
    cd "$BACKUP_DIR"
    if sha256sum -c "${BACKUP_NAME}.tar.gz.sha256" &>/dev/null; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed!"
        exit 1
    fi
}

# Upload to remote storage (optional)
upload_to_remote() {
    if [ ! -z "$REMOTE_BACKUP_LOCATION" ]; then
        log_info "Uploading backup to remote storage..."
        
        # Example for S3
        if command -v aws &> /dev/null && [[ "$REMOTE_BACKUP_LOCATION" == s3://* ]]; then
            aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" "$REMOTE_BACKUP_LOCATION/" \
                --storage-class GLACIER_IR
            aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz.sha256" "$REMOTE_BACKUP_LOCATION/"
            log_success "Backup uploaded to S3"
            
        # Example for rsync
        elif [[ "$REMOTE_BACKUP_LOCATION" == *:* ]]; then
            rsync -avz "$BACKUP_DIR/${BACKUP_NAME}.tar.gz"* "$REMOTE_BACKUP_LOCATION/"
            log_success "Backup uploaded via rsync"
        fi
    fi
}

# Send notification
send_notification() {
    local status=$1
    local message=$2
    
    # Email notification (if configured)
    if [ ! -z "$NOTIFICATION_EMAIL" ]; then
        echo "$message" | mail -s "Paperless Cluster Backup - $status" "$NOTIFICATION_EMAIL" 2>/dev/null || true
    fi
    
    # Log to system journal
    logger -t paperless-backup "$status: $message"
}

# Main backup function
perform_backup() {
    log_info "Starting Paperless-ngx cluster backup on $NODE_NAME"
    
    START_TIME=$(date +%s)
    
    # Create backup directory
    create_backup_dir
    
    # Perform backups
    backup_cluster_config
    backup_postgresql
    backup_glusterfs
    backup_docker
    
    # Create archive
    create_archive
    
    # Verify backup
    verify_backup
    
    # Clean old backups
    clean_old_backups
    
    # Upload to remote (if configured)
    upload_to_remote
    
    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Final report
    REPORT="Backup completed successfully!
Location: $BACKUP_DIR/${BACKUP_NAME}.tar.gz
Size: $BACKUP_SIZE
Duration: ${DURATION} seconds
Node: $NODE_NAME
Timestamp: $TIMESTAMP"
    
    echo
    echo "========================================="
    echo "$REPORT"
    echo "========================================="
    
    # Send notification
    send_notification "SUCCESS" "$REPORT"
}

# Restore function
restore_backup() {
    local RESTORE_FILE=$1
    
    if [ -z "$RESTORE_FILE" ]; then
        log_error "Please specify a backup file to restore"
        echo "Usage: $0 --restore <backup-file.tar.gz>"
        exit 1
    fi
    
    if [ ! -f "$RESTORE_FILE" ]; then
        log_error "Backup file not found: $RESTORE_FILE"
        exit 1
    fi
    
    log_warning "This will restore the cluster from backup. All current data will be overwritten!"
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Starting restore from $RESTORE_FILE"
    
    # Extract backup
    RESTORE_DIR="/tmp/paperless_restore_$$"
    mkdir -p "$RESTORE_DIR"
    tar -xzf "$RESTORE_FILE" -C "$RESTORE_DIR"
    
    # Find extracted directory
    BACKUP_CONTENT=$(find "$RESTORE_DIR" -maxdepth 1 -type d | grep paperless_backup | head -1)
    
    # Stop services
    log_info "Stopping services..."
    cd /opt/paperless-ngx && docker compose down
    systemctl stop postgresql-$PG_VERSION
    
    # Restore PostgreSQL
    log_info "Restoring PostgreSQL..."
    sudo -u postgres psql < "$BACKUP_CONTENT/postgresql_dump.sql"
    
    # Restore Docker configuration
    log_info "Restoring Docker configuration..."
    cp -r "$BACKUP_CONTENT/docker-config/"* /opt/paperless-ngx/
    
    # Restore data files (if using file backup)
    if [ -f "$BACKUP_CONTENT/paperless_data.tar.gz" ]; then
        log_info "Restoring Paperless data files..."
        tar -xzf "$BACKUP_CONTENT/paperless_data.tar.gz" -C /mnt/glusterfs/
    fi
    
    # Start services
    log_info "Starting services..."
    systemctl start postgresql-$PG_VERSION
    cd /opt/paperless-ngx && docker compose up -d
    
    # Cleanup
    rm -rf "$RESTORE_DIR"
    
    log_success "Restore completed successfully!"
}

# Parse command line arguments
parse_arguments() {
    case "${1:-}" in
        --restore)
            check_root
            restore_backup "$2"
            ;;
        --help)
            show_help
            ;;
        *)
            check_root
            perform_backup
            ;;
    esac
}

# Show help
show_help() {
    cat <<EOF
Paperless-ngx Cluster Backup Script

Usage:
    $0                     Perform backup
    $0 --restore <file>    Restore from backup file
    $0 --help             Show this help message

Environment Variables:
    BACKUP_DIR            Backup directory (default: /backup/paperless-cluster)
    RETENTION_DAYS        Days to keep backups (default: 30)
    REMOTE_BACKUP_LOCATION Remote backup location (S3 or rsync)
    NOTIFICATION_EMAIL    Email for notifications

Examples:
    # Perform backup
    $0
    
    # Restore from backup
    $0 --restore /backup/paperless-cluster/paperless_backup_node1_20240101_120000.tar.gz
    
    # Backup with S3 upload
    REMOTE_BACKUP_LOCATION=s3://my-bucket/backups $0
    
    # Backup with email notification
    NOTIFICATION_EMAIL=admin@example.com $0

EOF
}

# Main execution
parse_arguments "$@"
