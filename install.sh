#!/bin/bash
#
# TavaBharat AWS Lightsail Migration - Master Installer
# One-command installation for complete migration
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
    exit 1
fi

# ASCII Art Header
clear
cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║              TavaBharat AWS Lightsail Migration                ║
║                                                                ║
║           Azure SQL → AWS Lightsail Migration Toolkit          ║
║                                                                ║
║  Components: 2 APIs + 2 UIs + 2 Databases + Nginx + MSSQL     ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF

echo ""

# Make all scripts executable
log_info "Making scripts executable..."
chmod +x *.sh
chmod +x monitoring/*.sh
chmod +x database/*.sh
log_success "Scripts are ready"

echo ""
echo "========================================"
echo "Installation Menu"
echo "========================================"
echo ""
echo "  1. Full Installation (All Steps)"
echo "  2. Server Setup Only"
echo "  3. Database Migration Only"
echo "  4. API Deployment Only"
echo "  5. UI Deployment Only"
echo "  6. Nginx Configuration Only"
echo "  7. SSL Setup Only"
echo "  8. Monitoring Setup Only"
echo "  9. Custom Selection"
echo "  0. Exit"
echo ""

read -p "Select option [0-9]: " OPTION

# Log file
LOG_FILE="installation_$(date +%Y%m%d_%H%M%S).log"
log_info "Logging to: $LOG_FILE"

# Execute based on selection
case $OPTION in
    1)
        log_step "Starting Full Installation..."
        
        # Step 1: Server Setup
        log_step "1/8: Server Setup"
        if ./1-server-setup.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Server setup completed"
        else
            log_error "Server setup failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to MSSQL installation..."
        
        # Step 2: MSSQL Installation
        log_step "2/8: MSSQL Installation"
        if ./2-install-mssql.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "MSSQL installation completed"
        else
            log_error "MSSQL installation failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to database migration..."
        
        # Step 3: Database Migration
        log_step "3/8: Database Migration"
        if ./3-migrate-databases.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Database migration completed"
        else
            log_error "Database migration failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to API 1 deployment..."
        
        # Step 4: Deploy API 1
        log_step "4/8: API 1 Deployment"
        if ./4-deploy-api1.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "API 1 deployment completed"
        else
            log_error "API 1 deployment failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to API 2 deployment..."
        
        # Step 5: Deploy API 2
        log_step "5/8: API 2 Deployment"
        if ./5-deploy-api2.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "API 2 deployment completed"
        else
            log_error "API 2 deployment failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to Angular deployment..."
        
        # Step 6: Deploy Angular
        log_step "6/8: Angular UI Deployment"
        if ./6-deploy-angular.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Angular deployment completed"
        else
            log_error "Angular deployment failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to React deployment..."
        
        # Step 7: Deploy React
        log_step "7/8: React UI Deployment"
        if ./7-deploy-react.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "React deployment completed"
        else
            log_error "React deployment failed"
            exit 1
        fi
        
        echo ""
        read -p "Press Enter to continue to Nginx configuration..."
        
        # Step 8: Configure Nginx
        log_step "8/8: Nginx Configuration"
        if ./8-configure-nginx.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Nginx configuration completed"
        else
            log_error "Nginx configuration failed"
            exit 1
        fi
        
        echo ""
        log_info "Optional: SSL and Monitoring"
        read -p "Setup SSL? [y/N]: " SETUP_SSL
        if [ "$SETUP_SSL" == "y" ] || [ "$SETUP_SSL" == "Y" ]; then
            ./9-setup-ssl.sh 2>&1 | tee -a "$LOG_FILE"
        fi
        
        echo ""
        read -p "Setup Monitoring? [y/N]: " SETUP_MON
        if [ "$SETUP_MON" == "y" ] || [ "$SETUP_MON" == "Y" ]; then
            ./10-monitoring.sh 2>&1 | tee -a "$LOG_FILE"
        fi
        ;;
        
    2)
        log_step "Running Server Setup..."
        ./1-server-setup.sh 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    3)
        log_step "Running Database Migration..."
        log_info "Prerequisites: MSSQL must be installed (run option 2 first if needed)"
        ./3-migrate-databases.sh 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    4)
        log_step "Running API Deployment..."
        echo ""
        echo "Which API?"
        echo "  1. API 1 (Port 5000)"
        echo "  2. API 2 (Port 5001)"
        echo "  3. Both"
        read -p "Select [1-3]: " API_CHOICE
        
        case $API_CHOICE in
            1)
                ./4-deploy-api1.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
            2)
                ./5-deploy-api2.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
            3)
                ./4-deploy-api1.sh 2>&1 | tee -a "$LOG_FILE"
                echo ""
                read -p "Press Enter to continue to API 2..."
                ./5-deploy-api2.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
        esac
        ;;
        
    5)
        log_step "Running UI Deployment..."
        echo ""
        echo "Which UI?"
        echo "  1. Angular (Main App)"
        echo "  2. React (Admin Panel)"
        echo "  3. Both"
        read -p "Select [1-3]: " UI_CHOICE
        
        case $UI_CHOICE in
            1)
                ./6-deploy-angular.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
            2)
                ./7-deploy-react.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
            3)
                ./6-deploy-angular.sh 2>&1 | tee -a "$LOG_FILE"
                echo ""
                read -p "Press Enter to continue to React..."
                ./7-deploy-react.sh 2>&1 | tee -a "$LOG_FILE"
                ;;
        esac
        ;;
        
    6)
        log_step "Running Nginx Configuration..."
        ./8-configure-nginx.sh 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    7)
        log_step "Running SSL Setup..."
        ./9-setup-ssl.sh 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    8)
        log_step "Running Monitoring Setup..."
        ./10-monitoring.sh 2>&1 | tee -a "$LOG_FILE"
        ;;
        
    9)
        log_step "Custom Selection"
        echo ""
        echo "Select components to install (space-separated numbers):"
        echo "  1. Server Setup"
        echo "  2. MSSQL Installation"
        echo "  3. Database Migration"
        echo "  4. API 1 Deployment"
        echo "  5. API 2 Deployment"
        echo "  6. Angular Deployment"
        echo "  7. React Deployment"
        echo "  8. Nginx Configuration"
        echo "  9. SSL Setup"
        echo "  10. Monitoring Setup"
        echo ""
        read -p "Enter numbers (e.g., 1 2 3): " SELECTIONS
        
        for num in $SELECTIONS; do
            case $num in
                1) ./1-server-setup.sh 2>&1 | tee -a "$LOG_FILE" ;;
                2) ./2-install-mssql.sh 2>&1 | tee -a "$LOG_FILE" ;;
                3) ./3-migrate-databases.sh 2>&1 | tee -a "$LOG_FILE" ;;
                4) ./4-deploy-api1.sh 2>&1 | tee -a "$LOG_FILE" ;;
                5) ./5-deploy-api2.sh 2>&1 | tee -a "$LOG_FILE" ;;
                6) ./6-deploy-angular.sh 2>&1 | tee -a "$LOG_FILE" ;;
                7) ./7-deploy-react.sh 2>&1 | tee -a "$LOG_FILE" ;;
                8) ./8-configure-nginx.sh 2>&1 | tee -a "$LOG_FILE" ;;
                9) ./9-setup-ssl.sh 2>&1 | tee -a "$LOG_FILE" ;;
                10) ./10-monitoring.sh 2>&1 | tee -a "$LOG_FILE" ;;
            esac
            echo ""
            read -p "Press Enter to continue..."
        done
        ;;
        
    0)
        log_info "Exiting..."
        exit 0
        ;;
        
    *)
        log_error "Invalid option"
        exit 1
        ;;
esac

# Final Summary
echo ""
echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo ""
log_success "Installation log saved to: $LOG_FILE"
echo ""
echo "System Status:"
./monitoring/health-check.sh || true
echo ""
echo "Next Steps:"
echo "  1. Test your applications in a browser"
echo "  2. Review logs if there are any issues"
echo "  3. Setup SSL if not done (./9-setup-ssl.sh)"
echo "  4. Configure monitoring if not done (./10-monitoring.sh)"
echo ""
echo "Useful Commands:"
echo "  Status:     tavabharat-status"
echo "  Update:     tavabharat-update [api1|api2|angular|react]"
echo "  Health:     sudo ./monitoring/health-check.sh"
echo ""
log_success "Migration toolkit installation completed!"
