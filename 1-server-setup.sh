#!/bin/bash
#
# Server Setup Script for TavaBharat Migration
# Prepares Ubuntu 22.04 LTS on AWS Lightsail for application deployment
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
echo "TavaBharat Server Setup"
echo "AWS Lightsail - Ubuntu 22.04 LTS"
echo "========================================"

# 1. Update system packages
log_info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
log_success "System packages updated"

# 2. Install essential tools
log_info "Installing essential tools..."
apt-get install -y -qq \
    curl \
    wget \
    unzip \
    git \
    vim \
    htop \
    net-tools \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential \
    jq \
    bc
log_success "Essential tools installed"

# 3. Configure timezone
log_info "Setting timezone to Asia/Kolkata..."
timedatectl set-timezone Asia/Kolkata
log_success "Timezone configured: $(timedatectl | grep 'Time zone')"

# 4. Setup swap (2GB)
if [ -f /swapfile ]; then
    log_warning "Swap file already exists, skipping creation"
else
    log_info "Creating 2GB swap file..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make swap permanent
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Configure swappiness
    sysctl vm.swappiness=10
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    fi
    
    log_success "Swap configured: $(free -h | grep Swap)"
fi

# 5. Configure firewall (UFW)
log_info "Configuring firewall..."
if ! command -v ufw &> /dev/null; then
    apt-get install -y -qq ufw
fi

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow HTTP/HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Enable firewall
echo "y" | ufw enable
ufw status numbered
log_success "Firewall configured"

# 6. Optimize system settings
log_info "Optimizing system settings..."

# Increase file descriptor limits
cat > /etc/security/limits.d/99-tavabharat.conf << EOF
* soft nofile 65536
* hard nofile 65536
ubuntu soft nofile 65536
ubuntu hard nofile 65536
EOF

# Network optimizations
cat >> /etc/sysctl.conf << EOF

# TavaBharat network optimizations
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF

sysctl -p > /dev/null
log_success "System settings optimized"

# 7. Create directory structure
log_info "Creating directory structure..."

# Application directories
mkdir -p /var/www/api1
mkdir -p /var/www/api2
mkdir -p /var/www/angular
mkdir -p /var/www/react

# Log directories
mkdir -p /var/log/tavabharat
mkdir -p /var/log/api1
mkdir -p /var/log/api2

# Backup directories
mkdir -p /var/backups/mssql
mkdir -p /var/backups/configs

# Set permissions
chown -R ubuntu:ubuntu /var/www
chown -R ubuntu:ubuntu /var/log/tavabharat
chown -R ubuntu:ubuntu /var/log/api1
chown -R ubuntu:ubuntu /var/log/api2
chown -R ubuntu:ubuntu /var/backups/mssql
chown -R ubuntu:ubuntu /var/backups/configs

# Set directory permissions
chmod 755 /var/www/api1
chmod 755 /var/www/api2
chmod 755 /var/www/angular
chmod 755 /var/www/react

log_success "Directory structure created"

# 8. Configure log rotation
log_info "Configuring log rotation..."

cat > /etc/logrotate.d/tavabharat << EOF
/var/log/tavabharat/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 ubuntu ubuntu
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

# 9. Install monitoring tools
log_info "Installing monitoring tools..."
apt-get install -y -qq sysstat iotop iftop
log_success "Monitoring tools installed"

# 10. System information summary
echo ""
echo "========================================"
echo "Server Setup Complete!"
echo "========================================"
echo ""
echo "System Information:"
echo "  OS: $(lsb_release -d | cut -f2)"
echo "  Kernel: $(uname -r)"
echo "  Hostname: $(hostname)"
echo "  IP Address: $(hostname -I | awk '{print $1}')"
echo "  Timezone: $(timedatectl | grep 'Time zone' | awk '{print $3}')"
echo ""
echo "Resources:"
echo "  CPU Cores: $(nproc)"
echo "  Total RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "  Total Swap: $(free -h | grep Swap | awk '{print $2}')"
echo "  Disk Space: $(df -h / | awk 'NR==2 {print $4}') available"
echo ""
echo "Next Steps:"
echo "  1. Run ./2-install-mssql.sh to install MSSQL Server"
echo "  2. Run ./3-migrate-databases.sh to migrate databases"
echo "  3. Run ./4-deploy-api1.sh and ./5-deploy-api2.sh for APIs"
echo "  4. Run ./6-deploy-angular.sh and ./7-deploy-react.sh for UIs"
echo "  5. Run ./8-configure-nginx.sh to setup reverse proxy"
echo "  6. Run ./9-setup-ssl.sh to configure SSL"
echo "  7. Run ./10-monitoring.sh to setup monitoring"
echo ""
log_success "Server is ready for application deployment!"
