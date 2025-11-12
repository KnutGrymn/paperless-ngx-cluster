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

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Detect OS distribution
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS distribution"
        exit 1
    fi
    log_info "Detected OS: $OS $VER"
}

# Node configuration
configure_node() {
    echo "==========================================="
    echo "     Paperless-ngx Cluster Configuration"
    echo "==========================================="
    echo
    
    read -p "Enter node name (e.g., node1): " NODE_NAME
    read -p "Enter node IP address: " NODE_IP
    read -p "Is this the first node in the cluster? (yes/no): " IS_FIRST_NODE
    
    if [[ "$IS_FIRST_NODE" == "no" ]]; then
        read -p "Enter first node IP address: " FIRST_NODE_IP
        read -p "Enter first node hostname: " FIRST_NODE_HOSTNAME
    fi
    
    # Cluster configuration
    read -p "Enter total number of nodes in cluster: " TOTAL_NODES
    
    # PostgreSQL configuration
    echo
    echo "PostgreSQL Configuration:"
    read -p "PostgreSQL version (default: 17): " PG_VERSION
    PG_VERSION=${PG_VERSION:-17}
    
    read -s -p "Enter PostgreSQL replication user password: " REPLICATION_PASSWORD
    echo
    read -s -p "Confirm PostgreSQL replication user password: " REPLICATION_PASSWORD_CONFIRM
    echo
    
    if [[ "$REPLICATION_PASSWORD" != "$REPLICATION_PASSWORD_CONFIRM" ]]; then
        log_error "Passwords do not match"
        exit 1
    fi
    
    read -s -p "Enter PostgreSQL database password for paperless: " DB_PASSWORD
    echo
    
    # GlusterFS configuration
    echo
    echo "GlusterFS Configuration:"
    read -p "GlusterFS volume name (default: paperless-volume): " GLUSTER_VOLUME
    GLUSTER_VOLUME=${GLUSTER_VOLUME:-paperless-volume}
    
    # Paperless configuration
    echo
    echo "Paperless-ngx Configuration:"
    read -s -p "Enter Paperless-ngx secret key (generate random if empty): " PAPERLESS_SECRET_KEY
    echo
    
    if [[ -z "$PAPERLESS_SECRET_KEY" ]]; then
        PAPERLESS_SECRET_KEY=$(openssl rand -hex 32)
        log_info "Generated random secret key"
    fi
    
    read -p "Enter Paperless-ngx URL (e.g., https://paperless.example.com): " PAPERLESS_URL
    
    # Save configuration
    cat > /etc/paperless-cluster.conf <<EOF
NODE_NAME=$NODE_NAME
NODE_IP=$NODE_IP
IS_FIRST_NODE=$IS_FIRST_NODE
FIRST_NODE_IP=$FIRST_NODE_IP
FIRST_NODE_HOSTNAME=$FIRST_NODE_HOSTNAME
TOTAL_NODES=$TOTAL_NODES
PG_VERSION=$PG_VERSION
REPLICATION_PASSWORD=$REPLICATION_PASSWORD
DB_PASSWORD=$DB_PASSWORD
GLUSTER_VOLUME=$GLUSTER_VOLUME
PAPERLESS_SECRET_KEY=$PAPERLESS_SECRET_KEY
PAPERLESS_URL=$PAPERLESS_URL
EOF
    
    chmod 600 /etc/paperless-cluster.conf
    log_success "Configuration saved to /etc/paperless-cluster.conf"
}

# Install Docker and Docker Compose
install_docker() {
    log_info "Installing Docker and Docker Compose..."
    
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian"* ]]; then
        apt-get update
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # Add Docker GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "Red Hat"* ]] || [[ "$OS" == "Rocky"* ]]; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        log_error "Unsupported OS: $OS"
        exit 1
    fi
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker and Docker Compose installed"
}

