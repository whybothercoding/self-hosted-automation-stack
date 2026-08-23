#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# backup-drill.sh — Prove the backup/restore cycle actually recovers data
#
# Usage: ./scripts/backup-drill.sh
#
# Precondition: the stack must already be up and healthy
# (`docker compose up -d --wait`) and `.env` must exist.
#
# Writes a marker row into Postgres, backs up, destroys the volumes, restores
# from the tarball just taken, and fails if the marker row isn't back. Used
# by both `make backup-test` (local) and the scheduled Backup Drill workflow
# (CI) — the drill logic lives here once so the two don't drift apart.
#
# Respects COMPOSE_FILE like any other `docker compose` invocation — export
# it (e.g. to include the dev override) before running this script.
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run this against a configured stack."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

MARKER="backup-drill-$(date +%s)-$$"

echo "Writing marker row: $MARKER"
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "CREATE TABLE IF NOT EXISTS backup_drill (marker text); INSERT INTO backup_drill VALUES ('${MARKER}');"

echo "Running backup..."
bash "$SCRIPT_DIR/backup.sh"

echo "Destroying the stack and its volumes (this is the point of the drill)..."
docker compose down -v

TIMESTAMP=$(find "$PROJECT_DIR/backups" -name "*_postgres_data_*.tar.gz" | sed -E 's/.*_([0-9]{8}_[0-9]{6})\.tar\.gz/\1/' | sort | tail -1)
if [ -z "$TIMESTAMP" ]; then
  echo "ERROR: no backup archive found after running backup.sh"
  exit 1
fi

echo "Restoring from backup timestamped: $TIMESTAMP"
bash "$SCRIPT_DIR/restore.sh" "$TIMESTAMP" --force

echo "Waiting for the restored stack to become healthy..."
bash "$SCRIPT_DIR/wait-for-healthy.sh" postgres n8n baserow

RESULT=$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
  "SELECT 1 FROM backup_drill WHERE marker = '${MARKER}';" | tr -d '[:space:]')

if [ "$RESULT" != "1" ]; then
  echo "FAIL: marker row '${MARKER}' did not survive the backup/restore cycle."
  exit 1
fi

echo "PASS: marker row confirmed present after restore. Backup/restore cycle verified."
