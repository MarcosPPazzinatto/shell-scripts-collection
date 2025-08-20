#!/usr/bin/env bash
# log_rotate.sh
# Script to rotate and compress old log files

set -euo pipefail

# Default log directory
LOG_DIR="/var/log"
# Number of days to keep logs
DAYS_TO_KEEP=7

echo "Rotating logs in $LOG_DIR ..."
echo "Keeping logs modified in the last $DAYS_TO_KEEP days."

# Find and compress old logs
find "$LOG_DIR" -type f -name "*.log" -mtime +"$DAYS_TO_KEEP" -print -exec gzip {} \;

# Remove very old compressed logs (older than 30 days)
find "$LOG_DIR" -type f -name "*.log.gz" -mtime +30 -print -delete

echo "Log rotation completed."

