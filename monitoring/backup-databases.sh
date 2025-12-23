#!/bin/bash
#
# Database Backup Script
# Automatically backs up all databases and manages retention
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="/var/backups/mssql"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/tavabharat-backup.log"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

# Create backup directory
sudo mkdir -p "$BACKUP_DIR"
sudo chown ubuntu:ubuntu "$BACKUP_DIR"

log_info "Starting database backup..."

# Load SA password from environment
if [ -f "/home/ubuntu/configs/.env" ]; then
    set -a
    source /home/ubuntu/configs/.env
    set +a
fi

SA_PASSWORD="${MSSQL_SA_PASSWORD:-}"

if [ -z "$SA_PASSWORD" ]; then
    log_error "MSSQL SA password not set. Please set MSSQL_SA_PASSWORD environment variable."
    exit 1
fi

# Get list of databases (excluding system databases)
DATABASES=$(sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -h -1 -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') AND state = 0;" -C 2>/dev/null | grep -v '^$' | tr -d ' ')

if [ -z "$DATABASES" ]; then
    log_error "No user databases found to backup"
    exit 1
fi

BACKUP_COUNT=0
FAILED_COUNT=0

# Backup each database
for DB in $DATABASES; do
    log_info "Backing up database: $DB"
    
    BACKUP_FILE="${BACKUP_DIR}/${DB}_${TIMESTAMP}.bak"
    
    # Create backup using sqlcmd
    if sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "BACKUP DATABASE [$DB] TO DISK = N'$BACKUP_FILE' WITH FORMAT, COMPRESSION;" -C 2>&1 | tee -a "$LOG_FILE"; then
        
        # Get backup file size
        if [ -f "$BACKUP_FILE" ]; then
            FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log_success "Backup completed: $BACKUP_FILE ($FILE_SIZE)"
            BACKUP_COUNT=$((BACKUP_COUNT + 1))
            
            # Create checksum
            sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
        else
            log_error "Backup file not created: $BACKUP_FILE"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        log_error "Failed to backup database: $DB"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Clean up old backups
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "*.bak" -type f -mtime +$RETENTION_DAYS | wc -l)

if [ $DELETED_COUNT -gt 0 ]; then
    find "$BACKUP_DIR" -name "*.bak" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "*.sha256" -type f -mtime +$RETENTION_DAYS -delete
    log_info "Deleted $DELETED_COUNT old backup(s)"
fi

# Summary
echo ""
log_info "========================================"
log_info "Backup Summary:"
log_info "  Databases backed up: $BACKUP_COUNT"
log_info "  Failed backups: $FAILED_COUNT"
log_info "  Old backups deleted: $DELETED_COUNT"
log_info "  Backup location: $BACKUP_DIR"
log_info "========================================"

if [ $FAILED_COUNT -eq 0 ]; then
    log_success "All backups completed successfully!"
    exit 0
else
    log_error "Some backups failed!"
    exit 1
fi
