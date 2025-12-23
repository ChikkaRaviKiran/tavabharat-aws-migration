#!/bin/bash
#
# Deploy API 1 - Primary Business API
# Deploys .NET API to /var/www/api1
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
echo "Deploy API 1 - Primary Business API"
echo "========================================"

# Load configuration
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

API_DIR="/var/www/api1"
API_PORT="${API1_PORT:-5000}"
API_USER="${API1_DB_USER:-api1_user}"
API_PASS="${API1_DB_PASSWORD:-Api1Password123!}"
DB_NAME="${API1_DB_NAME:-TavaBharatDB_Prod}"

# Deployment method selection
echo ""
echo "Deployment Methods:"
echo "  1. Upload published .NET application (ZIP file)"
echo "  2. Clone from Git repository"
echo "  3. Use existing files in $API_DIR"
echo ""
read -p "Select deployment method [1-3]: " METHOD

case $METHOD in
    1)
        read -p "Path to ZIP file: " ZIP_PATH
        if [ ! -f "$ZIP_PATH" ]; then
            log_error "File not found: $ZIP_PATH"
            exit 1
        fi
        
        log_info "Extracting application..."
        rm -rf $API_DIR/*
        unzip -q "$ZIP_PATH" -d $API_DIR
        log_success "Application extracted"
        ;;
        
    2)
        read -p "Git repository URL: " GIT_URL
        read -p "Branch (default: main): " GIT_BRANCH
        GIT_BRANCH=${GIT_BRANCH:-main}
        
        log_info "Cloning repository..."
        rm -rf $API_DIR/*
        git clone -b "$GIT_BRANCH" "$GIT_URL" $API_DIR
        log_success "Repository cloned"
        ;;
        
    3)
        log_info "Using existing files in $API_DIR"
        if [ ! -d "$API_DIR" ] || [ -z "$(ls -A $API_DIR)" ]; then
            log_error "Directory is empty: $API_DIR"
            exit 1
        fi
        ;;
        
    *)
        log_error "Invalid selection"
        exit 1
        ;;
esac

# Detect .NET version and DLL
log_info "Detecting application configuration..."

# Find .csproj files
CSPROJ_FILE=$(find $API_DIR -name "*.csproj" -type f | head -1)

if [ -n "$CSPROJ_FILE" ]; then
    # Extract target framework
    DOTNET_VERSION=$(grep -oP '(?<=<TargetFramework>net)\d+' "$CSPROJ_FILE" || echo "")
    log_info "Detected .NET version: $DOTNET_VERSION"
    
    # Check if we need to publish
    if [ ! -f "$API_DIR"/*.dll ] && [ -f "$CSPROJ_FILE" ]; then
        log_warning "No DLL found, need to publish the application"
        
        # Check if .NET SDK is installed
        if ! command -v dotnet &> /dev/null; then
            log_info "Installing .NET SDK..."
            
            # Determine version to install (default to .NET 8)
            INSTALL_VERSION=${DOTNET_VERSION:-8}
            
            wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
            dpkg -i /tmp/packages-microsoft-prod.deb
            rm /tmp/packages-microsoft-prod.deb
            
            apt-get update -qq
            apt-get install -y -qq dotnet-sdk-${INSTALL_VERSION}.0
            
            log_success ".NET SDK installed"
        fi
        
        # Publish application
        log_info "Publishing application..."
        cd $API_DIR
        dotnet publish -c Release -o $API_DIR/publish
        
        # Move published files to root
        mv $API_DIR/publish/* $API_DIR/
        rmdir $API_DIR/publish
        
        log_success "Application published"
    fi
else
    log_info "No .csproj file found, assuming pre-published application"
fi

# Find main DLL
MAIN_DLL=$(find $API_DIR -maxdepth 1 -name "*.dll" -type f | grep -v "Microsoft\|System\|runtime" | head -1)

if [ -z "$MAIN_DLL" ]; then
    log_error "No main DLL found in $API_DIR"
    exit 1
fi

DLL_NAME=$(basename "$MAIN_DLL")
log_info "Main DLL: $DLL_NAME"

# Install .NET Runtime if not installed
if ! command -v dotnet &> /dev/null; then
    log_info "Installing .NET Runtime..."
    
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb
    rm /tmp/packages-microsoft-prod.deb
    
    apt-get update -qq
    apt-get install -y -qq aspnetcore-runtime-8.0
    
    log_success ".NET Runtime installed"
fi

# Create/update appsettings.Production.json
log_info "Configuring application settings..."

CONNECTION_STRING="Server=localhost;Database=$DB_NAME;User Id=$API_USER;Password=$API_PASS;TrustServerCertificate=True;Max Pool Size=100;Connection Timeout=30;"

# Check if appsettings.json exists
if [ -f "$API_DIR/appsettings.json" ]; then
    # Create Production override
    cat > "$API_DIR/appsettings.Production.json" << EOF
{
  "ConnectionStrings": {
    "DefaultConnection": "$CONNECTION_STRING"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
EOF
    log_success "appsettings.Production.json created"
fi

# Create .env file
cat > "$API_DIR/.env" << EOF
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://localhost:$API_PORT
ConnectionStrings__DefaultConnection=$CONNECTION_STRING
EOF

chmod 600 "$API_DIR/.env"
log_success "Environment file created"

# Set permissions
chown -R ubuntu:ubuntu $API_DIR
chmod 755 $API_DIR
log_success "Permissions set"

# Create systemd service
log_info "Creating systemd service..."

cat > /etc/systemd/system/api1.service << EOF
[Unit]
Description=TavaBharat API 1
After=network.target mssql-server.service

[Service]
Type=notify
WorkingDirectory=$API_DIR
ExecStart=/usr/bin/dotnet $API_DIR/$DLL_NAME
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=api1
User=ubuntu
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://localhost:$API_PORT
EnvironmentFile=$API_DIR/.env

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
systemctl daemon-reload
systemctl enable api1
systemctl restart api1

# Wait for service to start
sleep 3

# Check service status
if systemctl is-active --quiet api1; then
    log_success "API 1 service started successfully"
else
    log_error "API 1 service failed to start"
    journalctl -u api1 -n 50 --no-pager
    exit 1
fi

# Test health endpoint
log_info "Testing API endpoint..."
sleep 2

if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:$API_PORT 2>/dev/null | grep -q "200\|404"; then
    log_success "API is responding on port $API_PORT"
else
    log_warning "API may not be responding correctly (this might be expected if no root endpoint exists)"
fi

# Summary
echo ""
echo "========================================"
echo "API 1 Deployment Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Location: $API_DIR"
echo "  Port: $API_PORT"
echo "  Route: /api/v1/* (via Nginx)"
echo "  Database: $DB_NAME"
echo "  DLL: $DLL_NAME"
echo ""
echo "Service Status:"
systemctl status api1 --no-pager -l | head -5
echo ""
echo "Useful Commands:"
echo "  View logs: sudo journalctl -u api1 -f"
echo "  Restart: sudo systemctl restart api1"
echo "  Stop: sudo systemctl stop api1"
echo "  Status: sudo systemctl status api1"
echo ""
echo "Next Steps:"
echo "  1. Run ./5-deploy-api2.sh to deploy the second API"
echo "  2. Run ./8-configure-nginx.sh to setup reverse proxy"
echo ""
log_success "API 1 is running!"
