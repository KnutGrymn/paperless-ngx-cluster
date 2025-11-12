# Paperless-ngx Multi-Node Cluster - Quick Start Guide

## MIT License
Copyright (c) 2024

## Overview

This guide helps you quickly set up a multi-node Paperless-ngx cluster with:
- PostgreSQL 17 with pgactive for active-active replication
- GlusterFS for distributed file storage
- Automated monitoring and backup
- High availability and automatic failover

## Prerequisites

- 2 or more Linux servers (Ubuntu 20.04+, Debian 11+, RHEL 8+)
- Minimum 4GB RAM and 50GB storage per node
- Network connectivity between all nodes
- Root or sudo access

## Quick Installation

### Step 1: Download Scripts

On all nodes:
```bash
git clone https://github.com/your-repo/paperless-ngx-cluster.git
cd paperless-ngx-cluster
chmod +x *.sh
```

### Step 2: Configure First Node

On the first node:
```bash
sudo ./install-cluster.sh
```

When prompted:
- Node name: `node1`
- Node IP: `<your-ip>`
- First node?: `yes`
- Total nodes: `3` (or your number)
- PostgreSQL version: `17` (press Enter for default)
- Set strong passwords when prompted
- Note down all passwords!

### Step 3: Configure Additional Nodes

On each additional node:
```bash
sudo ./install-cluster.sh
```

When prompted:
- Node name: `node2`, `node3`, etc.
- Node IP: `<this-node-ip>`
- First node?: `no`
- First node IP: `<first-node-ip>`
- Use same passwords as first node

### Step 4: Complete Cluster Setup

Back on the first node, when prompted:
- Enter IPs of all other nodes
- Wait for cluster formation

### Step 5: Verify Installation

Check cluster status:
```bash
sudo ./monitor-cluster.sh
```

Expected output:
- All services: Running ✓
- PostgreSQL replication: Streaming ✓
- GlusterFS peers: Connected ✓
- Docker containers: Running ✓

## Access Paperless-ngx

1. Open browser: `http://<any-node-ip>:8000`
2. Create admin account:
   ```bash
   cd /opt/paperless-ngx
   docker compose exec webserver python manage.py createsuperuser
   ```
3. Login with created credentials

## Basic Operations

### Monitor Cluster
```bash
# One-time check
sudo ./monitor-cluster.sh

# Continuous monitoring
sudo ./monitor-cluster.sh --continuous 30
```

### Create Backup
```bash
sudo ./backup-cluster.sh
```

### Restore Backup
```bash
sudo ./backup-cluster.sh --restore /backup/paperless_backup_*.tar.gz
```

### View Logs
```bash
# Cluster monitor logs
sudo journalctl -u paperless-cluster-monitor -f

# Docker logs
cd /opt/paperless-ngx
docker compose logs -f

# PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-17-main.log
```

## Common Tasks

### Add a New Node

1. Install on new node:
   ```bash
   sudo ./install-cluster.sh
   ```

2. On existing node, add to GlusterFS:
   ```bash
   sudo gluster peer probe <new-node-ip>
   sudo gluster volume add-brick paperless-volume replica 4 <new-node-ip>:/data/glusterfs/brick
   ```

### Remove a Node

1. On node to remove:
   ```bash
   sudo -u postgres psql -d paperless -c "SELECT pgactive.pgactive_leave_group();"
   ```

2. On another node:
   ```bash
   sudo gluster peer detach <node-to-remove>
   ```

### Update Paperless-ngx

On each node (one at a time):
```bash
cd /opt/paperless-ngx
docker compose pull
docker compose down
docker compose up -d
```

## Troubleshooting

### Service Not Running
```bash
sudo systemctl restart postgresql-17
sudo systemctl restart glusterd
sudo systemctl restart docker
```

### Replication Issues
```bash
# Check status
sudo -u postgres psql -d paperless -c "SELECT * FROM pgactive.pgactive_monitor_subscription_status();"

# Check conflicts
sudo -u postgres psql -d paperless -c "SELECT * FROM pgactive.pgactive_monitor_conflict_history();"
```

### GlusterFS Not Mounted
```bash
sudo mount -t glusterfs localhost:/paperless-volume /mnt/glusterfs
```

### Container Issues
```bash
cd /opt/paperless-ngx
docker compose restart
docker compose logs webserver
```

## Security Notes

1. **Change default passwords immediately**
2. **Configure firewall:**
   ```bash
   sudo ufw allow from <cluster-network> to any port 5432
   sudo ufw allow from <cluster-network> to any port 24007:24008
   sudo ufw allow 8000
   sudo ufw enable
   ```
3. **Use HTTPS with reverse proxy (nginx/Apache)**
4. **Enable 2FA in Paperless-ngx settings**
5. **Regular backups to remote location**

## Performance Tips

1. **Use SSDs for better performance**
2. **Ensure low latency between nodes (<5ms)**
3. **Tune PostgreSQL for your RAM:**
   ```bash
   # Edit /etc/postgresql/17/main/postgresql.conf
   shared_buffers = 25% of RAM
   effective_cache_size = 75% of RAM
   ```
4. **Monitor resource usage:**
   ```bash
   sudo ./monitor-cluster.sh --continuous 60
   ```

## Maintenance Schedule

### Daily
- Monitor cluster health: `sudo ./monitor-cluster.sh`
- Check logs for errors

### Weekly
- Create manual backup: `sudo ./backup-cluster.sh`
- Review monitoring metrics

### Monthly
- Update system packages
- Clean old Docker images: `docker image prune -a`
- Vacuum PostgreSQL: `sudo -u postgres psql -d paperless -c "VACUUM ANALYZE;"`

## Getting Help

1. Check full documentation: [README.md](README.md)
2. Review logs: `/var/log/paperless-cluster-monitor.log`
3. Run diagnostics: `sudo ./monitor-cluster.sh`
4. Check service status: `systemctl status <service-name>`

## Quick Reference

| Command | Description |
|---------|-------------|
| `./install-cluster.sh` | Install cluster node |
| `./monitor-cluster.sh` | Check cluster health |
| `./backup-cluster.sh` | Create backup |
| `./backup-cluster.sh --restore <file>` | Restore backup |
| `docker compose ps` | Check containers |
| `gluster volume status` | Check GlusterFS |
| `systemctl status postgresql-17` | Check PostgreSQL |

## Support

- Issues: Create issue in GitHub repository
- Documentation: See [README.md](README.md) for detailed documentation
- pgactive: https://github.com/aws/pgactive
- Paperless-ngx: https://docs.paperless-ngx.com

---
*Version: 1.0.0*
*Last Updated: 2024*
