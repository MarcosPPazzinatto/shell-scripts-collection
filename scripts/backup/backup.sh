#!/usr/bin/env bash
# backup.sh
# Simple backup script to compress and store a directory
# Usage: ./backup.sh /path/to/source /path/to/backup

set -euo pipefail

SOURCE_DIR=${1:-}
BACKUP_DIR=${2:-}

if [[ -z "$SOURCE_DIR" || -z "$BACKUP_DIR" ]]; then
  echo "Usage: $0 /path/to/source /path/to/backup"
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: Source directory does not exist."
  exit 1
fi

# Create backup directory if it does not exist
mkdir -p "$BACKUP_DIR"

# Create filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

# Create compressed archive
tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

echo "Backup completed successfully: $BACKUP_FILE"

