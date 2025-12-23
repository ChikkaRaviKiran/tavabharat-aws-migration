# TavaBharat AWS Lightsail Migration Toolkit

Complete, automated migration toolkit to migrate TavaBharat application stack from Azure to AWS Lightsail.

## 📋 Overview

This toolkit provides a complete, step-by-step migration solution for:
- **2 Databases** (Azure SQL → MSSQL Express)
- **2 .NET APIs** (Port 5000 & 5001)
- **2 Frontend UIs** (Angular + React)
- **Nginx Reverse Proxy**
- **SSL/TLS Configuration**
- **Automated Monitoring & Backups**

## 🎯 Target Infrastructure

- **Platform:** AWS Lightsail - Ubuntu 22.04 LTS
- **Instance:** $12/month plan (2GB RAM, 2 vCPU, 60GB SSD)
- **Budget:** ₹1,000-1,500/month (₹996 + GST)
- **Database:** MSSQL Server 2022 Express (FREE, 10GB limit)

## 🏗️ Architecture

```
                             ┌─────────────────────┐
                             │  AWS Lightsail      │
                             │  Ubuntu 22.04 LTS   │
                             └──────────┬──────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         │      Nginx (Port 80/443)     │
                         │     Reverse Proxy & SSL      │
                         └──────────────┬──────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │                               │                               │
  ┌─────▼─────┐                  ┌──────▼──────┐              ┌────────▼────────┐
  │  Angular  │                  │  React UI   │              │   .NET APIs     │
  │    UI     │                  │ /admin      │              │  /api/v1 :5000  │
  │    /      │                  │             │              │  /api/v2 :5001  │
  └───────────┘                  └─────────────┘              └────────┬────────┘
                                                                       │
                                                              ┌────────▼────────┐
                                                              │  MSSQL Express  │
                                                              │  localhost:1433 │
                                                              │  2 Databases    │
                                                              └─────────────────┘
```

## ⚡ Quick Start (30-Minute Setup)

### Prerequisites

1. **AWS Lightsail Instance:**
   - Create Ubuntu 22.04 LTS instance ($12/month)
   - Assign static IP address
   - Configure SSH access

2. **Local Preparation:**
   - Azure SQL database credentials
   - Built .NET API applications (or source code)
   - Built Angular/React applications (or source code)

### Installation Steps

```bash
# 1. Connect to your Lightsail instance
ssh ubuntu@YOUR_LIGHTSAIL_IP

# 2. Clone this repository
git clone https://github.com/ChikkaRaviKiran/tavabharat-aws-migration.git
cd tavabharat-aws-migration

# 3. Configure credentials (IMPORTANT!)
cp configs/.env.example configs/.env
nano configs/.env  # Edit with your actual credentials

# 4. Run the master installer
sudo ./install.sh
```

Follow the interactive prompts to complete the installation!

## 📦 What's Included

### Migration Scripts (1-10)

| Script | Purpose | Duration |
|--------|---------|----------|
| `1-server-setup.sh` | System preparation, swap, firewall | ~5 min |
| `2-install-mssql.sh` | MSSQL Server Express installation | ~10 min |
| `3-migrate-databases.sh` | Database migration from Azure | ~15-30 min |
| `4-deploy-api1.sh` | Deploy first .NET API | ~5 min |
| `5-deploy-api2.sh` | Deploy second .NET API | ~5 min |
| `6-deploy-angular.sh` | Deploy Angular UI | ~5 min |
| `7-deploy-react.sh` | Deploy React UI | ~5 min |
| `8-configure-nginx.sh` | Setup reverse proxy | ~3 min |
| `9-setup-ssl.sh` | Configure SSL/HTTPS | ~5 min |
| `10-monitoring.sh` | Setup monitoring & backups | ~3 min |

### Configuration Templates

- `configs/.env.example` - Environment variables template
- `configs/api1.service` - Systemd service for API 1
- `configs/api2.service` - Systemd service for API 2
- `configs/appsettings.Production.json.template` - .NET configuration
- `configs/nginx.conf` - Nginx configuration

### Monitoring Scripts

- `monitoring/health-check.sh` - Monitor all services (runs every 5 min)
- `monitoring/backup-databases.sh` - Database backup (runs daily at 2 AM)
- `monitoring/resource-monitor.sh` - Track CPU/RAM/Disk (runs hourly)

### Database Utilities

- `database/export-azure-db.sh` - Export databases from Azure SQL
- `database/validate-migration.sql` - Validation queries

## 📖 Detailed Documentation

For complete documentation including:
- Detailed step-by-step guide for each script
- Configuration examples
- Deployment procedures
- Troubleshooting guide
- Security best practices
- Cost optimization tips
- Migration checklist

Please see the full documentation in the repository files.

## 🔧 Key Features

- ✅ **Automated Setup** - One-command installation
- ✅ **Memory Optimized** - Configured for 2GB RAM servers
- ✅ **Production Ready** - Systemd services with auto-restart
- ✅ **Secure** - Firewall, SSL/TLS, isolated database
- ✅ **Monitored** - Automated health checks and backups
- ✅ **Well Documented** - Comprehensive guides and examples
- ✅ **Idempotent Scripts** - Safe to run multiple times
- ✅ **Interactive** - User-friendly prompts and menus
- ✅ **Validated** - Database migration verification
- ✅ **Rollback Support** - Backup procedures included

## 🚀 Quick Commands

```bash
# Check system status
tavabharat-status

# Update applications
tavabharat-update [api1|api2|angular|react]

# Manual health check
sudo ./monitoring/health-check.sh

# Manual database backup
sudo ./monitoring/backup-databases.sh

# View logs
sudo journalctl -u api1 -f
sudo tail -f /var/log/nginx/tavabharat-error.log
```

## 💰 Cost Breakdown

- **Lightsail Instance:** $12/month (~₹996)
- **Data Transfer:** 2TB included
- **MSSQL Express:** FREE
- **SSL Certificate:** FREE (Let's Encrypt)
- **Total:** Under ₹1,500/month including GST ✅

## 📋 Migration Checklist

- [ ] Create Lightsail instance
- [ ] Clone repository
- [ ] Configure `.env` file
- [ ] Run server setup
- [ ] Install MSSQL
- [ ] Migrate databases
- [ ] Deploy APIs
- [ ] Deploy UIs
- [ ] Configure Nginx
- [ ] Setup SSL
- [ ] Enable monitoring
- [ ] Test all functionality
- [ ] Update DNS (if using domain)

## 🆘 Troubleshooting

### Common Issues

**API won't start:**
```bash
sudo journalctl -u api1 -n 100
sudo systemctl restart api1
```

**Database connection failed:**
```bash
sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -C
sudo systemctl restart mssql-server
```

**Nginx 502 error:**
```bash
curl http://localhost:5000
sudo tail -f /var/log/nginx/tavabharat-error.log
```

See full troubleshooting guide in the repository documentation.

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! Please submit pull requests or open issues.

---

**Built with ❤️ for TavaBharat Migration**
