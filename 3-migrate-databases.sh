#!/bin/bash
#
# Database Migration Script
# Migrates databases from Azure SQL to local MSSQL Express
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

# Progress bar function
show_progress() {
    local duration=$1
    local steps=50
    local step_duration=$((duration / steps))
    
    for ((i=0; i<=steps; i++)); do
        local percent=$((i * 100 / steps))
        local filled=$((i * 50 / steps))
        local empty=$((50 - filled))
        
        printf "\r["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] %d%%" "$percent"
        
        sleep 0.1
    done
    echo ""
}

echo "========================================"
echo "Database Migration from Azure SQL"
echo "========================================"

# Load configuration
if [ -f "configs/.env" ]; then
    set -a
    source configs/.env
    set +a
    log_info "Loaded configuration from configs/.env"
fi

# Create necessary directories
mkdir -p database/backups
mkdir -p database/logs

# Migration method selection
echo ""
echo "Migration Methods:"
echo "  1. Export from Azure using sqlpackage (recommended)"
echo "  2. Import existing .bacpac files"
echo "  3. Run SQL scripts manually"
echo "  4. Manual guide for Azure Portal export"
echo ""
read -p "Select migration method [1-4]: " METHOD

case $METHOD in
    1)
        log_info "Method 1: Export from Azure using sqlpackage"
        
        # Get Azure credentials
        read -p "Azure SQL Server (default: ${AZURE_SQL_SERVER}): " azure_server
        azure_server=${azure_server:-$AZURE_SQL_SERVER}
        
        read -p "Azure SQL Username (default: ${AZURE_SQL_USER}): " azure_user
        azure_user=${azure_user:-$AZURE_SQL_USER}
        
        read -sp "Azure SQL Password: " azure_password
        echo
        azure_password=${azure_password:-$AZURE_SQL_PASSWORD}
        
        # Database 1
        read -p "First database name (default: ${AZURE_SQL_DB1}): " db1_name
        db1_name=${db1_name:-$AZURE_SQL_DB1}
        
        # Database 2
        read -p "Second database name (optional, press Enter to skip): " db2_name
        
        # Export Database 1
        log_info "Exporting database: $db1_name"
        BACKUP_FILE1="database/backups/${db1_name}_$(date +%Y%m%d_%H%M%S).bacpac"
        
        if sqlpackage /Action:Export \
            /SourceServerName:"$azure_server" \
            /SourceDatabaseName:"$db1_name" \
            /SourceUser:"$azure_user" \
            /SourcePassword:"$azure_password" \
            /SourceTrustServerCertificate:True \
            /TargetFile:"$BACKUP_FILE1" \
            /p:VerifyExtraction=True 2>&1 | tee database/logs/export_${db1_name}.log; then
            
            log_success "Export completed: $BACKUP_FILE1"
            sha256sum "$BACKUP_FILE1" > "${BACKUP_FILE1}.sha256"
        else
            log_error "Export failed for $db1_name"
            exit 1
        fi
        
        # Export Database 2 if specified
        if [ -n "$db2_name" ]; then
            log_info "Exporting database: $db2_name"
            BACKUP_FILE2="database/backups/${db2_name}_$(date +%Y%m%d_%H%M%S).bacpac"
            
            if sqlpackage /Action:Export \
                /SourceServerName:"$azure_server" \
                /SourceDatabaseName:"$db2_name" \
                /SourceUser:"$azure_user" \
                /SourcePassword:"$azure_password" \
                /SourceTrustServerCertificate:True \
                /TargetFile:"$BACKUP_FILE2" \
                /p:VerifyExtraction=True 2>&1 | tee database/logs/export_${db2_name}.log; then
                
                log_success "Export completed: $BACKUP_FILE2"
                sha256sum "$BACKUP_FILE2" > "${BACKUP_FILE2}.sha256"
            else
                log_error "Export failed for $db2_name"
                exit 1
            fi
        fi
        ;;
        
    2)
        log_info "Method 2: Import existing .bacpac files"
        
        # List available bacpac files
        log_info "Available .bacpac files:"
        ls -lh database/backups/*.bacpac 2>/dev/null || log_warning "No .bacpac files found in database/backups/"
        
        read -p "Path to first .bacpac file: " BACKUP_FILE1
        if [ ! -f "$BACKUP_FILE1" ]; then
            log_error "File not found: $BACKUP_FILE1"
            exit 1
        fi
        
        read -p "Path to second .bacpac file (optional, press Enter to skip): " BACKUP_FILE2
        
        read -p "Name for first database (default: ${AZURE_SQL_DB1}): " db1_name
        db1_name=${db1_name:-$AZURE_SQL_DB1}
        
        if [ -n "$BACKUP_FILE2" ]; then
            read -p "Name for second database: " db2_name
        fi
        ;;
        
    3)
        log_info "Method 3: Run SQL scripts manually"
        log_info "Please follow these steps:"
        echo ""
        echo "1. Place your SQL script files in database/scripts/"
        echo "2. Run: sqlcmd -S localhost -U sa -P 'YOUR_PASSWORD' -d DATABASE_NAME -i script.sql -C"
        echo ""
        exit 0
        ;;
        
    4)
        log_info "Method 4: Manual guide for Azure Portal export"
        echo ""
        echo "=== Azure Portal Export Guide ==="
        echo ""
        echo "1. Go to Azure Portal (portal.azure.com)"
        echo "2. Navigate to your SQL Database"
        echo "3. Click 'Export' in the toolbar"
        echo "4. Choose a storage account or create new one"
        echo "5. Set authentication to SQL authentication"
        echo "6. Enter server admin credentials"
        echo "7. Click OK to start export"
        echo "8. Wait for export to complete (check notifications)"
        echo "9. Download the .bacpac file from storage account"
        echo "10. Copy the file to this server: database/backups/"
        echo "11. Run this script again and choose method 2"
        echo ""
        exit 0
        ;;
        
    *)
        log_error "Invalid selection"
        exit 1
        ;;
esac

# Get local MSSQL SA password
if [ -z "${MSSQL_SA_PASSWORD:-}" ]; then
    read -sp "Local MSSQL SA Password: " MSSQL_SA_PASSWORD
    echo
fi

# Import databases
log_info "Starting database import to local MSSQL..."

# Import Database 1
if [ -n "${BACKUP_FILE1:-}" ]; then
    log_info "Importing database: $db1_name"
    log_info "This may take several minutes..."
    
    # Drop database if exists
    sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF EXISTS (SELECT * FROM sys.databases WHERE name = '$db1_name') BEGIN ALTER DATABASE [$db1_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db1_name]; END" -C 2>&1 | tee -a database/logs/import_${db1_name}.log
    
    # Import using sqlpackage
    if sqlpackage /Action:Import \
        /SourceFile:"$BACKUP_FILE1" \
        /TargetServerName:"localhost" \
        /TargetDatabaseName:"$db1_name" \
        /TargetUser:"sa" \
        /TargetPassword:"$MSSQL_SA_PASSWORD" \
        /TargetTrustServerCertificate:True \
        /p:DatabaseEdition=Default \
        /p:DatabaseServiceObjective=Default 2>&1 | tee -a database/logs/import_${db1_name}.log; then
        
        log_success "Import completed: $db1_name"
    else
        log_error "Import failed for $db1_name"
        log_info "Check logs: database/logs/import_${db1_name}.log"
        exit 1
    fi
fi

# Import Database 2
if [ -n "${BACKUP_FILE2:-}" ] && [ -n "${db2_name:-}" ]; then
    log_info "Importing database: $db2_name"
    
    # Drop database if exists
    sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "IF EXISTS (SELECT * FROM sys.databases WHERE name = '$db2_name') BEGIN ALTER DATABASE [$db2_name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db2_name]; END" -C 2>&1 | tee -a database/logs/import_${db2_name}.log
    
    # Import using sqlpackage
    if sqlpackage /Action:Import \
        /SourceFile:"$BACKUP_FILE2" \
        /TargetServerName:"localhost" \
        /TargetDatabaseName:"$db2_name" \
        /TargetUser:"sa" \
        /TargetPassword:"$MSSQL_SA_PASSWORD" \
        /TargetTrustServerCertificate:True \
        /p:DatabaseEdition=Default \
        /p:DatabaseServiceObjective=Default 2>&1 | tee -a database/logs/import_${db2_name}.log; then
        
        log_success "Import completed: $db2_name"
    else
        log_error "Import failed for $db2_name"
        log_info "Check logs: database/logs/import_${db2_name}.log"
        exit 1
    fi
fi

# Validate migration
log_info "Validating migration..."

for db in "$db1_name" ${db2_name:-}; do
    if [ -n "$db" ]; then
        log_info "Validating database: $db"
        
        # Get table count
        TABLE_COUNT=$(sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$db" -Q "SELECT COUNT(*) FROM sys.tables" -h -1 -C 2>/dev/null | tr -d ' ')
        
        # Get total rows
        sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$db" -i database/validate-migration.sql -C > "database/logs/validation_${db}.log" 2>&1
        
        log_success "Database $db validated: $TABLE_COUNT tables"
        log_info "Detailed validation report: database/logs/validation_${db}.log"
    fi
done

# Create database users for APIs
log_info "Creating database users for APIs..."

# User for API 1
API1_USER="${API1_DB_USER:-api1_user}"
API1_PASS="${API1_DB_PASSWORD:-Api1Password123!}"

sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$db1_name" -Q "
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$API1_USER')
BEGIN
    CREATE USER [$API1_USER] WITH PASSWORD = '$API1_PASS';
    ALTER ROLE db_datareader ADD MEMBER [$API1_USER];
    ALTER ROLE db_datawriter ADD MEMBER [$API1_USER];
    ALTER ROLE db_ddladmin ADD MEMBER [$API1_USER];
END
" -C

log_success "Created user: $API1_USER"

# User for API 2
if [ -n "${db2_name:-}" ]; then
    API2_USER="${API2_DB_USER:-api2_user}"
    API2_PASS="${API2_DB_PASSWORD:-Api2Password123!}"
    
    sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d "$db2_name" -Q "
    IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$API2_USER')
    BEGIN
        CREATE USER [$API2_USER] WITH PASSWORD = '$API2_PASS';
        ALTER ROLE db_datareader ADD MEMBER [$API2_USER];
        ALTER ROLE db_datawriter ADD MEMBER [$API2_USER];
        ALTER ROLE db_ddladmin ADD MEMBER [$API2_USER];
    END
    " -C
    
    log_success "Created user: $API2_USER"
fi

# Generate migration report
REPORT_FILE="database/logs/migration_report_$(date +%Y%m%d_%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
======================================
Database Migration Report
======================================
Date: $(date)
Method: $METHOD

Databases Migrated:
$([ -n "$db1_name" ] && echo "  - $db1_name")
$([ -n "${db2_name:-}" ] && echo "  - $db2_name")

Database Users Created:
  - $API1_USER (for $db1_name)
$([ -n "${db2_name:-}" ] && echo "  - $API2_USER (for $db2_name)")

Backup Files:
$([ -n "${BACKUP_FILE1:-}" ] && echo "  - $BACKUP_FILE1")
$([ -n "${BACKUP_FILE2:-}" ] && echo "  - $BACKUP_FILE2")

Validation Logs:
  - database/logs/validation_${db1_name}.log
$([ -n "${db2_name:-}" ] && echo "  - database/logs/validation_${db2_name}.log")

======================================
EOF

log_success "Migration report saved: $REPORT_FILE"

# Summary
echo ""
echo "========================================"
echo "Database Migration Complete!"
echo "========================================"
echo ""
echo "Migrated Databases:"
[ -n "$db1_name" ] && echo "  ✓ $db1_name"
[ -n "${db2_name:-}" ] && echo "  ✓ $db2_name"
echo ""
echo "Next Steps:"
echo "  1. Review validation reports in database/logs/"
echo "  2. Update connection strings in your application configs"
echo "  3. Run ./4-deploy-api1.sh and ./5-deploy-api2.sh to deploy APIs"
echo ""
log_success "Migration completed successfully!"
