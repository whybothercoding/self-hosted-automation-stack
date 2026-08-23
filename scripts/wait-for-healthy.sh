#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# wait-for-healthy.sh — Poll each service directly until it responds.
#
# Deliberately does NOT rely on `docker compose up --wait` or `docker
# inspect .State.Health.Status`: both depend on Docker's own HEALTHCHECK
# state machine, which was observed getting stuck reporting "unhealthy" for
# Baserow even while it was actually up, under GitHub Actions runner
# resource contention during first-boot migrations.
#
# Also deliberately does NOT `docker compose exec` into n8n/Baserow to run
# their own healthcheck command: baserow/baserow:2.3.3 has no `wget` binary
# anywhere in $PATH at all (confirmed at the OCI runtime level, not a shell
# quirk) — docker-compose.yml's own `wget`-based HEALTHCHECK for that
# service has never actually been able to run. Instead this curls each
# HTTP service directly on its host-mapped port from the caller's machine.
#
# PRECONDITION: the caller must already have the dev compose override
# active (host ports 5678/8080 mapped) — e.g. via `-f docker-compose.dev.yml`
# or `COMPOSE_FILE` including it. Both current call sites (validate.yml's
# smoke-test, backup-drill.yml) already do this.
#
# Usage: ./scripts/wait-for-healthy.sh <service> [<service> ...]
# Known services: postgres, n8n, baserow
# Env:   WAIT_ATTEMPTS (default 40), WAIT_INTERVAL_SECS (default 10)
# -------------------------------------------------------

ATTEMPTS="${WAIT_ATTEMPTS:-40}"
INTERVAL="${WAIT_INTERVAL_SECS:-10}"

run_check() {
  case "$1" in
    postgres) docker compose exec -T postgres sh -c 'pg_isready -U "$POSTGRES_USER"' ;;
    n8n)      curl -sf http://localhost:5678/healthz ;;
    baserow)  curl -sf http://localhost:8080/api/_health/ ;;
    *)
      echo "Unknown service: $1 (known: postgres, n8n, baserow)" >&2
      return 2
      ;;
  esac
}

for service in "$@"; do
  echo "Waiting for $service (up to $((ATTEMPTS * INTERVAL))s)..."
  ok=""
  for i in $(seq 1 "$ATTEMPTS"); do
    # if/else around the assignment (not `out=$(...) ; rc=$?`) so a nonzero
    # exit doesn't trip `set -e` on the assignment itself.
    if out=$(run_check "$service" 2>&1); then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
      echo "  $service is responding"
      ok="yes"
      break
    fi
    echo "  [$i/$ATTEMPTS] $service not ready (exit $rc): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
    sleep "$INTERVAL"
  done
  if [ -z "$ok" ]; then
    echo "ERROR: $service did not respond within $((ATTEMPTS * INTERVAL))s"
    docker compose logs "$service" --tail=100
    exit 1
  fi
done

echo "All services responding: $*"
