# TavaBharat Migration - Quick Reference

One-page reference for common tasks and commands.

## Installation (First Time)

```bash
# 1. Clone repository
git clone https://github.com/ChikkaRaviKiran/tavabharat-aws-migration.git
cd tavabharat-aws-migration

# 2. Configure
cp configs/.env.example configs/.env
nano configs/.env  # Edit with your credentials

# 3. Run installer
sudo ./install.sh  # Select option 1 for full installation
```

## Common Commands

### System Status
```bash
tavabharat-status              # Overall system status
htop                           # Resource monitor
df -h                          # Disk space
free -h                        # Memory usage
```

### Service Management
```bash
# Status
sudo systemctl status mssql-server
sudo systemctl status api1
sudo systemctl status api2
sudo systemctl status nginx

# Restart
sudo systemctl restart api1
sudo systemctl restart api2
sudo systemctl restart nginx

# Start/Stop
sudo systemctl start api1
sudo systemctl stop api1
```

### View Logs
```bash
# API logs (live)
sudo journalctl -u api1 -f
sudo journalctl -u api2 -f

# Last 100 lines
sudo journalctl -u api1 -n 100

# Nginx logs
sudo tail -f /var/log/nginx/tavabharat-error.log
sudo tail -f /var/log/nginx/tavabharat-access.log

# Health check logs
tail -f /var/log/tavabharat-health.log
```

### Database Operations
```bash
# Connect
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -C

# List databases
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "SELECT name FROM sys.databases" -C

# Backup database
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
BACKUP DATABASE [TavaBharatDB_Prod] 
TO DISK = '/var/backups/mssql/manual_backup.bak'
WITH COMPRESSION
" -C

# Check database size
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
SELECT name, size/128.0 AS 'Size (MB)' 
FROM sys.master_files WHERE type = 0
" -C
```

### Application Updates

```bash
# Update API 1
sudo systemctl stop api1
# Upload new files to /var/www/api1
sudo systemctl start api1

# Update API 2
sudo tavabharat-update api2
# Upload files
sudo systemctl start api2

# Update Angular UI
# Upload to /var/www/angular
sudo systemctl reload nginx

# Update React UI  
# Upload to /var/www/react
sudo systemctl reload nginx
```

### Monitoring & Maintenance

```bash
# Manual health check
sudo ./monitoring/health-check.sh

# Manual backup
sudo ./monitoring/backup-databases.sh

# View backups
ls -lh /var/backups/mssql/

# Check cron jobs
cat /etc/cron.d/tavabharat-monitoring
```

### Nginx Operations

```bash
# Test configuration
sudo nginx -t

# Reload config (no downtime)
sudo systemctl reload nginx

# Restart Nginx
sudo systemctl restart nginx

# View configuration
sudo cat /etc/nginx/sites-available/tavabharat
```

### Security

```bash
# Check firewall
sudo ufw status

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Check failed login attempts
sudo grep "Failed password" /var/log/auth.log | wc -l

# Active connections
sudo ss -tuln
```

### Troubleshooting

```bash
# Service won't start
sudo journalctl -u api1 -n 50 --no-pager

# High memory usage
free -h
ps aux --sort=-%mem | head -10

# High CPU usage
uptime
ps aux --sort=-%cpu | head -10

# Disk space issues
df -h
sudo du -sh /* | sort -h

# Network issues
curl http://localhost:5000
curl http://localhost/api/v1
```

## File Locations

### Applications
```
/var/www/api1/              # API 1 files
/var/www/api2/              # API 2 files  
/var/www/angular/           # Angular UI
/var/www/react/             # React UI
```

### Configuration
```
configs/.env                # Environment variables
/etc/systemd/system/api1.service  # API 1 service
/etc/systemd/system/api2.service  # API 2 service
/etc/nginx/sites-available/tavabharat  # Nginx config
```

### Logs
```
/var/log/tavabharat/        # Application logs
/var/log/nginx/             # Nginx logs
journalctl -u api1          # API 1 logs (systemd)
journalctl -u api2          # API 2 logs (systemd)
```

### Backups
```
/var/backups/mssql/         # Database backups
database/backups/           # Migration backups
```