# Install PostgreSQL with pgactive
install_postgresql() {
    log_info "Installing PostgreSQL $PG_VERSION with pgactive extension..."
    
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian"* ]]; then
        # Add PostgreSQL APT repository
        sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        apt-get update
        
        # Install PostgreSQL
        apt-get install -y postgresql-$PG_VERSION postgresql-client-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-server-dev-$PG_VERSION
        
        # Install build dependencies for pgactive
        apt-get install -y git build-essential
        
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "Red Hat"* ]] || [[ "$OS" == "Rocky"* ]]; then
        # Install PostgreSQL repository
        yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        
        # Install PostgreSQL
        yum install -y postgresql$PG_VERSION-server postgresql$PG_VERSION-contrib postgresql$PG_VERSION-devel
        
        # Initialize database
        /usr/pgsql-$PG_VERSION/bin/postgresql-$PG_VERSION-setup initdb
        
        # Install build dependencies
        yum install -y git gcc make
    fi
    
    # Clone and install pgactive extension
    cd /tmp
    git clone https://github.com/aws/pgactive.git
    cd pgactive
    
    # Build and install pgactive
    export PATH=/usr/pgsql-$PG_VERSION/bin:$PATH
    make
    make install
    
    # Configure PostgreSQL for logical replication
    PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"
    if [[ ! -d "$PG_CONFIG_DIR" ]]; then
        PG_CONFIG_DIR="/var/lib/pgsql/$PG_VERSION/data"
    fi
    
    cat >> $PG_CONFIG_DIR/postgresql.conf <<EOF

# Logical replication configuration for pgactive
wal_level = logical
max_replication_slots = 20
max_wal_senders = 20
max_logical_replication_workers = 10
track_commit_timestamp = on
shared_preload_libraries = 'pgactive'

# Network configuration
listen_addresses = '*'

# Performance tuning
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
min_wal_size = 1GB
max_wal_size = 4GB
EOF
    
    # Configure pg_hba.conf for replication
    cat >> $PG_CONFIG_DIR/pg_hba.conf <<EOF

# Replication configuration
host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
EOF
    
    # Restart PostgreSQL
    systemctl restart postgresql-$PG_VERSION
    systemctl enable postgresql-$PG_VERSION
    
    # Create replication user and paperless database
    sudo -u postgres psql <<EOF
CREATE USER replicator WITH REPLICATION LOGIN PASSWORD '$REPLICATION_PASSWORD';
CREATE USER paperless WITH LOGIN PASSWORD '$DB_PASSWORD';
CREATE DATABASE paperless OWNER paperless;
\c paperless
CREATE EXTENSION IF NOT EXISTS pgactive;
EOF
    
    log_success "PostgreSQL $PG_VERSION with pgactive installed"
}

# Install and configure GlusterFS
install_glusterfs() {
    log_info "Installing GlusterFS..."
    
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian"* ]]; then
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:gluster/glusterfs-10
        apt-get update
        apt-get install -y glusterfs-server glusterfs-client
        
    elif [[ "$OS" == "CentOS"* ]] || [[ "$OS" == "Red Hat"* ]] || [[ "$OS" == "Rocky"* ]]; then
        yum install -y centos-release-gluster10
        yum install -y glusterfs-server glusterfs-client
    fi
    
    # Enable and start GlusterFS
    systemctl enable glusterd
    systemctl start glusterd
    
    # Create brick directory
    mkdir -p /data/glusterfs/brick
    
    # Configure firewall for GlusterFS
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --add-service=glusterfs --permanent
        firewall-cmd --add-port=24007-24008/tcp --permanent
        firewall-cmd --add-port=49152-49251/tcp --permanent
        firewall-cmd --reload
    fi
    
    log_success "GlusterFS installed"
}

# Configure GlusterFS cluster
configure_glusterfs() {
    log_info "Configuring GlusterFS cluster..."
    
    if [[ "$IS_FIRST_NODE" == "yes" ]]; then
        log_info "Initializing GlusterFS cluster on first node..."
        
        # Wait for user to confirm other nodes are ready
        echo
        log_warning "Please ensure all other nodes have completed installation before continuing."
        read -p "Press Enter when all nodes are ready..."
        
        # Probe other nodes
        log_info "Adding peer nodes to GlusterFS cluster..."
        for ((i=2; i<=TOTAL_NODES; i++)); do
            read -p "Enter IP address of node$i: " PEER_IP
            gluster peer probe $PEER_IP
        done
        
        # Create replicated volume
        log_info "Creating GlusterFS replicated volume..."
        
        # Build brick list
        BRICK_LIST="$NODE_IP:/data/glusterfs/brick"
        for ((i=2; i<=TOTAL_NODES; i++)); do
            read -p "Enter IP address of node$i (again for volume creation): " PEER_IP
            BRICK_LIST="$BRICK_LIST $PEER_IP:/data/glusterfs/brick"
        done
        
        gluster volume create $GLUSTER_VOLUME replica $TOTAL_NODES $BRICK_LIST force
        gluster volume start $GLUSTER_VOLUME
        
        # Set volume options for better performance
        gluster volume set $GLUSTER_VOLUME performance.cache-size 256MB
        gluster volume set $GLUSTER_VOLUME performance.io-thread-count 32
        gluster volume set $GLUSTER_VOLUME performance.write-behind-window-size 4MB
        gluster volume set $GLUSTER_VOLUME cluster.heal-timeout 10
        gluster volume set $GLUSTER_VOLUME cluster.self-heal-daemon enable
        
    else
        log_info "Joining existing GlusterFS cluster..."
        gluster peer probe $FIRST_NODE_IP
    fi
    
    # Mount GlusterFS volume
    mkdir -p /mnt/glusterfs
    mount -t glusterfs localhost:/$GLUSTER_VOLUME /mnt/glusterfs
    
    # Add to fstab for persistent mounting
    echo "localhost:/$GLUSTER_VOLUME /mnt/glusterfs glusterfs defaults,_netdev 0 0" >> /etc/fstab
    
    log_success "GlusterFS cluster configured"
}

