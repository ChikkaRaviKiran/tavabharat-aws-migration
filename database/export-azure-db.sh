#!/bin/bash
#
# Export Azure SQL Database to .bacpac file
# This script uses sqlpackage to export databases from Azure SQL
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

# Load environment variables if .env exists
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# Create backup directory
BACKUP_DIR="database/backups"
mkdir -p "$BACKUP_DIR"

# Get Azure SQL credentials
read -p "Azure SQL Server (default: $AZURE_SQL_SERVER): " azure_server
azure_server=${azure_server:-$AZURE_SQL_SERVER}

read -p "Azure SQL Username (default: $AZURE_SQL_USER): " azure_user
azure_user=${azure_user:-$AZURE_SQL_USER}

read -sp "Azure SQL Password: " azure_password
echo
azure_password=${azure_password:-$AZURE_SQL_PASSWORD}

read -p "Database name to export (default: $AZURE_SQL_DB1): " db_name
db_name=${db_name:-$AZURE_SQL_DB1}

# Generate filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${BACKUP_DIR}/${db_name}_${TIMESTAMP}.bacpac"

log_info "Starting export of database: $db_name"
log_info "Output file: $OUTPUT_FILE"

# Check if sqlpackage is installed
if ! command -v sqlpackage &> /dev/null; then
    log_error "sqlpackage not found. Installing..."
    
    # Download and install sqlpackage
    wget -q https://aka.ms/sqlpackage-linux -O /tmp/sqlpackage.zip
    unzip -q /tmp/sqlpackage.zip -d /tmp/sqlpackage
    sudo mv /tmp/sqlpackage /opt/sqlpackage
    sudo chmod +x /opt/sqlpackage/sqlpackage
    sudo ln -sf /opt/sqlpackage/sqlpackage /usr/local/bin/sqlpackage
    rm /tmp/sqlpackage.zip
    
    log_success "sqlpackage installed successfully"
fi

# Export database
log_info "Exporting database (this may take several minutes)..."

if sqlpackage /Action:Export \
    /SourceServerName:"$azure_server" \
    /SourceDatabaseName:"$db_name" \
    /SourceUser:"$azure_user" \
    /SourcePassword:"$azure_password" \
    /SourceTrustServerCertificate:True \
    /TargetFile:"$OUTPUT_FILE" \
    /p:VerifyExtraction=True; then
    
    log_success "Export completed successfully!"
    log_info "File location: $OUTPUT_FILE"
    
    # Calculate and display file size
    file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    log_info "File size: $file_size"
    
    # Generate checksum
    checksum=$(sha256sum "$OUTPUT_FILE" | cut -d' ' -f1)
    echo "$checksum" > "${OUTPUT_FILE}.sha256"
    log_info "Checksum: $checksum"
    
else
    log_error "Export failed!"
    exit 1
fi

log_success "Export process completed!"
log_info "You can now import this file using the migration script (3-migrate-databases.sh)"
