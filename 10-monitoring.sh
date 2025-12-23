#!/bin/bash
#
# Setup Monitoring and Health Checks
# Configures automated monitoring, backups, and health checks
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
    exit 1
fi

echo "========================================"
echo "Setup Monitoring and Health Checks"
echo "========================================"

# Load configuration
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# Make monitoring scripts executable
log_info "Making monitoring scripts executable..."
chmod +x monitoring/*.sh
chmod +x database/*.sh
log_success "Scripts are executable"

# Setup cron jobs
log_info "Setting up cron jobs..."

# Create cron file
CRON_FILE="/etc/cron.d/tavabharat-monitoring"

cat > "$CRON_FILE" << EOF
# TavaBharat Monitoring Cron Jobs
# Generated on $(date)

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Health check every 5 minutes
*/5 * * * * root cd $(pwd) && ./monitoring/health-check.sh >> /var/log/tavabharat/health-check.log 2>&1

# Database backup daily at 2 AM
0 2 * * * root cd $(pwd) && ./monitoring/backup-databases.sh >> /var/log/tavabharat/backup.log 2>&1

# Resource monitoring every hour
0 * * * * root cd $(pwd) && ./monitoring/resource-monitor.sh >> /var/log/tavabharat/resource-monitor.log 2>&1

# Cleanup old logs weekly (Sunday at 3 AM)
0 3 * * 0 root find /var/log/tavabharat -name "*.log" -type f -mtime +30 -delete
0 3 * * 0 root find /var/log/nginx -name "*.log.*.gz" -type f -mtime +30 -delete

EOF

chmod 644 "$CRON_FILE"
log_success "Cron jobs configured"

# Display cron schedule
echo ""
echo "Scheduled Tasks:"
echo "  Health Checks:      Every 5 minutes"
echo "  Database Backups:   Daily at 2:00 AM"
echo "  Resource Monitor:   Every hour"
echo "  Log Cleanup:        Weekly on Sunday at 3:00 AM"
echo ""

# Test monitoring scripts
echo ""
log_info "Testing monitoring scripts..."
echo ""

# Test health check
log_info "Running health check test..."
if ./monitoring/health-check.sh; then
    log_success "Health check script working"
else
    log_warning "Health check script completed with warnings"
fi

echo ""

# Test resource monitor
log_info "Running resource monitor test..."
if ./monitoring/resource-monitor.sh; then
    log_success "Resource monitor script working"
else
    log_warning "Resource monitor script completed with warnings"
fi

echo ""

# Ask about database backup test
read -p "Run database backup test? This will create actual backups [y/N]: " RUN_BACKUP
if [ "$RUN_BACKUP" == "y" ] || [ "$RUN_BACKUP" == "Y" ]; then
    log_info "Running database backup test..."
    if ./monitoring/backup-databases.sh; then
        log_success "Database backup script working"
    else
        log_error "Database backup script failed"
    fi
fi

# Setup log rotation (in case it wasn't done earlier)
log_info "Verifying log rotation configuration..."

if [ ! -f /etc/logrotate.d/tavabharat ]; then
    cat > /etc/logrotate.d/tavabharat << EOF
/var/log/tavabharat/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 ubuntu ubuntu
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}

/var/log/api1/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 ubuntu ubuntu
}

/var/log/api2/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 ubuntu ubuntu
}
EOF
    log_success "Log rotation configured"
else
    log_info "Log rotation already configured"
fi

# Create monitoring dashboard script
log_info "Creating monitoring dashboard..."

cat > /usr/local/bin/tavabharat-status << 'EOF'
#!/bin/bash
# TavaBharat Status Dashboard

echo "========================================"
echo "TavaBharat System Status"
echo "========================================"
echo ""

# System Info
echo "System Information:"
echo "  Hostname: $(hostname)"
echo "  Uptime: $(uptime -p)"
echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Resources
echo "Resources:"
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
echo "  Memory: ${MEMORY_USAGE}%"
echo "  Disk: ${DISK_USAGE}"
echo ""

# Services
echo "Services:"
echo -n "  MSSQL:   "
systemctl is-active mssql-server >/dev/null 2>&1 && echo "✓ Running" || echo "✗ Stopped"
echo -n "  API 1:   "
systemctl is-active api1 >/dev/null 2>&1 && echo "✓ Running" || echo "✗ Stopped"
echo -n "  API 2:   "
systemctl is-active api2 >/dev/null 2>&1 && echo "✓ Running" || echo "✗ Stopped"
echo -n "  Nginx:   "
systemctl is-active nginx >/dev/null 2>&1 && echo "✓ Running" || echo "✗ Stopped"
echo ""