# Configure pgactive replication
configure_pgactive() {
    log_info "Configuring pgactive replication..."
    
    if [[ "$IS_FIRST_NODE" == "yes" ]]; then
        # Create pgactive group on first node
        sudo -u postgres psql -d paperless <<EOF
SELECT pgactive.pgactive_create_group(
    node_name := '$NODE_NAME',
    node_dsn := 'dbname=paperless host=$NODE_IP user=replicator password=$REPLICATION_PASSWORD'
);

SELECT pgactive.pgactive_wait_for_node_ready();
EOF
        
        log_success "pgactive group created on first node"
        
    else
        # Join existing pgactive group
        sudo -u postgres psql -d paperless <<EOF
SELECT pgactive.pgactive_join_group(
    node_name := '$NODE_NAME',
    node_dsn := 'dbname=paperless host=$NODE_IP user=replicator password=$REPLICATION_PASSWORD',
    join_using_dsn := 'dbname=paperless host=$FIRST_NODE_IP user=replicator password=$REPLICATION_PASSWORD'
);

SELECT pgactive.pgactive_wait_for_node_ready();
EOF
        
        log_success "Joined pgactive group"
    fi
}

# Create Docker Compose configuration
create_docker_compose() {
    log_info "Creating Docker Compose configuration for Paperless-ngx..."
    
    mkdir -p /opt/paperless-ngx
    
    cat > /opt/paperless-ngx/docker-compose.yml <<EOF
# MIT License
# Copyright (c) 2024

version: '3.8'

services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redis-data:/data
    networks:
      - paperless-net

  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    depends_on:
      - redis
    ports:
      - "8000:8000"
    volumes:
      - /mnt/glusterfs/data:/usr/src/paperless/data
      - /mnt/glusterfs/media:/usr/src/paperless/media
      - /mnt/glusterfs/export:/usr/src/paperless/export
      - /mnt/glusterfs/consume:/usr/src/paperless/consume
    environment:
      PAPERLESS_REDIS: redis://redis:6379
      PAPERLESS_DBENGINE: postgres
      PAPERLESS_DBHOST: $NODE_IP
      PAPERLESS_DBPORT: 5432
      PAPERLESS_DBNAME: paperless
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: $DB_PASSWORD
      PAPERLESS_SECRET_KEY: $PAPERLESS_SECRET_KEY
      PAPERLESS_URL: $PAPERLESS_URL
      PAPERLESS_OCR_LANGUAGE: eng+deu
      PAPERLESS_TIME_ZONE: Europe/Berlin
      PAPERLESS_CONSUMER_POLLING: 60
      PAPERLESS_TASK_WORKERS: 2
    networks:
      - paperless-net

volumes:
  redis-data:

networks:
  paperless-net:
    driver: bridge
EOF
    
    # Create necessary directories on GlusterFS
    mkdir -p /mnt/glusterfs/{data,media,export,consume}
    
    # Start Paperless-ngx
    cd /opt/paperless-ngx
    docker compose up -d
    
    log_success "Paperless-ngx Docker Compose configuration created"
}

