#!/bin/bash
#
# Configure Nginx as Reverse Proxy
# Sets up Nginx to serve applications and proxy API requests
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
echo "Configure Nginx Reverse Proxy"
echo "========================================"

# Load configuration
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# Install Nginx
if ! command -v nginx &> /dev/null; then
    log_info "Installing Nginx..."
    apt-get update -qq
    apt-get install -y -qq nginx
    log_success "Nginx installed"
else
    log_info "Nginx is already installed"
fi

# Get server IP or domain
SERVER_NAME="${SERVER_IP:-_}"
read -p "Enter your server IP or domain name (default: $SERVER_NAME): " input_server
SERVER_NAME=${input_server:-$SERVER_NAME}

log_info "Configuring Nginx for: $SERVER_NAME"

# Create Nginx configuration
log_info "Creating Nginx configuration..."

cat > /etc/nginx/sites-available/tavabharat << EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    # Increase buffer sizes for larger headers/cookies
    client_max_body_size 50M;
    client_body_buffer_size 128k;
    large_client_header_buffers 4 32k;
    
    # Angular UI (Main application)
    location / {
        root /var/www/angular;
        try_files \$uri \$uri/ /index.html;
        
        # Caching for static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # Disable caching for index.html
        location = /index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            add_header Pragma "no-cache";
            add_header Expires "0";
        }
        
        # Gzip compression
        gzip on;
        gzip_vary on;
        gzip_min_length 1024;
        gzip_types text/css application/javascript application/json text/plain text/xml application/xml;
    }

    # React UI (Admin panel)
    location /admin {
        alias /var/www/react;
        try_files \$uri \$uri/ /admin/index.html;
        
        # Caching for static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # Handle index.html
        location = /admin/ {
            alias /var/www/react/;
            try_files index.html =404;
        }
        
        location = /admin/index.html {
            alias /var/www/react/index.html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            add_header Pragma "no-cache";
            add_header Expires "0";
        }
    }

    # API 1 - Primary business API
    location /api/v1 {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
        
        # Standard proxy headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # API 2 - Secondary/Admin API
    location /api/v2 {
        proxy_pass http://localhost:5001;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
        
        # Standard proxy headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Logging
    access_log /var/log/nginx/tavabharat-access.log;
    error_log /var/log/nginx/tavabharat-error.log;
}
EOF

log_success "Configuration file created"

# Test Nginx configuration
log_info "Testing Nginx configuration..."
if nginx -t; then
    log_success "Nginx configuration is valid"
else
    log_error "Nginx configuration has errors"
    exit 1
fi

# Enable site
log_info "Enabling site..."
if [ -L /etc/nginx/sites-enabled/tavabharat ]; then
    rm /etc/nginx/sites-enabled/tavabharat
fi
ln -s /etc/nginx/sites-available/tavabharat /etc/nginx/sites-enabled/tavabharat

# Disable default site if it exists
if [ -L /etc/nginx/sites-enabled/default ]; then
    log_info "Disabling default Nginx site..."
    rm /etc/nginx/sites-enabled/default
fi

# Restart Nginx
log_info "Restarting Nginx..."
systemctl restart nginx

# Wait a moment for Nginx to start
sleep 2

# Check Nginx status
if systemctl is-active --quiet nginx; then
    log_success "Nginx is running"
else
    log_error "Nginx failed to start"
    journalctl -u nginx -n 50 --no-pager
    exit 1
fi

# Test all routes
log_info "Testing routes..."

# Test main page
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null | grep -q "200"; then
    log_success "Main page (/) is accessible"
else
    log_warning "Main page (/) may not be accessible"
fi

# Test admin page
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost/admin 2>/dev/null | grep -q "200"; then
    log_success "Admin page (/admin) is accessible"
else
    log_warning "Admin page (/admin) may not be accessible"
fi

# Test API 1
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost/api/v1 2>/dev/null | grep -q "200\|404\|401"; then
    log_success "API 1 (/api/v1) is reachable"
else
    log_warning "API 1 (/api/v1) may not be reachable"
fi

# Test API 2
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost/api/v2 2>/dev/null | grep -q "200\|404\|401"; then
    log_success "API 2 (/api/v2) is reachable"
else
    log_warning "API 2 (/api/v2) may not be reachable"
fi

# Summary
echo ""
echo "========================================"
echo "Nginx Configuration Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Server: $SERVER_NAME"
echo "  Config file: /etc/nginx/sites-available/tavabharat"
echo ""
echo "Routes:"
echo "  Main App:    http://$SERVER_NAME/"
echo "  Admin Panel: http://$SERVER_NAME/admin"
echo "  API 1:       http://$SERVER_NAME/api/v1/*"
echo "  API 2:       http://$SERVER_NAME/api/v2/*"
echo ""
echo "Service Status:"
systemctl status nginx --no-pager -l | head -5
echo ""
echo "Useful Commands:"
echo "  Test config:  sudo nginx -t"
echo "  Reload:       sudo systemctl reload nginx"
echo "  Restart:      sudo systemctl restart nginx"
echo "  View logs:    sudo tail -f /var/log/nginx/tavabharat-error.log"
echo ""
echo "Next Steps:"
echo "  1. Test all routes in your browser"
echo "  2. Run ./9-setup-ssl.sh to configure SSL/HTTPS (recommended)"
echo "  3. Run ./10-monitoring.sh to setup monitoring"
echo ""
log_success "Nginx is configured and running!"
