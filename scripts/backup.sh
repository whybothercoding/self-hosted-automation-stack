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

# Detect the compose project name (derived from directory name by Docker Compose)
COMPOSE_PROJECT=$(docker compose config 2>/dev/null | grep -m1 '^name:' | awk '{print $2}')
if [ -z "$COMPOSE_PROJECT" ]; then
  echo "ERROR: Could not determine compose project name."
  echo "Make sure .env exists and docker compose config runs without errors."
  exit 1
fi

echo "[$TIMESTAMP] Starting backup (project: $COMPOSE_PROJECT)..."

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

backup_volume "${COMPOSE_PROJECT}_n8n_data"
backup_volume "${COMPOSE_PROJECT}_baserow_data"
backup_volume "${COMPOSE_PROJECT}_postgres_data"

echo "Restarting containers..."
docker compose start

echo ""
echo "Backup complete. Files saved to: $BACKUP_DIR"
find "$BACKUP_DIR" -name "*${TIMESTAMP}*" -exec ls -lh {} \;
