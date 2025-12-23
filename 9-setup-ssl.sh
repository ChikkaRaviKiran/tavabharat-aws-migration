#!/bin/bash
#
# SSL/TLS Setup Script
# Configures HTTPS using Let's Encrypt or self-signed certificates
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
echo "SSL/TLS Certificate Setup"
echo "========================================"

# Load configuration
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# SSL method selection
echo ""
echo "SSL Certificate Options:"
echo "  1. Let's Encrypt (FREE, requires domain name)"
echo "  2. Self-signed certificate (for testing/IP-only access)"
echo "  3. Skip SSL configuration"
echo ""
read -p "Select SSL method [1-3]: " METHOD

case $METHOD in
    1)
        log_info "Method 1: Let's Encrypt Certificate"
        
        # Get domain name
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        
        if [ -z "$DOMAIN_NAME" ]; then
            log_error "Domain name is required for Let's Encrypt"
            exit 1
        fi
        
        # Validate domain points to this server
        log_info "Checking DNS resolution..."
        DOMAIN_IP=$(dig +short "$DOMAIN_NAME" | tail -1)
        SERVER_IP=$(curl -s ifconfig.me)
        
        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            log_warning "Domain $DOMAIN_NAME resolves to $DOMAIN_IP"
            log_warning "This server's IP is $SERVER_IP"
            log_warning "DNS may not be configured correctly. Let's Encrypt may fail."
            read -p "Continue anyway? [y/N]: " CONTINUE
            if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
                exit 1
            fi
        fi
        
        # Get admin email
        ADMIN_EMAIL="${ADMIN_EMAIL:-}"
        if [ -z "$ADMIN_EMAIL" ]; then
            read -p "Enter your email address (for certificate notifications): " ADMIN_EMAIL
        fi
        
        # Install certbot
        log_info "Installing certbot..."
        apt-get update -qq
        apt-get install -y -qq certbot python3-certbot-nginx
        log_success "Certbot installed"
        
        # Update Nginx config with domain name
        log_info "Updating Nginx configuration..."
        sed -i "s/server_name .*/server_name $DOMAIN_NAME;/" /etc/nginx/sites-available/tavabharat
        nginx -t && systemctl reload nginx
        
        # Obtain certificate
        log_info "Obtaining Let's Encrypt certificate..."
        log_warning "This will modify your Nginx configuration"
        
        if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$ADMIN_EMAIL" --redirect; then
            log_success "SSL certificate obtained and installed"
            
            # Setup auto-renewal
            log_info "Setting up automatic renewal..."
            
            # Certbot automatically installs a renewal timer, let's verify
            if systemctl list-timers | grep -q certbot; then
                log_success "Auto-renewal is configured"
                systemctl status certbot.timer --no-pager | head -5
            else
                log_warning "Auto-renewal timer not found, adding cron job"
                echo "0 3 * * * root certbot renew --quiet" > /etc/cron.d/certbot-renewal
                log_success "Cron job added for certificate renewal"
            fi
        else
            log_error "Failed to obtain Let's Encrypt certificate"
            log_info "Common issues:"
            log_info "  - Domain doesn't point to this server"
            log_info "  - Port 80 is not accessible from internet"
            log_info "  - Firewall blocking connections"
            exit 1
        fi
        ;;
        
    2)
        log_info "Method 2: Self-Signed Certificate"
        log_warning "Self-signed certificates will show browser warnings"
        log_warning "Only use for testing or when domain is not available"
        
        # Create SSL directory
        mkdir -p /etc/nginx/ssl
        
        # Get server name
        SERVER_NAME="${SERVER_IP:-localhost}"
        read -p "Enter server name/IP (default: $SERVER_NAME): " input_server
        SERVER_NAME=${input_server:-$SERVER_NAME}
        
        # Generate self-signed certificate
        log_info "Generating self-signed certificate..."
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/tavabharat.key \
            -out /etc/nginx/ssl/tavabharat.crt \
            -subj "/C=IN/ST=State/L=City/O=TavaBharat/CN=$SERVER_NAME"
        
        chmod 600 /etc/nginx/ssl/tavabharat.key
        chmod 644 /etc/nginx/ssl/tavabharat.crt
        
        log_success "Self-signed certificate created"
        
        # Update Nginx configuration for SSL
        log_info "Updating Nginx configuration for SSL..."
        
        # Backup original config
        cp /etc/nginx/sites-available/tavabharat /etc/nginx/sites-available/tavabharat.backup
        
        # Create new config with SSL
        cat > /etc/nginx/sites-available/tavabharat << 'EOF'
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name SERVER_NAME_PLACEHOLDER;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name SERVER_NAME_PLACEHOLDER;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/tavabharat.crt;
    ssl_certificate_key /etc/nginx/ssl/tavabharat.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Increase buffer sizes
    client_max_body_size 50M;
    client_body_buffer_size 128k;
    large_client_header_buffers 4 32k;
    
    # Angular UI
    location / {
        root /var/www/angular;
        try_files $uri $uri/ /index.html;
        
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        gzip on;
        gzip_vary on;
        gzip_min_length 1024;
        gzip_types text/css application/javascript application/json text/plain text/xml application/xml;
    }

    # React UI
    location /admin {
        alias /var/www/react;
        try_files $uri $uri/ /admin/index.html;
    }

    # API 1
    location /api/v1 {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass $http_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # API 2
    location /api/v2 {
        proxy_pass http://localhost:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass $http_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Logging
    access_log /var/log/nginx/tavabharat-access.log;
    error_log /var/log/nginx/tavabharat-error.log;
}
EOF

        # Replace server name
        sed -i "s/SERVER_NAME_PLACEHOLDER/$SERVER_NAME/g" /etc/nginx/sites-available/tavabharat
        
        # Test and reload Nginx
        if nginx -t; then
            systemctl reload nginx
            log_success "Nginx configured for HTTPS"
        else
            log_error "Nginx configuration error"
            mv /etc/nginx/sites-available/tavabharat.backup /etc/nginx/sites-available/tavabharat
            exit 1
        fi
        
        # Update firewall
        log_info "Updating firewall for HTTPS..."
        ufw allow 443/tcp comment 'HTTPS'
        log_success "Firewall updated"
        ;;
        
    3)
        log_info "Skipping SSL configuration"
        log_warning "Your site will only be accessible via HTTP (not secure)"
        exit 0
        ;;
        
    *)
        log_error "Invalid selection"
        exit 1
        ;;
esac

# Test HTTPS
log_info "Testing HTTPS connection..."
sleep 2

if curl -k -f -s -o /dev/null https://localhost/ 2>/dev/null; then
    log_success "HTTPS is working"
else
    log_warning "HTTPS connection test failed (may be expected)"
fi

# Summary
echo ""
echo "========================================"
echo "SSL Configuration Complete!"
echo "========================================"
echo ""
if [ "$METHOD" == "1" ]; then
    echo "Certificate Type: Let's Encrypt (Valid for 90 days)"
    echo "Domain: $DOMAIN_NAME"
    echo "Auto-renewal: Enabled"
    echo ""
    echo "Your site: https://$DOMAIN_NAME"
elif [ "$METHOD" == "2" ]; then
    echo "Certificate Type: Self-Signed (Valid for 1 year)"
    echo "Server: $SERVER_NAME"
    echo ""
    echo "⚠️  Browser Warning: Self-signed certificates show security warnings"
    echo "Your site: https://$SERVER_NAME (accept the warning)"
fi
echo ""
echo "Next Steps:"
echo "  1. Test HTTPS access in your browser"
echo "  2. Run ./10-monitoring.sh to setup monitoring"
echo ""
log_success "SSL/TLS is configured!"