## Network Ports

| Service | Port | Access |
|---------|------|--------|
| SSH | 22 | External |
| HTTP | 80 | External |
| HTTPS | 443 | External |
| API 1 | 5000 | Localhost only |
| API 2 | 5001 | Localhost only |
| MSSQL | 1433 | Localhost only |

## URLs (after Nginx setup)

```
http://YOUR_IP/                # Angular app
http://YOUR_IP/admin           # React admin
http://YOUR_IP/api/v1/*        # API 1
http://YOUR_IP/api/v2/*        # API 2
```

## Emergency Procedures

### API Not Responding
```bash
# 1. Check if running
sudo systemctl status api1

# 2. Check logs
sudo journalctl -u api1 -n 50

# 3. Restart
sudo systemctl restart api1

# 4. If still failing, check database
sqlcmd -S localhost -U sa -P 'PASSWORD' -C
```

### Database Not Accessible
```bash
# 1. Check service
sudo systemctl status mssql-server

# 2. Check logs
sudo journalctl -u mssql-server -n 50

# 3. Restart
sudo systemctl restart mssql-server

# 4. Check memory
free -h
# If low, reduce MSSQL memory:
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512
sudo systemctl restart mssql-server
```

### Nginx 502 Error
```bash
# 1. Check APIs
sudo systemctl status api1 api2

# 2. Start APIs if stopped
sudo systemctl start api1
sudo systemctl start api2

# 3. Check if listening
sudo ss -tuln | grep 5000
sudo ss -tuln | grep 5001

# 4. Test directly
curl http://localhost:5000
curl http://localhost:5001
```

### Out of Disk Space
```bash
# 1. Check usage
df -h

# 2. Clean old backups
find /var/backups/mssql -name "*.bak" -mtime +7 -delete

# 3. Clean logs
sudo find /var/log -name "*.log" -mtime +30 -delete

# 4. Clean package cache
sudo apt-get clean
```

### High Memory Usage
```bash
# 1. Check what's using memory
free -h
ps aux --sort=-%mem | head -10

# 2. Reduce MSSQL memory
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512
sudo systemctl restart mssql-server

# 3. Restart services if needed
sudo systemctl restart api1
sudo systemctl restart api2
```

## Resource Limits (2GB Server)

| Component | Memory Limit | Notes |
|-----------|--------------|-------|
| MSSQL | 768MB | Configured in script |
| API 1 | ~200MB | Typical .NET API |
| API 2 | ~200MB | Typical .NET API |
| Nginx | ~50MB | Minimal |
| System | ~500MB | OS + other |
| Swap | 2GB | Emergency overflow |

## Quick Fixes

```bash
# Fix: All services slow
sudo systemctl restart mssql-server api1 api2 nginx

# Fix: Can't connect to database
sudo systemctl restart mssql-server

# Fix: APIs not responding
sudo systemctl restart api1 api2

# Fix: Website not loading
sudo systemctl restart nginx

# Fix: High memory
sudo sysctl -w vm.drop_caches=3  # Clear cache
sudo systemctl restart mssql-server  # Restart heaviest service

# Fix: SSL certificate expired
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

## Support

- 📖 Full Documentation: `README.md`
- 🔧 Detailed Guide: `DETAILED_GUIDE.md`
- ❓ Troubleshooting: `TROUBLESHOOTING.md`
- 🔒 Security: `SECURITY.md`
- 🐛 Issues: GitHub Issues

## Backup & Restore

### Manual Backup
```bash
# Database
sudo ./monitoring/backup-databases.sh

# Configurations
sudo tar -czf /tmp/config-backup.tar.gz \
    /var/www/api*/appsettings*.json \
    /var/www/api*/.env \
    /etc/nginx/sites-available/tavabharat \
    /etc/systemd/system/api*.service
```

### Restore Database
```bash
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
RESTORE DATABASE [TavaBharatDB_Prod]
FROM DISK = '/var/backups/mssql/TavaBharatDB_Prod_TIMESTAMP.bak'
WITH REPLACE
" -C
```

---

**Keep this reference handy for daily operations!**
