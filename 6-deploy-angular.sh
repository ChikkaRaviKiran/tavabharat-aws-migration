#!/bin/bash
#
# Deploy Angular UI - Main Application
# Deploys Angular application to /var/www/angular
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
echo "Deploy Angular UI - Main Application"
echo "========================================"

APP_DIR="/var/www/angular"

# Deployment method selection
echo ""
echo "Deployment Methods:"
echo "  1. Upload pre-built dist/ folder (ZIP file)"
echo "  2. Clone source code and build"
echo "  3. Use existing files in $APP_DIR"
echo ""
read -p "Select deployment method [1-3]: " METHOD

case $METHOD in
    1)
        read -p "Path to ZIP file (containing dist/ folder): " ZIP_PATH
        if [ ! -f "$ZIP_PATH" ]; then
            log_error "File not found: $ZIP_PATH"
            exit 1
        fi
        
        log_info "Extracting application..."
        rm -rf $APP_DIR/*
        unzip -q "$ZIP_PATH" -d /tmp/angular-extract
        
        # Find dist folder
        DIST_FOLDER=$(find /tmp/angular-extract -type d -name "dist" | head -1)
        
        if [ -z "$DIST_FOLDER" ]; then
            # No dist folder found, assume files are in root
            mv /tmp/angular-extract/* $APP_DIR/
        else
            # Copy contents of dist folder
            # Check if dist has a subfolder (common in Angular)
            INNER_FOLDER=$(find "$DIST_FOLDER" -mindepth 1 -maxdepth 1 -type d | head -1)
            if [ -n "$INNER_FOLDER" ]; then
                mv "$INNER_FOLDER"/* $APP_DIR/
            else
                mv "$DIST_FOLDER"/* $APP_DIR/
            fi
        fi
        
        rm -rf /tmp/angular-extract
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
        rm -rf /tmp/angular-source
        git clone -b "$GIT_BRANCH" "$GIT_URL" /tmp/angular-source
        
        cd /tmp/angular-source
        
        # Install dependencies
        log_info "Installing dependencies (this may take a few minutes)..."
        npm install --quiet
        
        # Build application
        log_info "Building Angular application..."
        npm run build -- --configuration production
        
        # Find and copy dist folder
        DIST_FOLDER=$(find /tmp/angular-source -type d -name "dist" | head -1)
        
        if [ -z "$DIST_FOLDER" ]; then
            log_error "Build failed or dist folder not found"
            exit 1
        fi
        
        rm -rf $APP_DIR/*
        
        # Check if dist has a subfolder (common in Angular)
        INNER_FOLDER=$(find "$DIST_FOLDER" -mindepth 1 -maxdepth 1 -type d | head -1)
        if [ -n "$INNER_FOLDER" ]; then
            cp -r "$INNER_FOLDER"/* $APP_DIR/
        else
            cp -r "$DIST_FOLDER"/* $APP_DIR/
        fi
        
        # Cleanup
        cd /
        rm -rf /tmp/angular-source
        
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

# Common Angular config files
CONFIG_FILES=("$APP_DIR/assets/config.json" "$APP_DIR/assets/config/config.json" "$APP_DIR/config.json")

SERVER_IP="${SERVER_IP:-localhost}"

for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Found config file: $CONFIG_FILE"
        
        # Create backup
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        
        # Update API endpoints (if they exist in the file)
        sed -i "s|http://localhost:5000|http://$SERVER_IP|g" "$CONFIG_FILE" || true
        sed -i "s|https://.*\.azurewebsites\.net|http://$SERVER_IP|g" "$CONFIG_FILE" || true
        
        log_info "Updated API endpoints to use: http://$SERVER_IP"
    fi
done

# Set proper permissions
chown -R ubuntu:ubuntu $APP_DIR
chmod -R 755 $APP_DIR
log_success "Permissions set"

# Summary
echo ""
echo "========================================"
echo "Angular UI Deployment Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Location: $APP_DIR"
echo "  Route: / (root, via Nginx)"
echo "  Files: $(ls -1 $APP_DIR | wc -l) files deployed"
echo ""
echo "Deployed Files:"
ls -lh $APP_DIR | head -10
echo ""
echo "Next Steps:"
echo "  1. Run ./7-deploy-react.sh to deploy React UI (if needed)"
echo "  2. Run ./8-configure-nginx.sh to setup reverse proxy"
echo "  3. Access your application via Nginx after configuration"
echo ""
log_success "Angular UI deployed successfully!"
