#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# update.sh — Pull latest images and redeploy the stack
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Pulling latest images..."
docker compose pull

echo ""
echo "Redeploying services..."
docker compose up -d --remove-orphans

echo ""
echo "Removing unused images..."
docker image prune -f

echo ""
echo "Update complete. Running services:"
docker compose ps
