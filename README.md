# Paperless-ngx Multi-Node Cluster Documentation

[![GitHub](https://img.shields.io/badge/github-KnutGrymn%2Fpaperless--ngx--cluster-blue)](https://github.com/KnutGrymn/paperless-ngx-cluster)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Paperless-ngx](https://img.shields.io/badge/paperless--ngx-compatible-brightgreen)](https://github.com/paperless-ngx/paperless-ngx)

![Shell Check](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Shell%20Script%20Tests/badge.svg)
![Markdown Lint](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Markdown%20Lint/badge.svg)
![Integration Tests](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Integration%20Tests/badge.svg)

A comprehensive solution for deploying Paperless-ngx in a high-availability multi-node cluster configuration with load balancing and data replication.

## 📦 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Monitoring](#monitoring)
7. [Backup and Restore](#backup-and-restore)
8. [Maintenance](#maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Security Considerations](#security-considerations)
11. [Performance Tuning](#performance-tuning)
12. [Disaster Recovery](#disaster-recovery)

## 🎯 Overview

This documentation describes a highly available, multi-node Paperless-ngx cluster implementation using:

- **PostgreSQL 17** with **pgactive** extension for active-active database replication
- **GlusterFS** for distributed file storage
- **Docker** and **Docker Compose** for containerization
- **Redis** for caching and task queuing
- Automated monitoring and backup solutions

### Key Features

- **Active-Active Replication**: All nodes can accept writes simultaneously
- **Distributed Storage**: Files are replicated across all nodes
- **Automatic Failover**: Continues operating if nodes fail
- **Conflict Resolution**: Automatic handling of concurrent updates
- **Zero-Downtime Updates**: Rolling updates without service interruption
- **Comprehensive Monitoring**: Real-time health checks and alerts
- **Automated Backups**: Scheduled backups with retention policies

## 📋 Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Load Balancer (Optional)                 │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────▼───────┐                         ┌────────▼──────┐
│    Node 1     │                         │    Node 2     │
├───────────────┤                         ├───────────────┤
│ Paperless-ngx │◄────────────────────────► Paperless-ngx │
│   (Docker)    │                         │   (Docker)    │
├───────────────┤                         ├───────────────┤
│    Redis      │                         │    Redis      │
├───────────────┤                         ├───────────────┤
│  PostgreSQL   │◄──── pgactive ─────────►  PostgreSQL   │
│  + pgactive   │      Replication        │  + pgactive   │
├───────────────┤                         ├───────────────┤
│   GlusterFS   │◄──── File Sync ────────►   GlusterFS   │
└───────────────┘                         └───────────────┘
```

### Data Flow

1. **Document Upload**: User uploads document to any node
2. **Processing**: Paperless-ngx processes and OCRs the document
3. **Database Sync**: Metadata is replicated via pgactive to all nodes
4. **File Sync**: Document files are replicated via GlusterFS
5. **Access**: Document is accessible from any node

## Prerequisites

### Hardware Requirements

**Minimum per node:**
- CPU: 2 cores
- RAM: 4 GB
- Storage: 50 GB (adjust based on document volume)
- Network: 1 Gbps interconnect recommended

**Recommended per node:**
- CPU: 4+ cores
- RAM: 8+ GB
- Storage: 100+ GB SSD
- Network: 10 Gbps interconnect

### Software Requirements

- Operating System: Ubuntu 20.04/22.04, Debian 11/12, RHEL 8/9, Rocky Linux 8/9
- Root or sudo access
- Internet connectivity for package installation

### Network Requirements

- All nodes must be able to communicate with each other
- Required ports:
  - 5432: PostgreSQL
  - 24007-24008: GlusterFS management
  - 49152-49251: GlusterFS bricks
  - 8000: Paperless-ngx web interface
  - 6379: Redis (internal)

## 🚀 Installation

### Step 1: Prepare All Nodes

On each node, ensure the system is up to date:

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# RHEL/Rocky/CentOS
sudo yum update -y
```

### Step 2: Configure Hostnames

Edit `/etc/hosts` on all nodes to include all cluster members:

```bash
192.168.1.10 node1 node1.example.com
192.168.1.11 node2 node2.example.com
192.168.1.12 node3 node3.example.com
```

### Step 3: Install First Node

On the first node:

```bash
# Download the installation script
wget https://raw.githubusercontent.com/KnutGrymn/paperless-cluster/main/install-cluster.sh
chmod +x install-cluster.sh

# Run installation
sudo ./install-cluster.sh
```

Follow the prompts:
1. Enter node name (e.g., `node1`)
2. Enter node IP address
3. Confirm this is the first node: `yes`
4. Enter total number of nodes in cluster
5. Set PostgreSQL version (default: 17)
6. Create strong passwords for database users
7. Configure GlusterFS volume name
8. Set Paperless-ngx secret key (or let it generate)
9. Enter the public URL for Paperless-ngx

### Step 4: Install Additional Nodes

On each additional node:

```bash
# Download and run installation
wget https://raw.githubusercontent.com/KnutGrymn/paperless-cluster/main/install-cluster.sh
chmod +x install-cluster.sh
sudo ./install-cluster.sh
```

Follow the prompts:
1. Enter node name (e.g., `node2`, `node3`)
2. Enter node IP address
3. Confirm this is NOT the first node: `no`
4. Enter first node's IP address and hostname
5. Use the same passwords and configuration as the first node

### Step 5: Complete Cluster Setup

After all nodes are installed, on the first node:

1. The script will prompt to add peer nodes to GlusterFS
2. Enter the IP addresses of all other nodes when prompted
3. The script will create the replicated volume

### Step 6: Verify Installation

Check cluster status on any node:

```bash
# Check monitoring
sudo ./monitor-cluster.sh

# Check PostgreSQL replication
sudo -u postgres psql -d paperless -c "SELECT * FROM pgactive.pgactive_monitor_group_membership();"

# Check GlusterFS
sudo gluster volume status

# Check Docker containers
cd /opt/paperless-ngx && docker compose ps
```

## 🔧 Configuration

### Main Configuration File

The cluster configuration is stored in `/etc/paperless-cluster.conf`:

```bash
NODE_NAME=node1
NODE_IP=192.168.1.10
IS_FIRST_NODE=yes
FIRST_NODE_IP=192.168.1.10
FIRST_NODE_HOSTNAME=node1
TOTAL_NODES=3
PG_VERSION=17
REPLICATION_PASSWORD=<encrypted>
DB_PASSWORD=<encrypted>
GLUSTER_VOLUME=paperless-volume
PAPERLESS_SECRET_KEY=<secret>
PAPERLESS_URL=https://paperless.example.com
```

### PostgreSQL Configuration

PostgreSQL is configured for logical replication in `/etc/postgresql/17/main/postgresql.conf`:

```ini
# Logical replication settings
wal_level = logical
max_replication_slots = 20
max_wal_senders = 20
max_logical_replication_workers = 10
track_commit_timestamp = on
shared_preload_libraries = 'pgactive'

# Performance settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
```

### Docker Compose Configuration

Located at `/opt/paperless-ngx/docker-compose.yml`:

```yaml
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redis-data:/data

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
      PAPERLESS_DBHOST: ${NODE_IP}
      # ... additional settings
```

### GlusterFS Volume Configuration

View current configuration:

```bash
sudo gluster volume info paperless-volume
```

Modify volume options:

```bash
# Increase cache size for better performance
sudo gluster volume set paperless-volume performance.cache-size 512MB

# Enable self-healing
sudo gluster volume set paperless-volume cluster.self-heal-daemon enable
```

## Monitoring

### Manual Monitoring

Run a single monitoring check:

```bash
sudo ./monitor-cluster.sh
```

### Continuous Monitoring

Run monitoring dashboard with auto-refresh:

```bash
# Refresh every 30 seconds
sudo ./monitor-cluster.sh --continuous 30
```

### Prometheus Metrics Export

Export metrics for Prometheus monitoring:

```bash
sudo ./monitor-cluster.sh --export-metrics
```

Metrics are saved to `/var/lib/paperless-cluster/metrics.prom`

### System Service Monitoring

The cluster includes an automatic monitoring service:

```bash
# View monitoring logs
sudo journalctl -u paperless-cluster-monitor -f

# Check service status
sudo systemctl status paperless-cluster-monitor

# Restart monitoring service
sudo systemctl restart paperless-cluster-monitor
```

### Monitoring Output Examples

```
=== System Resources ===
✓ CPU Usage: 35.2%
✓ Memory Usage: 42.8%
✓ Disk Usage:
  ✓ /: 45%
  ✓ /mnt/glusterfs: 23%

=== PostgreSQL Status ===
✓ PostgreSQL service: Running
✓ Database connectivity: OK
  Database size: 1.2 GB
  Active connections: 5

=== pgactive Replication Status ===
  Group Membership:
  ✓ node1 (ID: 1) - Local Node
  ○ node2 (ID: 2) - Remote Node
  ○ node3 (ID: 3) - Remote Node
  
  Subscription Status:
  ✓ sub_node1_node2: streaming
  ✓ sub_node1_node3: streaming
```

## Backup and Restore

### Manual Backup

Create a backup:

```bash
sudo ./backup-cluster.sh
```

### Scheduled Backups

Create a cron job for automatic backups:

```bash
# Edit crontab
sudo crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/backup-cluster.sh >> /var/log/paperless-backup.log 2>&1
```

### Backup to Remote Storage

Configure S3 backup:

```bash
# Set environment variables
export REMOTE_BACKUP_LOCATION=s3://my-bucket/paperless-backups
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# Run backup
sudo -E ./backup-cluster.sh
```

Configure rsync backup:

```bash
export REMOTE_BACKUP_LOCATION=user@backup-server:/backups/paperless
sudo -E ./backup-cluster.sh
```

### Restore from Backup

Restore a specific backup:

```bash
sudo ./backup-cluster.sh --restore /backup/paperless-cluster/paperless_backup_node1_20240101_120000.tar.gz
```

### Backup Contents

Each backup includes:
- PostgreSQL database dump
- PostgreSQL configuration
- pgactive replication status
- GlusterFS configuration and data
- Docker configuration
- Paperless-ngx data and media files
- System configuration

## 🛡️ Maintenance

### Updating Paperless-ngx

1. **Update one node at a time:**

```bash
# Stop Paperless on node
cd /opt/paperless-ngx
docker compose down

# Pull new image
docker compose pull

# Start with new version
docker compose up -d

# Check logs
docker compose logs -f
```

2. **Repeat for each node**

### PostgreSQL Maintenance

**Vacuum and analyze database:**

```bash
sudo -u postgres psql -d paperless -c "VACUUM ANALYZE;"
```

**Check replication lag:**

```bash
sudo -u postgres psql -d paperless -c "
SELECT node_name, 
       subscription_name, 
       subscription_status,
       received_lsn
FROM pgactive.pgactive_monitor_subscription_status();"
```

**View conflict history:**

```bash
sudo -u postgres psql -d paperless -c "
SELECT * FROM pgactive.pgactive_monitor_conflict_history() 
ORDER BY conflict_time DESC LIMIT 10;"
```

### GlusterFS Maintenance

**Check volume health:**

```bash
sudo gluster volume heal paperless-volume info
```

**Start healing process:**

```bash
sudo gluster volume heal paperless-volume
```

**Rebalance volume after adding nodes:**

```bash
sudo gluster volume rebalance paperless-volume start
```

**Check rebalance status:**

```bash
sudo gluster volume rebalance paperless-volume status
```

### Docker Maintenance

**Clean up unused resources:**

```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -a -f

# Remove unused volumes (careful!)
docker volume prune -f

# Clean build cache
docker builder prune -f
```

**View resource usage:**

```bash
docker system df
```

## 🆘 Troubleshooting

### Common Issues and Solutions

#### PostgreSQL Replication Issues

**Problem:** Replication lag is increasing

```bash
# Check replication status
sudo -u postgres psql -d paperless -c "SELECT * FROM pgactive.pgactive_monitor_subscription_status();"

# Check for long-running queries
sudo -u postgres psql -d paperless -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';"

# Cancel long-running query
sudo -u postgres psql -d paperless -c "SELECT pg_cancel_backend(PID);"
```

**Problem:** Node not joining pgactive group

```bash
# Check pgactive extension
sudo -u postgres psql -d paperless -c "SELECT * FROM pg_extension WHERE extname = 'pgactive';"

# Manually rejoin group
sudo -u postgres psql -d paperless -c "
SELECT pgactive.pgactive_leave_group();
SELECT pgactive.pgactive_join_group(
    node_name := 'node2',
    node_dsn := 'dbname=paperless host=192.168.1.11 user=replicator password=xxx',
    join_using_dsn := 'dbname=paperless host=192.168.1.10 user=replicator password=xxx'
);"
```

#### GlusterFS Issues

**Problem:** GlusterFS volume not mounting

```bash
# Check glusterd service
sudo systemctl status glusterd

# Check volume status
sudo gluster volume status paperless-volume

# Force mount
sudo mount -t glusterfs localhost:/paperless-volume /mnt/glusterfs

# Check logs
sudo tail -f /var/log/glusterfs/mnt-glusterfs.log
```

**Problem:** Split-brain in GlusterFS

```bash
# Identify split-brain files
sudo gluster volume heal paperless-volume info split-brain

# Resolve by choosing a source
sudo gluster volume heal paperless-volume split-brain source-brick node1:/data/glusterfs/brick

# Or resolve manually file by file
sudo gluster volume heal paperless-volume split-brain entry /path/to/file
```

#### Docker/Paperless Issues

**Problem:** Paperless web interface not accessible

```bash
# Check container status
cd /opt/paperless-ngx
docker compose ps

# View logs
docker compose logs webserver

# Restart containers
docker compose restart

# Check port binding
sudo netstat -tulpn | grep 8000
```

**Problem:** Document processing stuck

```bash
# Check Redis queue
docker compose exec redis redis-cli LLEN paperless:queue:default

# Clear stuck tasks (use with caution)
docker compose exec redis redis-cli FLUSHALL

# Restart worker
docker compose restart webserver
```

### Log Locations

- **PostgreSQL:** `/var/log/postgresql/postgresql-17-main.log`
- **GlusterFS:** `/var/log/glusterfs/`
- **Docker:** `docker compose logs` or `/var/lib/docker/containers/*/`
- **Cluster Monitor:** `/var/log/paperless-cluster-monitor.log`
- **System:** `journalctl -u <service-name>`

## 🛡️ Security Considerations

### Network Security

1. **Firewall Configuration:**

```bash
# Configure UFW (Ubuntu)
sudo ufw allow from 192.168.1.0/24 to any port 5432  # PostgreSQL
sudo ufw allow from 192.168.1.0/24 to any port 24007:24008  # GlusterFS management
sudo ufw allow from 192.168.1.0/24 to any port 49152:49251  # GlusterFS bricks
sudo ufw allow 8000  # Paperless web (restrict as needed)
```

2. **SSL/TLS Configuration:**

Use a reverse proxy (nginx/Apache) with SSL certificates:

```nginx
server {
    listen 443 ssl http2;
    server_name paperless.example.com;
    
    ssl_certificate /etc/ssl/certs/paperless.crt;
    ssl_certificate_key /etc/ssl/private/paperless.key;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Database Security

1. **Encrypt replication traffic:**

Edit PostgreSQL configuration to require SSL:

```ini
ssl = on
ssl_cert_file = '/etc/postgresql/17/main/server.crt'
ssl_key_file = '/etc/postgresql/17/main/server.key'
```

2. **Restrict pg_hba.conf:**

```
# TYPE  DATABASE    USER        ADDRESS                 METHOD
hostssl replication replicator  192.168.1.0/24         md5
hostssl paperless   paperless   192.168.1.0/24         md5
```

### Access Control

1. **Create Paperless admin user:**

```bash
cd /opt/paperless-ngx
docker compose exec webserver python manage.py createsuperuser
```

2. **Enable 2FA in Paperless:**

Login to web interface → Settings → Security → Enable 2FA

### Backup Encryption

Encrypt backups before storing:

```bash
# Encrypt backup
gpg --cipher-algo AES256 --symmetric backup.tar.gz

# Decrypt backup
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

## Performance Tuning

### PostgreSQL Optimization

1. **Tune shared_buffers based on available RAM:**

```ini
# For 8GB RAM system
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
work_mem = 10MB
```

2. **Optimize for SSDs:**

```ini
random_page_cost = 1.1
effective_io_concurrency = 200
```

3. **Tune checkpoint settings:**

```ini
checkpoint_completion_target = 0.9
wal_buffers = 16MB
min_wal_size = 2GB
max_wal_size = 8GB
```

### GlusterFS Optimization

```bash
# Increase cache sizes
sudo gluster volume set paperless-volume performance.cache-size 1GB
sudo gluster volume set paperless-volume performance.write-behind-window-size 8MB

# Optimize for small files
sudo gluster volume set paperless-volume performance.readdir-ahead on
sudo gluster volume set paperless-volume performance.io-cache on

# Tune network settings
sudo gluster volume set paperless-volume network.ping-timeout 10
sudo gluster volume set paperless-volume network.tcp-window-size 1MB
```

### Docker Optimization

1. **Limit container resources:**

```yaml
services:
  webserver:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G
```

2. **Use Docker logging driver:**

```yaml
services:
  webserver:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### System Optimization

1. **Tune kernel parameters:**

```bash
# Edit /etc/sysctl.conf
cat >> /etc/sysctl.conf <<EOF
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000

# File system optimizations
fs.file-max = 2097152
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply settings
sudo sysctl -p
```

2. **Configure I/O scheduler for SSDs:**

```bash
echo noop | sudo tee /sys/block/sda/queue/scheduler
```

## Disaster Recovery

### Node Failure Scenarios

#### Single Node Failure

The cluster continues operating normally:

1. Other nodes handle all traffic
2. GlusterFS maintains data availability
3. pgactive replication queues changes

Recovery steps:
```bash
# Fix failed node
# Restart services
sudo systemctl start postgresql-17
sudo systemctl start glusterd
sudo systemctl start docker

# Check replication catch-up
sudo ./monitor-cluster.sh
```

#### Multiple Node Failure

If majority of nodes fail:

1. **Identify surviving node with most recent data**
2. **Promote to temporary single-node operation:**

```bash
# On surviving node
# Disable pgactive subscriptions temporarily
sudo -u postgres psql -d paperless -c "
SELECT pgactive.pgactive_pause_all_subscriptions();"

# Continue operations in degraded mode
```

3. **Rebuild failed nodes and rejoin cluster**

### Complete Cluster Recovery

If all nodes fail:

1. **Restore from backup on first node:**

```bash
sudo ./backup-cluster.sh --restore /path/to/latest-backup.tar.gz
```

2. **Recreate pgactive group:**

```bash
sudo -u postgres psql -d paperless -c "
SELECT pgactive.pgactive_create_group(
    node_name := 'node1',
    node_dsn := 'dbname=paperless host=node1 user=replicator password=xxx'
);"
```

3. **Rebuild other nodes and join group**

### Data Corruption Recovery

1. **Identify corrupted data:**

```bash
# Check PostgreSQL
sudo -u postgres psql -d paperless -c "
SELECT schemaname, tablename 
FROM pg_tables 
WHERE schemaname = 'public';" | while read schema table; do
    sudo -u postgres psql -d paperless -c "SELECT COUNT(*) FROM $table;" || echo "Error in $table"
done

# Check GlusterFS
sudo gluster volume heal paperless-volume info
```

2. **Restore from backup or replica:**

```bash
# If one node has good data, sync from it
# Stop services on corrupted node
sudo systemctl stop postgresql-17

# Re-sync database
pg_basebackup -h good-node -D /var/lib/postgresql/17/main -U replicator -W

# Restart and rejoin
sudo systemctl start postgresql-17
```

### Monitoring Recovery Progress

```bash
# Monitor replication catch-up
watch -n 5 "sudo -u postgres psql -d paperless -c 'SELECT * FROM pgactive.pgactive_monitor_subscription_status();'"

# Monitor GlusterFS healing
watch -n 10 "sudo gluster volume heal paperless-volume info"

# Check overall cluster health
sudo ./monitor-cluster.sh --continuous 30
```

## Advanced Topics

### Adding New Nodes to Existing Cluster

1. **Install new node:**

```bash
sudo ./install-cluster.sh
# Follow prompts, specify it's NOT the first node
```

2. **Add to GlusterFS volume:**

```bash
# On existing node
sudo gluster peer probe new-node-ip

# Add brick to volume
sudo gluster volume add-brick paperless-volume replica 4 new-node-ip:/data/glusterfs/brick force

# Rebalance data
sudo gluster volume rebalance paperless-volume start
```

3. **Join pgactive group:**

Already handled by installation script

### Removing Nodes from Cluster

1. **Remove from pgactive:**

```bash
# On node to remove
sudo -u postgres psql -d paperless -c "SELECT pgactive.pgactive_leave_group();"
```

2. **Remove from GlusterFS:**

```bash
# On another node
sudo gluster volume remove-brick paperless-volume replica 2 node-to-remove:/data/glusterfs/brick force

# Remove peer
sudo gluster peer detach node-to-remove
```

3. **Update configuration on remaining nodes**

### Load Balancing

Configure HAProxy for load balancing:

```
global
    maxconn 4096
    
defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    
frontend paperless_frontend
    bind *:443 ssl crt /etc/ssl/paperless.pem
    default_backend paperless_backend
    
backend paperless_backend
    balance roundrobin
    option httpchk GET /api/
    server node1 192.168.1.10:8000 check
    server node2 192.168.1.11:8000 check
    server node3 192.168.1.12:8000 check
```

### Monitoring Integration

#### Prometheus Configuration

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'paperless-cluster'
    static_configs:
      - targets:
        - 'node1:9090'
        - 'node2:9090'
        - 'node3:9090'
    metrics_path: '/metrics'
    scrape_interval: 30s
```

#### Grafana Dashboard

Import dashboard JSON for visualization (create custom dashboard with queries for the exported metrics)

### Automation with Ansible

Create Ansible playbook for cluster management:

```yaml
---
- name: Paperless Cluster Management
  hosts: paperless_cluster
  become: yes
  tasks:
    - name: Ensure services are running
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - postgresql-17
        - glusterd
        - docker
        - paperless-cluster-monitor
    
    - name: Check cluster health
      command: /usr/local/bin/monitor-cluster.sh
      register: health_check
    
    - name: Display health status
      debug:
        msg: "{{ health_check.stdout }}"
```

## Support and Contribution

### Getting Help

1. Check the troubleshooting section
2. Review logs in `/var/log/paperless-cluster-monitor.log`
3. Run diagnostic: `sudo ./monitor-cluster.sh`
4. Check pgactive documentation: https://github.com/aws/pgactive
5. Check Paperless-ngx documentation: https://docs.paperless-ngx.com

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

### License

This project is licensed under the MIT License - see the LICENSE file for details.

## Appendix

### A. Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_NAME` | Name of the current node | Required |
| `NODE_IP` | IP address of current node | Required |
| `PG_VERSION` | PostgreSQL version | 17 |
| `GLUSTER_VOLUME` | GlusterFS volume name | paperless-volume |
| `BACKUP_DIR` | Backup directory | /backup/paperless-cluster |
| `RETENTION_DAYS` | Backup retention period | 30 |

### B. Port Reference

| Port | Service | Protocol |
|------|---------|----------|
| 5432 | PostgreSQL | TCP |
| 6379 | Redis | TCP |
| 8000 | Paperless-ngx | TCP |
| 24007-24008 | GlusterFS Management | TCP |
| 49152-49251 | GlusterFS Bricks | TCP |
| 111 | Portmapper | TCP/UDP |

### C. Command Quick Reference

```bash
# Cluster Status
sudo ./monitor-cluster.sh

# Create Backup
sudo ./backup-cluster.sh

# Restore Backup
sudo ./backup-cluster.sh --restore <backup-file>

# PostgreSQL Status
sudo -u postgres psql -d paperless -c "SELECT * FROM pgactive.pgactive_monitor_group_membership();"

# GlusterFS Status
sudo gluster volume status paperless-volume

# Docker Status
cd /opt/paperless-ngx && docker compose ps

# View Logs
sudo journalctl -u paperless-cluster-monitor -f
tail -f /var/log/paperless-cluster-monitor.log

# Restart Services
sudo systemctl restart postgresql-17
sudo systemctl restart glusterd
cd /opt/paperless-ngx && docker compose restart
```

### D. Troubleshooting Flowchart

```
Problem Detected
    │
    ├─> Check monitor-cluster.sh output
    │       │
    │       ├─> PostgreSQL Issue?
    │       │   └─> Check logs, verify pgactive status
    │       │
    │       ├─> GlusterFS Issue?
    │       │   └─> Check volume status, heal if needed
    │       │
    │       └─> Docker Issue?
    │           └─> Check container logs, restart if needed
    │
    ├─> Check system resources
    │   └─> CPU, Memory, Disk space adequate?
    │
    ├─> Check network connectivity
    │   └─> All nodes reachable?
    │
    └─> Check recent changes
        └─> Rollback if necessary
```

---

*Last Updated: 2024*
*Version: 1.0.0*
