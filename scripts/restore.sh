#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# restore.sh — Restore all Docker volumes from a backup.sh snapshot
#
# Usage: ./scripts/restore.sh <timestamp> [--force]
#   <timestamp>  Matches the suffix on files in ./backups/, e.g. 20260823_140000
#   --force      Skip the confirmation prompt (used by the automated backup drill)
#
# WARNING: this replaces the current contents of n8n_data, baserow_data,
# and postgres_data. There is no undo once the existing volumes are removed.
#
# Respects the standard COMPOSE_FILE env var, same as any `docker compose`
# invocation — set it if you need to restore against a non-default compose
# file combination (e.g. the dev override).
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

TIMESTAMP="${1:-}"
FORCE_FLAG="${2:-}"

if [ -z "$TIMESTAMP" ]; then
  echo "Usage: $0 <timestamp> [--force]"
  echo ""
  echo "Available backup timestamps:"
  find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | sed -E 's/.*_([0-9]{8}_[0-9]{6})\.tar\.gz/\1/' | sort -u
  exit 1
fi

cd "$PROJECT_DIR"

COMPOSE_PROJECT=$(docker compose config 2>/dev/null | grep -m1 '^name:' | awk '{print $2}')
if [ -z "$COMPOSE_PROJECT" ]; then
  echo "ERROR: Could not determine compose project name."
  echo "Make sure .env exists and docker compose config runs without errors."
  exit 1
fi

VOLUMES=("n8n_data" "baserow_data" "postgres_data")

for VOL in "${VOLUMES[@]}"; do
  ARCHIVE="$BACKUP_DIR/${COMPOSE_PROJECT}_${VOL}_${TIMESTAMP}.tar.gz"
  if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: Backup file not found: $ARCHIVE"
    exit 1
  fi
done

if [ "$FORCE_FLAG" != "--force" ]; then
  echo "This will STOP the stack and REPLACE the current contents of:"
  for VOL in "${VOLUMES[@]}"; do
    echo "  - ${COMPOSE_PROJECT}_${VOL}"
  done
  echo "with the backup timestamped ${TIMESTAMP}. This cannot be undone."
  read -rp "Type 'restore' to continue: " CONFIRM
  if [ "$CONFIRM" != "restore" ]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Stopping stack..."
docker compose down

restore_volume() {
  local VOL="$1"
  local VOLUME_NAME="${COMPOSE_PROJECT}_${VOL}"
  local ARCHIVE="$BACKUP_DIR/${VOLUME_NAME}_${TIMESTAMP}.tar.gz"

  echo "Restoring volume: $VOLUME_NAME <- $ARCHIVE"
  docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
  docker volume create "$VOLUME_NAME" >/dev/null
  docker run --rm \
    -v "${VOLUME_NAME}:/data" \
    -v "$BACKUP_DIR:/backup:ro" \
    alpine \
    tar xzf "/backup/$(basename "$ARCHIVE")" -C /data
}

for VOL in "${VOLUMES[@]}"; do
  restore_volume "$VOL"
done

echo "Starting stack..."
docker compose up -d

echo ""
echo "Restore complete from backup timestamped: ${TIMESTAMP}"
