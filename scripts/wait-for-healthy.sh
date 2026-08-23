#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# wait-for-healthy.sh — Poll docker compose services until Docker reports
# them healthy.
#
# Deliberately NOT `docker compose up --wait`: that command fails
# permanently on the first "unhealthy" transition, even if the container
# recovers a few seconds later. Observed happening to Baserow in CI —
# its first-boot migration + template sync left it briefly unhealthy under
# runner resource contention, then it started responding 200 on every
# subsequent check, but `--wait` had already given up. This script tolerates
# that and only fails on a genuine timeout with nothing ever reporting
# healthy.
#
# Usage: ./scripts/wait-for-healthy.sh <service> [<service> ...]
# Env:   WAIT_ATTEMPTS (default 20), WAIT_INTERVAL_SECS (default 20)
# -------------------------------------------------------

ATTEMPTS="${WAIT_ATTEMPTS:-20}"
INTERVAL="${WAIT_INTERVAL_SECS:-20}"

for service in "$@"; do
  echo "Waiting for $service to become healthy (up to $((ATTEMPTS * INTERVAL))s)..."
  healthy=""
  for i in $(seq 1 "$ATTEMPTS"); do
    cid=$(docker compose ps -q "$service")
    status="no container"
    if [ -n "$cid" ]; then
      status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "none")
    fi
    if [ "$status" = "healthy" ]; then
      echo "  $service is healthy"
      healthy="yes"
      break
    fi
    echo "  [$i/$ATTEMPTS] $service: $status"
    sleep "$INTERVAL"
  done
  if [ -z "$healthy" ]; then
    echo "ERROR: $service did not become healthy within $((ATTEMPTS * INTERVAL))s"
    docker compose logs "$service" --tail=100
    exit 1
  fi
done

echo "All services healthy: $*"