# Create systemd service for monitoring
create_monitoring_service() {
    log_info "Creating monitoring service..."
    
    cat > /usr/local/bin/paperless-cluster-monitor.sh <<'EOF'
#!/bin/bash

# MIT License
# Copyright (c) 2024

source /etc/paperless-cluster.conf

LOG_FILE="/var/log/paperless-cluster-monitor.log"

check_postgresql() {
    if systemctl is-active --quiet postgresql-$PG_VERSION; then
        echo "$(date) - PostgreSQL is running" >> $LOG_FILE
        
        # Check replication status
        REPLICATION_STATUS=$(sudo -u postgres psql -t -c "SELECT * FROM pgactive.pgactive_monitor_subscription_status();" paperless 2>/dev/null)
        if [[ ! -z "$REPLICATION_STATUS" ]]; then
            echo "$(date) - Replication status: Active" >> $LOG_FILE
        else
            echo "$(date) - WARNING: Replication may have issues" >> $LOG_FILE
        fi
    else
        echo "$(date) - ERROR: PostgreSQL is not running" >> $LOG_FILE
        systemctl restart postgresql-$PG_VERSION
    fi
}

check_glusterfs() {
    if systemctl is-active --quiet glusterd; then
        echo "$(date) - GlusterFS is running" >> $LOG_FILE
        
        # Check volume status
        VOLUME_STATUS=$(gluster volume status $GLUSTER_VOLUME 2>/dev/null | grep "Status:" | head -1)
        echo "$(date) - GlusterFS volume status: $VOLUME_STATUS" >> $LOG_FILE
    else
        echo "$(date) - ERROR: GlusterFS is not running" >> $LOG_FILE
        systemctl restart glusterd
    fi
    
    # Check if GlusterFS is mounted
    if ! mountpoint -q /mnt/glusterfs; then
        echo "$(date) - ERROR: GlusterFS not mounted, attempting to mount" >> $LOG_FILE
        mount -t glusterfs localhost:/$GLUSTER_VOLUME /mnt/glusterfs
    fi
}

check_docker() {
    if systemctl is-active --quiet docker; then
        echo "$(date) - Docker is running" >> $LOG_FILE
        
        # Check Paperless-ngx containers
        cd /opt/paperless-ngx
        CONTAINER_STATUS=$(docker compose ps --format "table {{.Service}}\t{{.State}}")
        echo "$(date) - Container status:" >> $LOG_FILE
        echo "$CONTAINER_STATUS" >> $LOG_FILE
    else
        echo "$(date) - ERROR: Docker is not running" >> $LOG_FILE
        systemctl restart docker
    fi
}

# Main monitoring loop
while true; do
    check_postgresql
    check_glusterfs
    check_docker
    sleep 60
done
EOF
    
    chmod +x /usr/local/bin/paperless-cluster-monitor.sh
    
    # Create systemd service
    cat > /etc/systemd/system/paperless-cluster-monitor.service <<EOF
[Unit]
Description=Paperless-ngx Cluster Monitor
After=network.target docker.service postgresql-$PG_VERSION.service glusterd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/paperless-cluster-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable paperless-cluster-monitor
    systemctl start paperless-cluster-monitor
    
    log_success "Monitoring service created and started"
}

# Main installation flow
main() {
    echo
    echo "==========================================="
    echo "  Paperless-ngx Multi-Node Cluster Setup"
    echo "==========================================="
    echo
    
    check_root
    detect_os
    
    # Load existing configuration if available
    if [ -f /etc/paperless-cluster.conf ]; then
        log_info "Found existing configuration"
        source /etc/paperless-cluster.conf
    else
        configure_node
        source /etc/paperless-cluster.conf
    fi
    
    # Installation steps
    install_docker
    install_postgresql
    install_glusterfs
    configure_glusterfs
    configure_pgactive
    create_docker_compose
    create_monitoring_service
    
    echo
    log_success "==========================================="
    log_success "  Paperless-ngx Cluster Installation Complete!"
    log_success "==========================================="
    echo
    echo "Next steps:"
    echo "1. Access Paperless-ngx at: http://$NODE_IP:8000"
    echo "2. Monitor cluster status: journalctl -u paperless-cluster-monitor -f"
    echo "3. Check replication: sudo -u postgres psql -d paperless -c 'SELECT * FROM pgactive.pgactive_monitor_group_membership();'"
    echo "4. Check GlusterFS: gluster volume status $GLUSTER_VOLUME"
    echo
    echo "Configuration saved in: /etc/paperless-cluster.conf"
    echo "Logs available at: /var/log/paperless-cluster-monitor.log"
    echo
}

# Run main function
main "$@"