# Recent logs
echo "Recent Errors (last 10):"
grep -h ERROR /var/log/tavabharat/*.log 2>/dev/null | tail -10 || echo "  No recent errors"
echo ""

# Disk usage by directory
echo "Disk Usage by Directory:"
du -sh /var/www/* 2>/dev/null | sort -h || echo "  No data"
du -sh /var/backups/mssql 2>/dev/null || echo "  No backups yet"
echo ""

echo "========================================"
echo "For detailed logs, use:"
echo "  sudo journalctl -u api1 -f       (API 1 logs)"
echo "  sudo journalctl -u api2 -f       (API 2 logs)"
echo "  sudo tail -f /var/log/nginx/tavabharat-error.log"
echo "========================================"
EOF

chmod +x /usr/local/bin/tavabharat-status
log_success "Status dashboard created"

# Create update script
log_info "Creating application update helper script..."

cat > /usr/local/bin/tavabharat-update << 'EOF'
#!/bin/bash
# TavaBharat Application Update Helper

set -e

echo "TavaBharat Application Update"
echo "=============================="
echo ""

if [ "$1" == "api1" ]; then
    echo "Updating API 1..."
    sudo systemctl stop api1
    echo "Service stopped. Deploy new files to /var/www/api1"
    echo "When done, run: sudo systemctl start api1"
    
elif [ "$1" == "api2" ]; then
    echo "Updating API 2..."
    sudo systemctl stop api2
    echo "Service stopped. Deploy new files to /var/www/api2"
    echo "When done, run: sudo systemctl start api2"
    
elif [ "$1" == "angular" ]; then
    echo "Updating Angular UI..."
    echo "Deploy new files to /var/www/angular"
    echo "When done, run: sudo systemctl reload nginx"
    
elif [ "$1" == "react" ]; then
    echo "Updating React UI..."
    echo "Deploy new files to /var/www/react"
    echo "When done, run: sudo systemctl reload nginx"
    
else
    echo "Usage: tavabharat-update [api1|api2|angular|react]"
    echo ""
    echo "This helper stops services for safe updates."
    echo "After deploying new files, restart the service."
fi
EOF

chmod +x /usr/local/bin/tavabharat-update
log_success "Update helper created"

# Install mailutils for email alerts (optional)
if [ -n "${ALERT_EMAIL:-}" ]; then
    log_info "Email alerts configured, installing mail utilities..."
    apt-get install -y -qq mailutils
    log_success "Mail utilities installed"
    log_info "Alert emails will be sent to: $ALERT_EMAIL"
else
    log_warning "No alert email configured (set ALERT_EMAIL in configs/.env)"
fi

# Summary
echo ""
echo "========================================"
echo "Monitoring Setup Complete!"
echo "========================================"
echo ""
echo "Configured Components:"
echo "  ✓ Health checks (every 5 minutes)"
echo "  ✓ Database backups (daily at 2 AM)"
echo "  ✓ Resource monitoring (hourly)"
echo "  ✓ Log rotation (daily, keep 7 days)"
echo "  ✓ Log cleanup (weekly)"
echo ""
echo "Monitoring Locations:"
echo "  Health logs:     /var/log/tavabharat/health-check.log"
echo "  Backup logs:     /var/log/tavabharat/backup.log"
echo "  Resource logs:   /var/log/tavabharat/resource-monitor.log"
echo "  Database backups: /var/backups/mssql/"
echo ""
echo "Useful Commands:"
echo "  Status dashboard:    tavabharat-status"
echo "  Update applications: tavabharat-update [api1|api2|angular|react]"
echo "  Manual health check: cd $(pwd) && sudo ./monitoring/health-check.sh"
echo "  Manual backup:       cd $(pwd) && sudo ./monitoring/backup-databases.sh"
echo "  View cron jobs:      cat /etc/cron.d/tavabharat-monitoring"
echo ""
echo "Log Locations:"
echo "  API 1:    sudo journalctl -u api1 -f"
echo "  API 2:    sudo journalctl -u api2 -f"
echo "  MSSQL:    sudo journalctl -u mssql-server -f"
echo "  Nginx:    sudo tail -f /var/log/nginx/tavabharat-error.log"
echo ""
log_success "Monitoring is configured and running!"
