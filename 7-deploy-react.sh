#!/bin/bash
#
# Deploy React UI - Admin Panel
# Deploys React application to /var/www/react
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
echo "Deploy React UI - Admin Panel"
echo "========================================"

APP_DIR="/var/www/react"

# Deployment method selection
echo ""
echo "Deployment Methods:"
echo "  1. Upload pre-built build/ folder (ZIP file)"
echo "  2. Clone source code and build"
echo "  3. Use existing files in $APP_DIR"
echo ""
read -p "Select deployment method [1-3]: " METHOD

case $METHOD in
    1)
        read -p "Path to ZIP file (containing build/ or dist/ folder): " ZIP_PATH
        if [ ! -f "$ZIP_PATH" ]; then
            log_error "File not found: $ZIP_PATH"
            exit 1
        fi
        
        log_info "Extracting application..."
        rm -rf $APP_DIR/*
        unzip -q "$ZIP_PATH" -d /tmp/react-extract
        
        # Find build or dist folder
        BUILD_FOLDER=$(find /tmp/react-extract -type d \( -name "build" -o -name "dist" \) | head -1)
        
        if [ -z "$BUILD_FOLDER" ]; then
            # No build/dist folder found, assume files are in root
            mv /tmp/react-extract/* $APP_DIR/
        else
            # Copy contents of build/dist folder
            mv "$BUILD_FOLDER"/* $APP_DIR/
        fi
        
        rm -rf /tmp/react-extract
        log_success "Application extracted"
        ;;
        
    2)
        read -p "Git repository URL: " GIT_URL
        read -p "Branch (default: main): " GIT_BRANCH
        GIT_BRANCH=${GIT_BRANCH:-main}
        
        # Install Node.js if not present
        if ! command -v node &> /dev/null; then
            log_info "Installing Node.js 20.x..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            apt-get install -y -qq nodejs
            log_success "Node.js installed: $(node --version)"
        fi
        
        # Clone repository
        log_info "Cloning repository..."
        rm -rf /tmp/react-source
        git clone -b "$GIT_BRANCH" "$GIT_URL" /tmp/react-source
        
        cd /tmp/react-source
        
        # Install dependencies
        log_info "Installing dependencies (this may take a few minutes)..."
        npm install --quiet
        
        # Build application
        log_info "Building React application..."
        npm run build
        
        # Find and copy build or dist folder
        if [ -d "/tmp/react-source/build" ]; then
            BUILD_FOLDER="/tmp/react-source/build"
        elif [ -d "/tmp/react-source/dist" ]; then
            BUILD_FOLDER="/tmp/react-source/dist"
        else
            log_error "Build failed or build/dist folder not found"
            exit 1
        fi
        
        rm -rf $APP_DIR/*
        cp -r "$BUILD_FOLDER"/* $APP_DIR/
        
        # Cleanup
        cd /
        rm -rf /tmp/react-source
        
        log_success "Application built and deployed"
        ;;
        
    3)
        log_info "Using existing files in $APP_DIR"
        if [ ! -d "$APP_DIR" ] || [ -z "$(ls -A $APP_DIR)" ]; then
            log_error "Directory is empty: $APP_DIR"
            exit 1
        fi
        ;;
        
    *)
        log_error "Invalid selection"
        exit 1
        ;;
esac

# Verify index.html exists
if [ ! -f "$APP_DIR/index.html" ]; then
    log_error "index.html not found in $APP_DIR"
    log_error "Please ensure the build output is correctly deployed"
    exit 1
fi

# Update API endpoints in config files if they exist
log_info "Checking for API endpoint configuration..."

# Common React config files and embedded config
CONFIG_FILES=("$APP_DIR/config.json" "$APP_DIR/env-config.js")

SERVER_IP="${SERVER_IP:-localhost}"

for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Found config file: $CONFIG_FILE"
        
        # Create backup
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        
        # Update API endpoints (if they exist in the file)
        sed -i "s|http://localhost:5000|http://$SERVER_IP|g" "$CONFIG_FILE" || true
        sed -i "s|http://localhost:5001|http://$SERVER_IP|g" "$CONFIG_FILE" || true
        sed -i "s|https://.*\.azurewebsites\.net|http://$SERVER_IP|g" "$CONFIG_FILE" || true
        
        log_info "Updated API endpoints to use: http://$SERVER_IP"
    fi
done

# Update base URL in index.html for /admin path
log_info "Configuring for /admin path..."

if grep -q '<base href="/"' "$APP_DIR/index.html" 2>/dev/null; then
    sed -i 's|<base href="/"|<base href="/admin/"|g' "$APP_DIR/index.html"
    log_success "Updated base href to /admin/"
fi

# Set proper permissions
chown -R ubuntu:ubuntu $APP_DIR
chmod -R 755 $APP_DIR
log_success "Permissions set"

# Summary
echo ""
echo "========================================"
echo "React UI Deployment Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Location: $APP_DIR"
echo "  Route: /admin (via Nginx)"
echo "  Files: $(ls -1 $APP_DIR | wc -l) files deployed"
echo ""
echo "Deployed Files:"
ls -lh $APP_DIR | head -10
echo ""
echo "Next Steps:"
echo "  1. Run ./8-configure-nginx.sh to setup reverse proxy"
echo "  2. Access your admin panel via http://YOUR_IP/admin"
echo ""
log_success "React UI deployed successfully!"
