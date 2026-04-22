#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# backup.sh — Backup all Docker volumes to tar.gz files
#
# Usage: ./scripts/backup.sh
#
# To automate, add to crontab:
#   0 2 * * * /path/to/self-hosted-automation-stack/scripts/backup.sh >> /var/log/stack-backup.log 2>&1
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

cd "$PROJECT_DIR"

echo "[$TIMESTAMP] Starting backup..."

echo "Stopping containers gracefully..."
docker compose stop

backup_volume() {
  local VOLUME_NAME="$1"
  local ARCHIVE="$BACKUP_DIR/${VOLUME_NAME}_${TIMESTAMP}.tar.gz"
  echo "Backing up volume: $VOLUME_NAME → $ARCHIVE"
  docker run --rm \
    -v "${VOLUME_NAME}:/data:ro" \
    -v "$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/$(basename "$ARCHIVE")" -C /data .
}

backup_volume "self-hosted-automation-stack_n8n_data"
backup_volume "self-hosted-automation-stack_baserow_data"
backup_volume "self-hosted-automation-stack_postgres_data"

echo "Restarting containers..."
docker compose start

echo ""
echo "Backup complete. Files saved to: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | grep "$TIMESTAMP"
