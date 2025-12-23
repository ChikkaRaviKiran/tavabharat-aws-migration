#!/bin/bash
#
# MSSQL Server Express Installation Script
# Installs and configures MSSQL Server 2022 Express Edition
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
echo "MSSQL Server Express Installation"
echo "========================================"

# Load configuration if exists
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# Get SA password
if [ -z "${MSSQL_SA_PASSWORD:-}" ]; then
    log_warning "SA password not set in configs/.env"
    read -sp "Enter SA password (min 8 chars, uppercase, lowercase, digits, special chars): " SA_PASSWORD
    echo
    read -sp "Confirm SA password: " SA_PASSWORD_CONFIRM
    echo
    
    if [ "$SA_PASSWORD" != "$SA_PASSWORD_CONFIRM" ]; then
        log_error "Passwords do not match"
        exit 1
    fi
    
    MSSQL_SA_PASSWORD="$SA_PASSWORD"
fi

# 1. Add Microsoft repository
log_info "Adding Microsoft SQL Server repository..."
curl -s https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
add-apt-repository "$(curl -s https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-2022.list)"
apt-get update -qq
log_success "Repository added"

# 2. Install MSSQL Server
log_info "Installing MSSQL Server 2022..."
apt-get install -y -qq mssql-server
log_success "MSSQL Server package installed"

# 3. Configure MSSQL Server
log_info "Configuring MSSQL Server (Express Edition)..."

# Run setup with environment variables
MSSQL_PID=Express \
ACCEPT_EULA=Y \
MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
/opt/mssql/bin/mssql-conf -n setup

log_success "MSSQL Server configured"

# 4. Start and enable service
log_info "Starting MSSQL Server..."
systemctl start mssql-server
systemctl enable mssql-server
sleep 5

if systemctl is-active --quiet mssql-server; then
    log_success "MSSQL Server is running"
else
    log_error "MSSQL Server failed to start"
    journalctl -u mssql-server -n 50 --no-pager
    exit 1
fi

# 5. Optimize memory for 2GB server (set to 768MB)
log_info "Optimizing memory settings for 2GB server..."
/opt/mssql/bin/mssql-conf set memory.memorylimitmb 768
systemctl restart mssql-server
sleep 5
log_success "Memory limit set to 768MB"

# 6. Install MSSQL command-line tools
log_info "Installing MSSQL command-line tools..."

# Add Microsoft repository for tools
curl -s https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl -s https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
apt-get update -qq

# Install mssql-tools18 (with sqlcmd)
ACCEPT_EULA=Y apt-get install -y -qq mssql-tools18 unixodbc-dev

# Add to PATH
if ! grep -q '/opt/mssql-tools18/bin' /etc/environment; then
    echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/mssql-tools18/bin"' > /etc/environment
fi

# Also add to current session
export PATH="$PATH:/opt/mssql-tools18/bin"

# Add to ubuntu user's bashrc
if ! grep -q '/opt/mssql-tools18/bin' /home/ubuntu/.bashrc; then
    echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> /home/ubuntu/.bashrc
fi

log_success "MSSQL tools installed"

# 7. Install sqlpackage
log_info "Installing sqlpackage..."

# Download and install sqlpackage
wget -q https://aka.ms/sqlpackage-linux -O /tmp/sqlpackage.zip
unzip -q /tmp/sqlpackage.zip -d /opt/sqlpackage
chmod +x /opt/sqlpackage/sqlpackage

# Create symlink
ln -sf /opt/sqlpackage/sqlpackage /usr/local/bin/sqlpackage

# Cleanup
rm /tmp/sqlpackage.zip

log_success "sqlpackage installed"

# 8. Test connection
log_info "Testing database connection..."

if /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT @@VERSION" -C > /dev/null 2>&1; then
    log_success "Database connection successful"
else
    log_error "Cannot connect to database"
    exit 1
fi

# 9. Get SQL Server version
SQL_VERSION=$(/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT @@VERSION" -h -1 -C 2>/dev/null | head -1)

# 10. Create initial databases
log_info "Creating databases..."

# Create database for API 1
DB1_NAME="${AZURE_SQL_DB1:-TavaBharatDB_Prod}"
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '$DB1_NAME') CREATE DATABASE [$DB1_NAME]" -C

# Create database for API 2 (if specified)
if [ -n "${AZURE_SQL_DB2:-}" ] && [ "${AZURE_SQL_DB2}" != "SecondDatabase" ]; then
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '${AZURE_SQL_DB2}') CREATE DATABASE [${AZURE_SQL_DB2}]" -C
fi

log_success "Databases created"

# 11. Summary
echo ""
echo "========================================"
echo "MSSQL Server Installation Complete!"
echo "========================================"
echo ""
echo "SQL Server Information:"
echo "  Version: MSSQL Server 2022 Express"
echo "  Edition: Express (FREE, 10GB limit per database)"
echo "  Memory Limit: 768MB (optimized for 2GB server)"
echo "  Host: localhost"
echo "  Port: 1433"
echo "  SA User: sa"
echo ""
echo "Installed Tools:"
echo "  sqlcmd: $(which sqlcmd 2>/dev/null || echo 'Installed')"
echo "  sqlpackage: $(which sqlpackage 2>/dev/null || echo 'Installed')"
echo ""
echo "Service Status:"
systemctl status mssql-server --no-pager -l | head -5
echo ""
echo "Next Steps:"
echo "  1. Run ./3-migrate-databases.sh to migrate databases from Azure"
echo "  2. Test connection: sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -C"
echo ""
log_success "MSSQL Server is ready!"
