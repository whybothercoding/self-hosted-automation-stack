#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# wait-for-healthy.sh — Poll a service's own healthcheck command via
# `docker compose exec` until it succeeds.
#
# Deliberately does NOT rely on `docker compose up --wait` or `docker
# inspect .State.Health.Status`: both depend on Docker's own HEALTHCHECK
# state machine, which was observed getting stuck reporting "unhealthy" for
# Baserow even while its /api/_health/ endpoint was returning 200 on every
# single check for minutes straight, under GitHub Actions runner resource
# contention during first-boot migrations. Running the exact same check
# command directly and retrying until IT succeeds sidesteps Docker's health
# bookkeeping entirely — what matters is "does the service respond right
# now", not "what does Docker's internal state say".
#
# Usage: ./scripts/wait-for-healthy.sh <service> [<service> ...]
# Known services: postgres, n8n, baserow
# Env:   WAIT_ATTEMPTS (default 40), WAIT_INTERVAL_SECS (default 10)
# -------------------------------------------------------

ATTEMPTS="${WAIT_ATTEMPTS:-40}"
INTERVAL="${WAIT_INTERVAL_SECS:-10}"

check_cmd() {
  case "$1" in
    postgres) echo 'pg_isready -U "$POSTGRES_USER"' ;;
    n8n)      echo 'wget -qO- http://localhost:5678/healthz' ;;
    baserow)  echo 'wget -qO- http://localhost/api/_health/' ;;
    *)
      echo "Unknown service: $1 (known: postgres, n8n, baserow)" >&2
      exit 1
      ;;
  esac
}

for service in "$@"; do
  cmd=$(check_cmd "$service")
  echo "Waiting for $service (up to $((ATTEMPTS * INTERVAL))s)..."
  ok=""
  for i in $(seq 1 "$ATTEMPTS"); do
    # if/else around the assignment (not `out=$(...) ; rc=$?`) so a nonzero
    # exit from the exec doesn't trip `set -e` on the assignment itself.
    if out=$(docker compose exec -T "$service" sh -c "$cmd" 2>&1); then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
      echo "  $service is responding"
      ok="yes"
      break
    fi
    # Print what actually failed — swallowing this is exactly what turned
    # earlier failures into multiple rounds of guessing instead of one.
    echo "  [$i/$ATTEMPTS] $service not ready (exec exit $rc): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
    sleep "$INTERVAL"
  done
  if [ -z "$ok" ]; then
    echo "ERROR: $service did not respond within $((ATTEMPTS * INTERVAL))s"
    docker compose logs "$service" --tail=100
    exit 1
  fi
done

echo "All services responding: $*"
