#!/bin/bash
#
# Resource Monitoring Script
# Tracks CPU, RAM, and Disk usage
#

set -euo pipefail

# Configuration
LOG_FILE="/var/log/tavabharat-resources.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=80

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Get CPU usage (1 minute average)
CPU_CORES=$(nproc)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_USAGE=$(echo "scale=2; ($LOAD_AVG / $CPU_CORES) * 100" | bc)

# Get memory usage
MEMORY_TOTAL=$(free -m | grep Mem | awk '{print $2}')
MEMORY_USED=$(free -m | grep Mem | awk '{print $3}')
MEMORY_USAGE=$(echo "scale=2; ($MEMORY_USED / $MEMORY_TOTAL) * 100" | bc)

# Get disk usage
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

# Get swap usage
SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_USAGE=$(echo "scale=2; ($SWAP_USED / $SWAP_TOTAL) * 100" | bc)
else
    SWAP_USAGE=0
fi

# Log resources
echo "[$TIMESTAMP] CPU: ${CPU_USAGE}% | Memory: ${MEMORY_USAGE}% (${MEMORY_USED}MB/${MEMORY_TOTAL}MB) | Disk: ${DISK_USAGE}% | Swap: ${SWAP_USAGE}% (${SWAP_USED}MB/${SWAP_TOTAL}MB)" >> "$LOG_FILE"

# Check thresholds and alert
ALERT_NEEDED=false
ALERT_MESSAGE=""

if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
    ALERT_NEEDED=true
    ALERT_MESSAGE="${ALERT_MESSAGE}CPU usage is high: ${CPU_USAGE}%\n"
fi

if (( $(echo "$MEMORY_USAGE > $MEMORY_THRESHOLD" | bc -l) )); then
    ALERT_NEEDED=true
    ALERT_MESSAGE="${ALERT_MESSAGE}Memory usage is high: ${MEMORY_USAGE}%\n"
fi

if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    ALERT_NEEDED=true
    ALERT_MESSAGE="${ALERT_MESSAGE}Disk usage is high: ${DISK_USAGE}%\n"
fi

# Send alert if needed
if [ "$ALERT_NEEDED" = true ] && [ -n "$ALERT_EMAIL" ]; then
    if command -v mail &> /dev/null; then
        echo -e "Resource usage alert on $(hostname) at $TIMESTAMP:\n\n$ALERT_MESSAGE" | \
            mail -s "TavaBharat Resource Alert" "$ALERT_EMAIL"
    fi
fi

# Display current status (optional, for manual runs)
if [ -t 1 ]; then
    echo "[$TIMESTAMP] Resource Usage:"
    echo "  CPU: ${CPU_USAGE}%"
    echo "  Memory: ${MEMORY_USAGE}% (${MEMORY_USED}MB / ${MEMORY_TOTAL}MB)"
    echo "  Disk: ${DISK_USAGE}%"
    echo "  Swap: ${SWAP_USAGE}% (${SWAP_USED}MB / ${SWAP_TOTAL}MB)"
fi
