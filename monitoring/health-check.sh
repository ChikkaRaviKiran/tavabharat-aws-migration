#!/bin/bash
#
# Health Check Script for TavaBharat Infrastructure
# Monitors all critical services and sends alerts if issues are found
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/var/log/tavabharat-health.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"
FAILED_CHECKS=0

# Logging function
log_check() {
    local status=$1
    local service=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}[✓]${NC} $service: $message"
        echo "[$timestamp] [OK] $service: $message" >> "$LOG_FILE"
    elif [ "$status" == "WARNING" ]; then
        echo -e "${YELLOW}[!]${NC} $service: $message"
        echo "[$timestamp] [WARNING] $service: $message" >> "$LOG_FILE"
    else
        echo -e "${RED}[✗]${NC} $service: $message"
        echo "[$timestamp] [ERROR] $service: $message" >> "$LOG_FILE"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

echo "========================================"
echo "TavaBharat Health Check - $(date)"
echo "========================================"

# 1. Check MSSQL Server
echo -e "\n${BLUE}Checking MSSQL Server...${NC}"
if systemctl is-active --quiet mssql-server; then
    log_check "OK" "MSSQL" "Service is running"
    
    # Check if we can connect
    if command -v sqlcmd &> /dev/null; then
        if timeout 5 sqlcmd -S localhost -Q "SELECT @@VERSION" -C &> /dev/null; then
            log_check "OK" "MSSQL" "Database connection successful"
        else
            log_check "ERROR" "MSSQL" "Cannot connect to database"
        fi
    fi
else
    log_check "ERROR" "MSSQL" "Service is not running"
fi

# 2. Check API 1
echo -e "\n${BLUE}Checking API 1...${NC}"
if systemctl is-active --quiet api1; then
    log_check "OK" "API1" "Service is running"
    
    # Check health endpoint
    if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/v1/health 2>/dev/null | grep -q "200\|404"; then
        log_check "OK" "API1" "HTTP endpoint responding"
    else
        log_check "WARNING" "API1" "HTTP endpoint not responding or returns error"
    fi
else
    log_check "ERROR" "API1" "Service is not running"
fi

# 3. Check API 2
echo -e "\n${BLUE}Checking API 2...${NC}"
if systemctl is-active --quiet api2; then
    log_check "OK" "API2" "Service is running"
    
    # Check health endpoint
    if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:5001/api/v2/health 2>/dev/null | grep -q "200\|404"; then
        log_check "OK" "API2" "HTTP endpoint responding"
    else
        log_check "WARNING" "API2" "HTTP endpoint not responding or returns error"
    fi
else
    log_check "ERROR" "API2" "Service is not running"
fi

# 4. Check Nginx
echo -e "\n${BLUE}Checking Nginx...${NC}"
if systemctl is-active --quiet nginx; then
    log_check "OK" "Nginx" "Service is running"
    
    # Check if nginx is listening on port 80
    if ss -tuln | grep -q ":80 "; then
        log_check "OK" "Nginx" "Listening on port 80"
    else
        log_check "ERROR" "Nginx" "Not listening on port 80"
    fi
else
    log_check "ERROR" "Nginx" "Service is not running"
fi

# 5. Check Disk Space
echo -e "\n${BLUE}Checking Disk Space...${NC}"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    log_check "OK" "Disk" "Usage: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -lt 90 ]; then
    log_check "WARNING" "Disk" "Usage: ${DISK_USAGE}% (running low)"
else
    log_check "ERROR" "Disk" "Usage: ${DISK_USAGE}% (critically low)"
fi

# 6. Check Memory Usage
echo -e "\n${BLUE}Checking Memory Usage...${NC}"
MEMORY_USAGE=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$MEMORY_USAGE" -lt 80 ]; then
    log_check "OK" "Memory" "Usage: ${MEMORY_USAGE}%"
elif [ "$MEMORY_USAGE" -lt 90 ]; then
    log_check "WARNING" "Memory" "Usage: ${MEMORY_USAGE}% (high)"
else
    log_check "ERROR" "Memory" "Usage: ${MEMORY_USAGE}% (critically high)"
fi

# 7. Check CPU Load
echo -e "\n${BLUE}Checking CPU Load...${NC}"
CPU_CORES=$(nproc)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
LOAD_NORMALIZED=$(echo "$LOAD_AVG / $CPU_CORES" | bc -l | awk '{printf "%.2f", $1}')

if (( $(echo "$LOAD_NORMALIZED < 0.8" | bc -l) )); then
    log_check "OK" "CPU" "Load: $LOAD_AVG (normalized: $LOAD_NORMALIZED)"
elif (( $(echo "$LOAD_NORMALIZED < 1.5" | bc -l) )); then
    log_check "WARNING" "CPU" "Load: $LOAD_AVG (normalized: $LOAD_NORMALIZED, high)"
else
    log_check "ERROR" "CPU" "Load: $LOAD_AVG (normalized: $LOAD_NORMALIZED, very high)"
fi

# Summary
echo ""
echo "========================================"
if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}All health checks passed!${NC}"
else
    echo -e "${RED}$FAILED_CHECKS health check(s) failed!${NC}"
fi
echo "========================================"

# Send alert email if configured and there are failures
if [ $FAILED_CHECKS -gt 0 ] && [ -n "$ALERT_EMAIL" ]; then
    if command -v mail &> /dev/null; then
        echo "Health check failures detected on $(hostname) at $(date)" | \
            mail -s "TavaBharat Health Check Alert" "$ALERT_EMAIL"
    fi
fi

exit $FAILED_CHECKS
