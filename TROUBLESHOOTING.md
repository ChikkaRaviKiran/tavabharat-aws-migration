# TavaBharat Migration - Troubleshooting Guide

Quick solutions to common issues during and after migration.

## Table of Contents

- [Server Setup Issues](#server-setup-issues)
- [MSSQL Installation Issues](#mssql-installation-issues)
- [Database Migration Issues](#database-migration-issues)
- [API Deployment Issues](#api-deployment-issues)
- [UI Deployment Issues](#ui-deployment-issues)
- [Nginx Configuration Issues](#nginx-configuration-issues)
- [SSL Certificate Issues](#ssl-certificate-issues)
- [Performance Issues](#performance-issues)
- [Monitoring Issues](#monitoring-issues)
- [General System Issues](#general-system-issues)

## Server Setup Issues

### Issue: Swap file creation fails

**Symptoms:**
```
fallocate: fallocate failed: No space left on device
```

**Solution:**
```bash
# Check available space
df -h

# If space available, try alternative method
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Issue: Firewall blocks needed ports

**Symptoms:**
- Can't access server via HTTP/HTTPS
- UFW blocks connections

**Solution:**
```bash
# Check current rules
sudo ufw status numbered

# Allow needed ports
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 80/tcp  # HTTP
sudo ufw allow 443/tcp # HTTPS

# Reload firewall
sudo ufw reload

# Also check Lightsail firewall in AWS console
```

### Issue: Permission denied errors

**Symptoms:**
```
mkdir: cannot create directory '/var/www/api1': Permission denied
```

**Solution:**
```bash
# Ensure running with sudo
sudo ./1-server-setup.sh

# Fix permissions if needed
sudo chown -R ubuntu:ubuntu /var/www
sudo chown -R ubuntu:ubuntu /var/log/tavabharat
```

## MSSQL Installation Issues

### Issue: MSSQL service won't start

**Symptoms:**
```
Job for mssql-server.service failed
```

**Solution:**
```bash
# Check detailed logs
sudo journalctl -u mssql-server -n 100 --no-pager

# Common fix: Check password complexity
# Password must have:
# - At least 8 characters
# - Uppercase letters
# - Lowercase letters
# - Digits
# - Special characters

# Try reconfiguring
sudo /opt/mssql/bin/mssql-conf setup

# Check memory limits
free -h
sudo /opt/mssql/bin/mssql-conf get memory.memorylimitmb

# If out of memory, reduce limit
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512
sudo systemctl restart mssql-server
```

### Issue: Cannot connect to MSSQL

**Symptoms:**
```
Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : Login timeout expired
```

**Solution:**
```bash
# Check if service is running
sudo systemctl status mssql-server

# Check if listening on port
sudo ss -tuln | grep 1433

# Test connection with -C flag (trust certificate)
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -C

# If still fails, check firewall
sudo ufw status
sudo ufw allow from 127.0.0.1 to any port 1433
```

### Issue: MSSQL uses too much memory

**Symptoms:**
- System running out of memory
- OOM (Out of Memory) killer terminating processes

**Solution:**
```bash
# Check current memory usage
free -h

# Check MSSQL memory limit
sudo /opt/mssql/bin/mssql-conf get memory.memorylimitmb

# Reduce MSSQL memory (for 2GB server, use 512-768MB)
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512
sudo systemctl restart mssql-server

# Monitor
watch -n 2 free -h
```

## Database Migration Issues

### Issue: sqlpackage export fails

**Symptoms:**
```
Error SQL72014: .Net SqlClient Data Provider: Msg 40613
The service is currently busy
```

**Solution:**
```bash
# Azure SQL may be throttling. Wait and retry.

# Check Azure SQL firewall rules
# Add your server IP to allowed IPs in Azure Portal

# Try with longer timeout
sqlpackage /Action:Export \
  /SourceServerName:"server.database.windows.net" \
  /SourceDatabaseName:"database" \
  /SourceUser:"user" \
  /SourcePassword:"password" \
  /SourceTrustServerCertificate:True \
  /TargetFile:"output.bacpac" \
  /p:CommandTimeout=600

# Alternative: Export from Azure Portal
# Portal → Database → Export → Download
```

### Issue: Import fails - disk space

**Symptoms:**
```
Error: There is not enough space on the disk
```

**Solution:**
```bash
# Check disk space
df -h

# Clean up if needed
sudo apt-get clean
sudo apt-get autoremove

# Remove old logs
sudo find /var/log -name "*.log" -type f -mtime +7 -delete

# Move .bacpac to external storage if needed
# Or use a larger Lightsail instance temporarily
```

### Issue: Import fails - database too large

**Symptoms:**
```
Database size exceeds the maximum allowed size (10 GB)
```

**Solution:**
```bash
# MSSQL Express has 10GB per database limit

# Option 1: Compress/clean source database
# - Remove old logs
# - Archive historical data
# - Shrink database in Azure

# Option 2: Split into multiple databases
# - Separate by modules/features
# - Use database per tenant pattern

# Option 3: Upgrade to MSSQL Standard (requires license)
```

### Issue: Row counts don't match

**Symptoms:**
- Validation shows different row counts
- Missing data after migration

**Solution:**
```bash
# Re-run validation
sqlcmd -S localhost -U sa -P 'PASSWORD' -d TavaBharatDB_Prod \
  -i database/validate-migration.sql -C

# Check for failed constraints
sqlcmd -S localhost -U sa -P 'PASSWORD' -d TavaBharatDB_Prod -Q "
SELECT object_name(parent_object_id) as TableName, name as ConstraintName 
FROM sys.foreign_keys WHERE is_disabled = 1
" -C

# If constraints failed, may need to:
# 1. Export/import without constraints
# 2. Fix data issues
# 3. Re-create constraints

# Re-import if needed
sudo ./3-migrate-databases.sh
```

## API Deployment Issues

### Issue: API service won't start

**Symptoms:**
```
systemctl status api1
● api1.service - TavaBharat API 1
   Loaded: loaded
   Active: failed
```

**Solution:**
```bash
# Check detailed logs
sudo journalctl -u api1 -n 100 --no-pager

# Common issues:

# 1. DLL not found
ls -la /var/www/api1/*.dll
# Redeploy if missing

# 2. Port already in use
sudo ss -tuln | grep 5000
# Kill process or change port

# 3. Connection string incorrect
cat /var/www/api1/appsettings.Production.json
# Fix and restart

# 4. .NET runtime not installed
dotnet --version
# Install if missing

# 5. Permission issues
sudo chown -R ubuntu:ubuntu /var/www/api1
sudo chmod 755 /var/www/api1

# Restart after fixing
sudo systemctl restart api1
```

### Issue: Database connection fails from API

**Symptoms:**
```
Microsoft.Data.SqlClient.SqlException: A network-related error occurred
```

**Solution:**
```bash
# Test database connectivity
sqlcmd -S localhost -U api1_user -P 'PASSWORD' -d TavaBharatDB_Prod -C

# Check connection string in appsettings
cat /var/www/api1/appsettings.Production.json

# Correct format:
# Server=localhost;Database=TavaBharatDB_Prod;User Id=api1_user;Password=***;TrustServerCertificate=True

# Verify database user exists
sqlcmd -S localhost -U sa -P 'SA_PASSWORD' -Q "
USE TavaBharatDB_Prod;
SELECT name FROM sys.database_principals WHERE name = 'api1_user';
" -C

# Recreate user if needed
sqlcmd -S localhost -U sa -P 'SA_PASSWORD' -Q "
USE TavaBharatDB_Prod;
CREATE USER [api1_user] WITH PASSWORD = 'PASSWORD';
ALTER ROLE db_datareader ADD MEMBER [api1_user];
ALTER ROLE db_datawriter ADD MEMBER [api1_user];
" -C

# Restart API
sudo systemctl restart api1
```

### Issue: API responds with 500 errors

**Symptoms:**
- API starts but returns HTTP 500
- Logs show exceptions

**Solution:**
```bash
# View detailed logs
sudo journalctl -u api1 -f

# Common causes:

# 1. Missing environment variables
cat /var/www/api1/.env
# Add missing variables

# 2. Configuration errors
cat /var/www/api1/appsettings.Production.json
# Fix JSON syntax

# 3. Database migration pending
# Run migrations if your app requires it

# 4. Missing dependencies
ls /var/www/api1/
# Ensure all DLLs present

# 5. File permissions
sudo chown -R ubuntu:ubuntu /var/www/api1
sudo chmod 644 /var/www/api1/*.dll
sudo chmod 644 /var/www/api1/*.json

# Restart after fixes
sudo systemctl restart api1
```

## UI Deployment Issues

### Issue: Blank page or "Cannot GET /"

**Symptoms:**
- Browser shows blank page
- 404 for all routes

**Solution:**
```bash
# Check if index.html exists
ls -la /var/www/angular/index.html

# Check Nginx configuration
sudo nginx -t

# Check if Nginx can read files
sudo -u www-data cat /var/www/angular/index.html

# Fix permissions
sudo chown -R ubuntu:ubuntu /var/www/angular
sudo chmod -R 755 /var/www/angular

# Reload Nginx
sudo systemctl reload nginx

# Check Nginx error logs
sudo tail -f /var/log/nginx/tavabharat-error.log
```

### Issue: Assets not loading (404 for JS/CSS)

**Symptoms:**
- Page loads but no styles
- Console shows 404 for .js and .css files

**Solution:**
```bash
# Check base href in index.html
cat /var/www/angular/index.html | grep "base href"

# For root deployment, should be:
# <base href="/">

# For /admin deployment (React), should be:
# <base href="/admin/">

# Fix if incorrect
sudo nano /var/www/react/index.html

# Check file structure
ls -la /var/www/angular/
# Should show js/, css/, assets/ etc.

# Reload Nginx
sudo systemctl reload nginx
```

### Issue: API calls return 404

**Symptoms:**
- UI loads but API calls fail
- Browser console shows 404 for /api/v1/*

**Solution:**
```bash
# Check if APIs are running
sudo systemctl status api1
sudo systemctl status api2

# Test APIs directly
curl http://localhost:5000
curl http://localhost:5001

# Check Nginx proxy configuration
sudo cat /etc/nginx/sites-available/tavabharat | grep -A 10 "location /api"

# Test proxy
curl http://localhost/api/v1

# If 502 Bad Gateway: APIs not running
# If 404: Nginx routing issue

# Reload Nginx
sudo systemctl reload nginx
```

### Issue: React routing not working (page refresh 404)

**Symptoms:**
- React routes work initially
- Page refresh shows 404

**Solution:**
```bash
# Check Nginx configuration for try_files
sudo cat /etc/nginx/sites-available/tavabharat | grep -A 3 "/admin"

# Should have:
# try_files $uri $uri/ /admin/index.html;

# Fix if missing
sudo nano /etc/nginx/sites-available/tavabharat

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

## Nginx Configuration Issues

### Issue: Nginx won't start

**Symptoms:**
```
nginx.service: Failed with result 'exit-code'
```

**Solution:**
```bash
# Test configuration
sudo nginx -t

# Common errors:

# 1. Syntax error
# Fix configuration file
sudo nano /etc/nginx/sites-available/tavabharat

# 2. Port already in use
sudo ss -tuln | grep :80
# Kill conflicting process

# 3. SSL certificate missing (if configured)
ls -la /etc/nginx/ssl/
# Regenerate or reconfigure

# View detailed errors
sudo journalctl -u nginx -n 50

# After fixing
sudo systemctl start nginx
```

### Issue: 502 Bad Gateway

**Symptoms:**
- Nginx starts but APIs return 502

**Solution:**
```bash
# Check if backend services are running
sudo systemctl status api1
sudo systemctl status api2

# Start if stopped
sudo systemctl start api1
sudo systemctl start api2

# Check if listening on correct ports
sudo ss -tuln | grep 5000
sudo ss -tuln | grep 5001

# Check Nginx error log for details
sudo tail -f /var/log/nginx/tavabharat-error.log

# Test backends directly
curl http://localhost:5000
curl http://localhost:5001

# If ports wrong, update Nginx config
sudo nano /etc/nginx/sites-available/tavabharat
sudo nginx -t
sudo systemctl reload nginx
```

### Issue: Large file uploads fail

**Symptoms:**
```
413 Request Entity Too Large
```

**Solution:**
```bash
# Edit Nginx configuration
sudo nano /etc/nginx/sites-available/tavabharat

# Add or increase:
client_max_body_size 50M;

# Test and reload
sudo nginx -t
sudo systemctl reload nginx

# Also check API configuration (Kestrel)
# In appsettings.json:
# "Kestrel": {
#   "Limits": {
#     "MaxRequestBodySize": 52428800
#   }
# }
```

## SSL Certificate Issues

### Issue: Let's Encrypt certificate fails

**Symptoms:**
```
Certbot failed to authenticate some domains
```

**Solution:**
```bash
# Check DNS
dig +short yourdomain.com
nslookup yourdomain.com

# Should return your server IP

# Check port 80 is open
sudo ufw status | grep 80
curl http://yourdomain.com

# Check Nginx is serving domain
sudo cat /etc/nginx/sites-available/tavabharat | grep server_name

# Retry with verbose output
sudo certbot --nginx -d yourdomain.com --dry-run

# If still fails, try standalone mode
sudo systemctl stop nginx
sudo certbot certonly --standalone -d yourdomain.com
sudo systemctl start nginx

# Then manually configure Nginx with certificate
```

### Issue: Certificate auto-renewal fails

**Symptoms:**
- Email notification about expiring certificate
- Renewal dry-run fails

**Solution:**
```bash
# Test renewal
sudo certbot renew --dry-run

# Check timer status
sudo systemctl status certbot.timer

# Enable if disabled
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Force renewal if expiring
sudo certbot renew --force-renewal

# Check logs
sudo journalctl -u certbot.timer
```

### Issue: Browser shows "Not Secure"

**Symptoms:**
- HTTPS configured but browser shows warning
- Self-signed certificate

**Solution:**
```bash
# For self-signed certificates, this is expected

# Options:
# 1. Accept the warning (for testing only)
# 2. Get proper certificate from Let's Encrypt
# 3. Add self-signed cert to browser trust store (not recommended)

# Recommended: Use Let's Encrypt
sudo ./9-setup-ssl.sh
# Select option 1
```

## Performance Issues

### Issue: High memory usage

**Symptoms:**
- System slow or unresponsive
- OOM killer terminating processes

**Solution:**
```bash
# Check memory usage
free -h
htop

# Identify memory hogs
ps aux --sort=-%mem | head -n 10

# Reduce MSSQL memory
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512
sudo systemctl restart mssql-server

# Clear PageCache if safe
sudo sync
sudo sysctl -w vm.drop_caches=3

# Consider upgrading to larger instance
# Lightsail: 4GB RAM instance is $20/month
```

### Issue: High CPU usage

**Symptoms:**
- Server slow to respond
- Load average very high

**Solution:**
```bash
# Check load
uptime
htop

# Identify CPU hogs
ps aux --sort=-%cpu | head -n 10

# Check for specific issues:

# 1. Database queries taking too long
# Optimize queries, add indexes

# 2. API doing heavy processing
# Optimize code, add caching

# 3. Log processes consuming CPU
# Check for log rotation

# Monitor specific service
journalctl -u api1 -f
```

### Issue: Slow database queries

**Symptoms:**
- API responses taking too long
- Timeouts

**Solution:**
```bash
# Enable query performance monitoring
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
-- Find slow queries
SELECT TOP 10
    qs.execution_count,
    qs.total_elapsed_time / 1000 as total_ms,
    (qs.total_elapsed_time / 1000) / qs.execution_count as avg_ms,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
    ((CASE qs.statement_end_offset
        WHEN -1 THEN DATALENGTH(qt.text)
        ELSE qs.statement_end_offset
    END - qs.statement_start_offset)/2) + 1) as query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_elapsed_time DESC
" -C

# Check for missing indexes
# Add indexes as needed

# Update statistics
sqlcmd -S localhost -U sa -P 'PASSWORD' -d TavaBharatDB_Prod -Q "
EXEC sp_updatestats
" -C
```

### Issue: Disk space full

**Symptoms:**
```
No space left on device
```

**Solution:**
```bash
# Check disk usage
df -h

# Find large directories
sudo du -sh /* | sort -h

# Common culprits:

# 1. Old logs
sudo find /var/log -name "*.log" -type f -mtime +30 -delete
sudo find /var/log -name "*.gz" -type f -mtime +30 -delete

# 2. Old backups
sudo find /var/backups/mssql -name "*.bak" -mtime +7 -delete

# 3. Database files
sudo du -sh /var/opt/mssql/data

# 4. Package cache
sudo apt-get clean
sudo apt-get autoremove

# Consider upgrading storage
# Or implementing automatic cleanup
```

## Monitoring Issues

### Issue: Health checks not running

**Symptoms:**
- No new entries in health check log
- Cron job not executing

**Solution:**
```bash
# Check cron file
cat /etc/cron.d/tavabharat-monitoring

# Verify cron service
sudo systemctl status cron

# Check permissions
ls -la monitoring/health-check.sh
chmod +x monitoring/health-check.sh

# Test manually
sudo ./monitoring/health-check.sh

# Check cron logs
grep CRON /var/log/syslog | tail -n 20

# Recreate cron job if needed
sudo ./10-monitoring.sh
```

### Issue: Backup fails

**Symptoms:**
- Backup cron job fails
- No backup files created

**Solution:**
```bash
# Check backup directory
ls -la /var/backups/mssql

# Check permissions
sudo chown -R ubuntu:ubuntu /var/backups/mssql

# Test manually
sudo ./monitoring/backup-databases.sh

# Check logs
cat /var/log/tavabharat/backup.log

# Common issues:
# 1. Disk space full
# 2. SA password incorrect
# 3. Database in use

# Fix and retry
```

### Issue: Email alerts not working

**Symptoms:**
- No alert emails received
- Mail command not found

**Solution:**
```bash
# Install mail utilities
sudo apt-get install mailutils

# Configure email
sudo nano /etc/postfix/main.cf
# Configure SMTP settings

# Test
echo "Test" | mail -s "Test" your@email.com

# Alternatively, use external SMTP
# Install ssmtp or msmtp
# Configure with Gmail/SendGrid/etc.
```

## General System Issues

### Issue: Cannot SSH to server

**Symptoms:**
- Connection timeout
- Connection refused

**Solution:**
```bash
# Check from Lightsail console:
# 1. Instance is running
# 2. Static IP attached
# 3. Firewall allows SSH (port 22)

# From AWS Lightsail console:
# Connect using browser-based SSH

# Then check:
sudo systemctl status sshd
sudo ufw status | grep 22

# Check Lightsail firewall rules in AWS console
```

### Issue: System time incorrect

**Symptoms:**
- Timestamps in logs are wrong
- SSL certificates show as expired

**Solution:**
```bash
# Check current time
date
timedatectl

# Set correct timezone
sudo timedatectl set-timezone Asia/Kolkata

# Sync time with NTP
sudo systemctl restart systemd-timesyncd
sudo timedatectl set-ntp on

# Verify
timedatectl
```

### Issue: Package installation fails

**Symptoms:**
```
E: Unable to locate package
E: Package has no installation candidate
```

**Solution:**
```bash
# Update package list
sudo apt-get update

# If still fails, check sources
cat /etc/apt/sources.list

# Repair if needed
sudo apt-get update --fix-missing
sudo apt-get install -f
sudo dpkg --configure -a

# Clear cache and retry
sudo apt-get clean
sudo apt-get update
sudo apt-get upgrade
```

## Getting Additional Help

If issues persist:

1. **Check Logs:**
   ```bash
   # System logs
   sudo journalctl -xe
   
   # Service-specific logs
   sudo journalctl -u mssql-server -n 100
   sudo journalctl -u api1 -n 100
   
   # Application logs
   ls /var/log/tavabharat/
   ```

2. **Gather System Information:**
   ```bash
   # Create diagnostic report
   {
     echo "=== System Info ==="
     uname -a
     lsb_release -a
     
     echo "=== Resources ==="
     free -h
     df -h
     
     echo "=== Services ==="
     systemctl status mssql-server api1 api2 nginx
     
     echo "=== Network ==="
     ss -tuln
     
     echo "=== Recent Errors ==="
     journalctl -p err -n 50
   } > /tmp/diagnostic-report.txt
   
   cat /tmp/diagnostic-report.txt
   ```

3. **Search Documentation:**
   - Check DETAILED_GUIDE.md
   - Review README.md
   - Check script comments

4. **Community Support:**
   - Open GitHub issue with diagnostic report
   - Include error messages and logs
   - Describe steps taken

5. **Professional Support:**
   - Consider AWS Support
   - Consult with system administrator
   - Hire migration specialist

---

**Remember:** Most issues can be resolved by carefully reading error messages and checking logs!
