# TavaBharat Migration - Detailed Step-by-Step Guide

This document provides detailed instructions for each step of the migration process.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Server Setup (Script 1)](#1-server-setup)
3. [MSSQL Installation (Script 2)](#2-mssql-installation)
4. [Database Migration (Script 3)](#3-database-migration)
5. [API Deployment (Scripts 4-5)](#4-5-api-deployment)
6. [UI Deployment (Scripts 6-7)](#6-7-ui-deployment)
7. [Nginx Configuration (Script 8)](#8-nginx-configuration)
8. [SSL Setup (Script 9)](#9-ssl-setup)
9. [Monitoring Setup (Script 10)](#10-monitoring-setup)
10. [Post-Migration Tasks](#post-migration-tasks)

## Prerequisites

### AWS Lightsail Setup

1. **Create Instance:**
   - Go to AWS Lightsail console
   - Click "Create instance"
   - Select "Linux/Unix" platform
   - Select "OS Only" → "Ubuntu 22.04 LTS"
   - Choose $12/month plan (2GB RAM, 2 vCPU, 60GB SSD)
   - Name your instance (e.g., "tavabharat-prod")
   - Click "Create instance"

2. **Configure Static IP:**
   - In Lightsail console, go to "Networking"
   - Click "Create static IP"
   - Attach to your instance
   - Note down the IP address

3. **Configure Firewall:**
   - In Lightsail console, go to your instance
   - Click "Networking" tab
   - Ensure these ports are open:
     - SSH (22)
     - HTTP (80)
     - HTTPS (443)

4. **SSH Access:**
   - Download the SSH key from Lightsail console
   - Set permissions: `chmod 400 LightsailDefaultKey.pem`
   - Connect: `ssh -i LightsailDefaultKey.pem ubuntu@YOUR_IP`

### Local Preparation

1. **Build .NET APIs:**
   ```bash
   # For each API project
   cd YourAPIProject
   dotnet publish -c Release -o ./publish -r linux-x64 --self-contained false
   cd publish
   zip -r ../api.zip .
   ```

2. **Build Angular:**
   ```bash
   cd angular-project
   npm install
   npm run build --prod
   cd dist
   zip -r ../../angular.zip .
   ```

3. **Build React:**
   ```bash
   cd react-project
   npm install
   npm run build
   cd build
   zip -r ../../react.zip .
   ```

## 1. Server Setup

**Script:** `1-server-setup.sh`

**Purpose:** Prepare the Ubuntu server for application deployment.

**What it does:**
- Updates all system packages
- Installs essential tools
- Configures timezone to Asia/Kolkata
- Creates 2GB swap file (critical for 2GB RAM)
- Configures firewall
- Optimizes system settings
- Creates directory structure
- Sets up log rotation

**Run:**
```bash
sudo ./1-server-setup.sh
```

**Expected Output:**
```
========================================
TavaBharat Server Setup
AWS Lightsail - Ubuntu 22.04 LTS
========================================
[INFO] Updating system packages...
[SUCCESS] System packages updated
[INFO] Installing essential tools...
[SUCCESS] Essential tools installed
...
[SUCCESS] Server is ready for application deployment!
```

**Verification:**
```bash
# Check swap
free -h

# Check firewall
sudo ufw status

# Check directories
ls -la /var/www
ls -la /var/log/tavabharat
```

**Troubleshooting:**
- If swap creation fails, ensure you have enough disk space
- If firewall configuration fails, manually enable it: `sudo ufw enable`

## 2. MSSQL Installation

**Script:** `2-install-mssql.sh`

**Purpose:** Install and configure MSSQL Server 2022 Express Edition.

**What it does:**
- Adds Microsoft repository
- Installs MSSQL Server 2022
- Configures Express Edition
- Sets SA password
- Optimizes memory to 768MB (for 2GB server)
- Installs sqlcmd and sqlpackage tools
- Creates initial databases

**Before Running:**
- Ensure you have a strong SA password ready (min 8 chars, mixed case, numbers, symbols)
- Or set it in `configs/.env` as `MSSQL_SA_PASSWORD`

**Run:**
```bash
sudo ./2-install-mssql.sh
```

**Expected Output:**
```
========================================
MSSQL Server Express Installation
========================================
[INFO] Adding Microsoft SQL Server repository...
[SUCCESS] Repository added
[INFO] Installing MSSQL Server 2022...
[SUCCESS] MSSQL Server package installed
...
[SUCCESS] MSSQL Server is ready!
```

**Verification:**
```bash
# Check service status
sudo systemctl status mssql-server

# Test connection
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -Q "SELECT @@VERSION" -C

# Check memory configuration
sudo /opt/mssql/bin/mssql-conf get memory.memorylimitmb
```

**Troubleshooting:**
- If service fails to start, check logs: `sudo journalctl -u mssql-server -n 50`
- If memory errors occur, reduce memory limit: `sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 512`
- Ensure password meets complexity requirements

## 3. Database Migration

**Script:** `3-migrate-databases.sh`

**Purpose:** Migrate databases from Azure SQL to local MSSQL Express.

**What it does:**
- Provides multiple migration methods
- Exports databases from Azure (Method 1)
- Imports .bacpac files to local MSSQL
- Validates migration with row counts
- Creates database users for APIs
- Generates migration report

**Migration Methods:**

### Method 1: Direct Export (Recommended)
Best for most scenarios. Exports directly from Azure SQL.

**Before Running:**
- Have Azure SQL credentials ready
- Ensure source database is accessible
- Check database size (must be under 10GB for Express)

**Run:**
```bash
sudo ./3-migrate-databases.sh
# Select option 1
# Enter Azure credentials when prompted
```

**What happens:**
1. Exports database to .bacpac file (15-30 minutes depending on size)
2. Saves to `database/backups/`
3. Imports to local MSSQL
4. Validates row counts
5. Creates API users

### Method 2: Import Existing Files
Use if you already have .bacpac files.

```bash
sudo ./3-migrate-databases.sh
# Select option 2
# Provide path to .bacpac file
```

### Method 3: SQL Scripts
For custom migration scenarios.

### Method 4: Manual Portal Export
Step-by-step guide for Azure Portal export.

**Expected Output:**
```
========================================
Database Migration from Azure SQL
========================================
[INFO] Method 1: Export from Azure using sqlpackage
[INFO] Exporting database: TavaBharatDB_Prod
[SUCCESS] Export completed
[INFO] Importing database
[SUCCESS] Import completed
[INFO] Validating migration...
[SUCCESS] Database TavaBharatDB_Prod validated: 50 tables
========================================
Database Migration Complete!
========================================
```

**Verification:**
```bash
# List databases
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -Q "SELECT name FROM sys.databases" -C

# Check table counts
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -d TavaBharatDB_Prod -Q "
SELECT COUNT(*) AS TableCount FROM sys.tables
" -C

# Review validation report
cat database/logs/validation_TavaBharatDB_Prod.log
```

**Troubleshooting:**
- If export fails, check Azure SQL firewall rules
- If import fails, check disk space and memory
- For large databases, consider splitting into smaller parts
- Review logs in `database/logs/` for detailed errors

## 4-5. API Deployment

**Scripts:** `4-deploy-api1.sh`, `5-deploy-api2.sh`

**Purpose:** Deploy .NET APIs and configure as systemd services.

**What it does:**
- Accepts published apps or source code
- Installs .NET runtime if needed
- Configures connection strings
- Creates systemd service
- Enables auto-start on boot
- Tests API endpoint

**Deployment Options:**

### Option 1: Upload Published ZIP
Fastest method. Use pre-published application.

**Prepare:**
```bash
# On your development machine
cd APIProject
dotnet publish -c Release -o ./publish
cd publish
zip -r ../api1.zip .
```

**Upload to server:**
```bash
scp api1.zip ubuntu@YOUR_IP:/tmp/
```

**Deploy:**
```bash
sudo ./4-deploy-api1.sh
# Select option 1
# Enter path: /tmp/api1.zip
```

### Option 2: Clone from Git
Builds from source on the server.

```bash
sudo ./4-deploy-api1.sh
# Select option 2
# Enter Git URL and branch
```

### Option 3: Use Existing Files
If files are already on the server.

**Expected Output:**
```
========================================
Deploy API 1 - Primary Business API
========================================
[INFO] Extracting application...
[SUCCESS] Application extracted
[INFO] Detecting application configuration...
[INFO] Main DLL: TavaBharatAPI.dll
[SUCCESS] API 1 service started successfully
[SUCCESS] API is responding on port 5000
========================================
API 1 Deployment Complete!
========================================
```

**Verification:**
```bash
# Check service status
sudo systemctl status api1

# View logs
sudo journalctl -u api1 -n 50

# Test endpoint
curl http://localhost:5000
curl http://localhost:5000/api/v1/health  # if you have health endpoint

# Check if listening on port
sudo ss -tuln | grep 5000
```

**Configuration:**

The script automatically creates:
- `/var/www/api1/.env` - Environment variables
- `/var/www/api1/appsettings.Production.json` - Connection strings
- `/etc/systemd/system/api1.service` - Service configuration

**Troubleshooting:**
- If service won't start: Check logs with `sudo journalctl -u api1 -n 100`
- If database connection fails: Verify connection string in appsettings.Production.json
- If port conflict: Check if another service is using port 5000
- If DLL not found: Ensure you published with correct target framework

## 6-7. UI Deployment

**Scripts:** `6-deploy-angular.sh`, `7-deploy-react.sh`

**Purpose:** Deploy frontend applications to be served by Nginx.

**What it does:**
- Accepts pre-built apps or source code
- Builds from source if needed (installs Node.js)
- Deploys to /var/www/
- Updates API endpoint configurations
- Sets proper permissions

**Deployment Options:**

### Option 1: Upload Pre-built ZIP
Fastest method.

**Prepare:**
```bash
# Angular
cd angular-project
npm run build --prod
cd dist/your-project-name
zip -r ../../angular-build.zip .

# React
cd react-project
npm run build
cd build
zip -r ../../react-build.zip .
```

**Upload:**
```bash
scp angular-build.zip ubuntu@YOUR_IP:/tmp/
scp react-build.zip ubuntu@YOUR_IP:/tmp/
```

**Deploy:**
```bash
sudo ./6-deploy-angular.sh
# Select option 1
# Enter path: /tmp/angular-build.zip

sudo ./7-deploy-react.sh
# Select option 1
# Enter path: /tmp/react-build.zip
```

### Option 2: Build from Source
Builds on the server (takes longer).

**Expected Output:**
```
========================================
Deploy Angular UI - Main Application
========================================
[INFO] Extracting application...
[SUCCESS] Application extracted
[INFO] Checking for API endpoint configuration...
[SUCCESS] Permissions set
========================================
Angular UI Deployment Complete!
========================================
```

**Verification:**
```bash
# Check deployed files
ls -la /var/www/angular
ls -la /var/www/react

# Verify index.html exists
cat /var/www/angular/index.html | head
cat /var/www/react/index.html | head

# Check permissions
ls -ld /var/www/angular
ls -ld /var/www/react
```

**Troubleshooting:**
- If index.html not found: Check build output structure
- If Node.js installation fails: Install manually: `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt-get install -y nodejs`
- If build fails: Check for sufficient disk space and memory

## 8. Nginx Configuration

**Script:** `8-configure-nginx.sh`

**Purpose:** Configure Nginx as reverse proxy for all applications.

**What it does:**
- Installs Nginx
- Creates configuration for all routes
- Enables site
- Tests configuration
- Restarts Nginx
- Verifies routes

**Routes Configured:**
- `/` → Angular UI (Port 80/443)
- `/admin` → React UI (Port 80/443)
- `/api/v1/*` → API 1 (Proxied to localhost:5000)
- `/api/v2/*` → API 2 (Proxied to localhost:5001)

**Run:**
```bash
sudo ./8-configure-nginx.sh
# Enter your server IP or domain when prompted
```

**Expected Output:**
```
========================================
Configure Nginx Reverse Proxy
========================================
[INFO] Installing Nginx...
[SUCCESS] Nginx installed
[INFO] Creating Nginx configuration...
[SUCCESS] Configuration file created
[INFO] Testing Nginx configuration...
[SUCCESS] Nginx configuration is valid
[SUCCESS] Nginx is running
[SUCCESS] Main page (/) is accessible
[SUCCESS] API 1 (/api/v1) is reachable
========================================
Nginx Configuration Complete!
========================================
```

**Verification:**
```bash
# Test Nginx configuration
sudo nginx -t

# Check service status
sudo systemctl status nginx

# Test all routes
curl http://localhost/
curl http://localhost/admin
curl http://localhost/api/v1
curl http://localhost/api/v2

# Check from external machine
curl http://YOUR_SERVER_IP/
```

**Testing in Browser:**
```
http://YOUR_SERVER_IP/          # Should show Angular app
http://YOUR_SERVER_IP/admin     # Should show React admin panel
http://YOUR_SERVER_IP/api/v1    # Should show API response or 404
http://YOUR_SERVER_IP/api/v2    # Should show API response or 404
```

**Troubleshooting:**
- 502 Bad Gateway: APIs not running - check `sudo systemctl status api1 api2`
- 404 Not Found for UI: Check files exist in /var/www/
- Nginx won't start: Check config with `sudo nginx -t`
- Can't access externally: Check Lightsail firewall rules

## 9. SSL Setup

**Script:** `9-setup-ssl.sh`

**Purpose:** Configure HTTPS/SSL for secure access.

**SSL Options:**

### Option 1: Let's Encrypt (Recommended for Production)

**Prerequisites:**
- Domain name pointing to your server IP
- Ports 80 and 443 accessible from internet

**Steps:**
```bash
sudo ./9-setup-ssl.sh
# Select option 1
# Enter domain name (e.g., tavabharat.com)
# Enter email for certificate notifications
```

**What happens:**
1. Installs certbot
2. Verifies domain points to server
3. Obtains SSL certificate
4. Updates Nginx configuration
5. Sets up auto-renewal

**Auto-renewal:**
- Certificates are valid for 90 days
- Automatically renews 30 days before expiration
- Check renewal: `sudo systemctl status certbot.timer`

### Option 2: Self-Signed Certificate (Testing Only)

**Use when:**
- No domain name available
- Testing environment
- Internal-only access

```bash
sudo ./9-setup-ssl.sh
# Select option 2
# Enter server IP or name
```

**Note:** Browsers will show security warnings. Click "Advanced" → "Proceed" to access.

**Expected Output:**
```
========================================
SSL Configuration Complete!
========================================
Certificate Type: Let's Encrypt (Valid for 90 days)
Domain: tavabharat.com
Auto-renewal: Enabled

Your site: https://tavabharat.com
========================================
```

**Verification:**
```bash
# Test HTTPS
curl -k https://localhost/

# Check certificate (Let's Encrypt)
sudo certbot certificates

# Check auto-renewal
sudo systemctl status certbot.timer

# Test renewal (dry run)
sudo certbot renew --dry-run
```

**Troubleshooting:**
- Let's Encrypt fails: Ensure domain DNS points to server
- Port 80 blocked: Check Lightsail firewall
- Certificate not trusted (self-signed): Expected - accept browser warning
- Auto-renewal fails: Check cron/timer: `sudo systemctl list-timers`

## 10. Monitoring Setup

**Script:** `10-monitoring.sh`

**Purpose:** Configure automated monitoring, health checks, and backups.

**What it does:**
- Configures cron jobs for automated tasks
- Sets up health checks (every 5 minutes)
- Configures database backups (daily at 2 AM)
- Enables resource monitoring (hourly)
- Creates status dashboard command
- Sets up log rotation

**Run:**
```bash
sudo ./10-monitoring.sh
```

**Monitoring Components:**

### 1. Health Checks
Runs every 5 minutes. Checks:
- MSSQL Server status
- API 1 status and endpoint
- API 2 status and endpoint
- Nginx status
- Disk space
- Memory usage
- CPU load

**View logs:**
```bash
tail -f /var/log/tavabharat-health.log
```

### 2. Database Backups
Runs daily at 2:00 AM. Features:
- Backs up all user databases
- Compression enabled
- Keeps last 7 days
- Creates checksums

**View backups:**
```bash
ls -lh /var/backups/mssql/
```

**Restore example:**
```bash
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
RESTORE DATABASE [TavaBharatDB_Prod] 
FROM DISK = '/var/backups/mssql/TavaBharatDB_Prod_TIMESTAMP.bak'
WITH REPLACE
" -C
```

### 3. Resource Monitoring
Runs every hour. Tracks:
- CPU usage and load average
- Memory usage (RAM and Swap)
- Disk usage
- Logs to file

**View logs:**
```bash
tail -f /var/log/tavabharat/resource-monitor.log
```

**Expected Output:**
```
========================================
Setup Monitoring and Health Checks
========================================
[INFO] Making monitoring scripts executable...
[SUCCESS] Scripts are executable
[INFO] Setting up cron jobs...
[SUCCESS] Cron jobs configured

Scheduled Tasks:
  Health Checks:      Every 5 minutes
  Database Backups:   Daily at 2:00 AM
  Resource Monitor:   Every hour
  Log Cleanup:        Weekly on Sunday at 3:00 AM
========================================
Monitoring Setup Complete!
========================================
```

**Verification:**
```bash
# View cron schedule
cat /etc/cron.d/tavabharat-monitoring

# Run manual tests
sudo ./monitoring/health-check.sh
sudo ./monitoring/resource-monitor.sh
sudo ./monitoring/backup-databases.sh

# Check system status
tavabharat-status

# View all logs
ls -la /var/log/tavabharat/
```

**Status Dashboard:**
```bash
tavabharat-status
```

Output:
```
========================================
TavaBharat System Status
========================================

System Information:
  Hostname: ip-172-26-x-x
  Uptime: up 2 days, 3 hours
  Load: 0.15, 0.20, 0.18

Resources:
  Memory: 45.2%
  Disk: 38%

Services:
  MSSQL:   ✓ Running
  API 1:   ✓ Running
  API 2:   ✓ Running
  Nginx:   ✓ Running
========================================
```

## Post-Migration Tasks

### 1. DNS Configuration (If Using Domain)

**Update DNS records:**
```
Type: A
Name: @ (or www)
Value: YOUR_LIGHTSAIL_IP
TTL: 300
```

Wait 5-30 minutes for DNS propagation.

**Verify:**
```bash
dig +short yourdomain.com
nslookup yourdomain.com
```

### 2. Final Testing

**Test all endpoints:**
```bash
# From external machine
curl https://yourdomain.com/
curl https://yourdomain.com/admin
curl https://yourdomain.com/api/v1/health
curl https://yourdomain.com/api/v2/health
```

**Test in browser:**
- Main application
- Admin panel
- API endpoints
- Login functionality
- Database operations

### 3. Performance Testing

**Load testing:**
```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Test API
ab -n 1000 -c 10 http://localhost:5000/api/v1/endpoint

# Monitor during test
htop
watch -n 1 free -h
```

### 4. Security Hardening

**Additional security measures:**

```bash
# Disable password authentication for SSH (use keys only)
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart sshd

# Install fail2ban
sudo apt-get install fail2ban
sudo systemctl enable fail2ban

# Regular updates
sudo apt-get update && sudo apt-get upgrade -y
```

### 5. Backup Verification

**Test backup restoration:**
```bash
# Create test database
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
CREATE DATABASE TestRestore
" -C

# Restore backup to test database
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
RESTORE DATABASE TestRestore 
FROM DISK = '/var/backups/mssql/TavaBharatDB_Prod_LATEST.bak'
WITH REPLACE
" -C

# Verify
sqlcmd -S localhost -U sa -P 'PASSWORD' -d TestRestore -Q "
SELECT COUNT(*) FROM sys.tables
" -C

# Clean up
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "
DROP DATABASE TestRestore
" -C
```

### 6. Monitoring Setup

**Configure email alerts (optional):**

```bash
# Edit configs/.env
ALERT_EMAIL=admin@yourdomain.com

# Test email
echo "Test" | mail -s "Test Alert" admin@yourdomain.com
```

### 7. Documentation

**Document your setup:**
- Server IP/domain
- Database credentials (store securely)
- API endpoints
- Admin panel URL
- Backup schedule
- Monitoring procedures

### 8. Decommission Azure Resources

**Only after confirming everything works:**

1. **Verify migration:**
   - All data migrated
   - All functionality working
   - Backups tested
   - DNS updated

2. **Take final Azure backup:**
   ```
   Azure Portal → Database → Export
   ```

3. **Stop Azure resources:**
   - Stop App Services
   - Stop SQL Database
   - Keep running for 1-2 weeks as safety

4. **Delete after confirmation:**
   - Delete App Services
   - Delete SQL Database
   - Delete App Service Plan
   - Delete Resource Group

## Maintenance Procedures

### Daily Tasks
- Check health check logs
- Monitor disk space
- Review error logs

### Weekly Tasks
- Review backup logs
- Check resource usage trends
- Review security logs
- Apply system updates

### Monthly Tasks
- Test backup restoration
- Review and rotate logs
- Update documentation
- Security audit

### As Needed
- Application updates
- Database maintenance
- Certificate renewal (Let's Encrypt auto-renews)
- Scale resources if needed

## Quick Reference Commands

```bash
# System Status
tavabharat-status
htop
df -h
free -h

# Services
sudo systemctl status mssql-server
sudo systemctl status api1
sudo systemctl status api2
sudo systemctl status nginx

# Logs
sudo journalctl -u api1 -f
sudo journalctl -u api2 -f
sudo tail -f /var/log/nginx/tavabharat-error.log

# Database
sqlcmd -S localhost -U sa -P 'PASSWORD' -C
sqlcmd -S localhost -U sa -P 'PASSWORD' -Q "SELECT name FROM sys.databases" -C

# Monitoring
sudo ./monitoring/health-check.sh
sudo ./monitoring/backup-databases.sh
sudo ./monitoring/resource-monitor.sh

# Updates
sudo tavabharat-update api1
sudo tavabharat-update api2
sudo tavabharat-update angular
sudo tavabharat-update react
```

---

For additional help, refer to the main README or open an issue on GitHub.
