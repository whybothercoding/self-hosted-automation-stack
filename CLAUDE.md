# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Docker Compose stack that runs **n8n + Baserow + PostgreSQL + Caddy** on a single VPS. Caddy handles reverse proxy and automatic Let's Encrypt TLS. Services are split across two internal networks: `proxy-network` (Caddy + n8n + Baserow) and `backend-network` (n8n + Baserow + PostgreSQL). Only Caddy exposes ports 80/443 to the outside; PostgreSQL is unreachable from the proxy layer.

## Commands

Prefer `make <target>` — it wraps all common operations:

```bash
make setup    # first-run interactive setup (writes .env, pulls images, starts stack)
make up       # docker compose up -d
make down     # docker compose down
make dev      # dev mode: direct ports (n8n :5678, Baserow :8080), no Caddy
make logs     # docker compose logs -f
make backup   # stops stack → snapshots volumes → restarts
make update   # pulls latest images, redeploys, prunes old images
make restart  # docker compose restart
make test     # boots the dev stack and curls both health endpoints (real smoke test)
make restore  # restores a backup: make restore TIMESTAMP=20260823_140000
make backup-test    # full backup → destroy volumes → restore → verify drill (needs a running stack)
make security-scan  # scans the four pinned images with the local Trivy CLI
```

Raw equivalents when needed:

```bash
docker compose ps
docker compose logs <service> --follow   # services: n8n, baserow, postgres, caddy
docker compose stop / start
```

## Architecture

```
Internet → Caddy (80/443) ──proxy-network──► n8n (5678)
                                         └──► Baserow (80)
                                                │      │
                                         backend-network
                                                │      │
                                                ▼      ▼
                                            PostgreSQL (5432)
```

- **`docker-compose.yml`** — production definition; Caddy is the only public-facing service
- **`docker-compose.dev.yml`** — override that ports n8n and Baserow directly and puts Caddy behind a `production` profile (so it doesn't start)
- **`Caddyfile`** — reads domain/subdomain from env vars at runtime via `{$VAR}` syntax; security headers include HSTS (`max-age=31536000; includeSubDomains`), X-Frame-Options, X-Content-Type-Options, Referrer-Policy; gzip on both virtual hosts
- **`.github/workflows/validate.yml`** — CI runs on every push to main and every PR: validates both compose files, shellchecks all scripts in `scripts/`, then actually boots the dev stack (`--wait`) and curls both health endpoints externally — this is real runtime verification, not just YAML syntax checking
- **`.github/workflows/security.yml`** — weekly + on-push Trivy CVE scan of the four pinned images (not the compose file — Trivy has no native docker-compose misconfig scanner), results land in the repo's Security tab. Non-blocking (`continue-on-error`).
- **`.github/workflows/backup-drill.yml`** — weekly + on-demand: writes a marker row, backs up, destroys the volumes, restores, and fails if the marker isn't back. Proves the restore path works instead of just documenting it. Logic lives in `scripts/backup-drill.sh` (also runnable locally via `make backup-test`), shared between CI and local use so they can't drift apart.
- **`.github/dependabot.yml`** — tracks the pinned image tags in `docker-compose.yml` (`docker` ecosystem) and third-party Action versions (`github-actions` ecosystem) weekly.
- **Third-party GitHub Actions are pinned by commit SHA, not by tag**, in every workflow file — `aquasecurity/trivy-action` had 75 of 76 version tags force-pushed with malware in March 2026 (tags are mutable; SHAs aren't). Apply the same pattern to any new third-party Action added to this repo; re-resolve the current SHA at the time you add it, don't copy an old one.
- **`scripts/restore.sh`** — restores all three volumes from a `backup.sh` snapshot; respects `COMPOSE_FILE` like any other `docker compose` call, so it works against the dev override too (see `backup-drill.yml` for how CI sets that).
- **Container hardening in `docker-compose.yml`** — every service has `no-new-privileges`; Caddy/n8n/Postgres have `cap_drop: [ALL]` plus only the specific caps each needs. **Baserow is deliberately not capability-dropped** — its all-in-one process supervisor's root requirements weren't confirmed safe to guess at from outside a live container. Don't attempt to add `cap_drop` to Baserow without verifying against a real running container first (see `docs/troubleshooting.md` § Container Won't Start After a Capability Change for the diagnostic approach).
- **`docs/adr/`** — architecture decision records for the reverse-proxy choice, the shared-Postgres decision, and the two-network topology. Add a new one when a similarly consequential architectural choice gets made, don't retrofit one for routine changes.

## Validation

Before committing changes to compose files or scripts, run these locally (mirrors the CI checks):

```bash
# Validate compose syntax (requires .env to exist)
cp .env.example .env
docker compose config --quiet
docker compose -f docker-compose.yml -f docker-compose.dev.yml config --quiet
rm .env

# Lint shell scripts
shellcheck --severity=error scripts/setup.sh scripts/backup.sh scripts/update.sh scripts/restore.sh scripts/backup-drill.sh
```

To actually verify the stack boots (not just that the YAML is valid), run `make test` — needs a local Docker daemon. If one isn't available in your environment, push to a branch and let the `validate.yml` smoke-test job do it; don't claim runtime behavior is verified without one or the other actually running.

## Critical Constraints

- `N8N_ENCRYPTION_KEY` — generated once by `setup.sh` via `openssl rand -hex 32`. **Never change it after first run**; doing so breaks all stored n8n credentials.
- `BASEROW_SECRET_KEY` — Django secret key; same rule applies.
- Both databases (`N8N_DB_NAME`, `BASEROW_DB_NAME`) are created automatically by each app on first run inside the shared Postgres container. The `POSTGRES_DB` var is just the default DB created at container init and isn't used by n8n or Baserow directly.
- Volume names in `backup.sh` are detected dynamically via `docker compose config` — no hardcoded prefix. The script requires `.env` to exist so compose config can resolve variable substitutions.
- `backup.sh` backs up `n8n_data`, `baserow_data`, and `postgres_data` only. `caddy_data` and `caddy_config` are intentionally excluded — certificates are re-issuable from Let's Encrypt for free.
- n8n and Baserow start only after Postgres passes its healthcheck (`pg_isready`). If either service fails to start, confirm Postgres is `(healthy)` first: `docker compose ps postgres`.
- `setup.sh` uses a `sed_inplace()` helper (macOS vs Linux `sed -i` differences). Any additions to that script that write to `.env` must use the same helper.
- All four images are version-pinned (no `:latest`). Bump via the Dependabot PR, not by hand, unless you have a specific reason to jump ahead of it — and review the linked changelog before merging either way.
- `.env.example` ships with `N8N_ENCRYPTION_KEY` and `BASEROW_SECRET_KEY` blank by design (real users generate them via `setup.sh`). Anything that boots the stack directly from `.env.example` (CI, a quick local test) must generate real values first — Baserow's Django backend won't start with an empty `SECRET_KEY`. See the "Prepare .env" step in `validate.yml`'s smoke-test job for the pattern.

## Docs

- `docs/initial-setup.md` — full fresh-VPS walkthrough
- `docs/ssl-configuration.md` — how TLS works, troubleshooting cert issuance
- `docs/backup-and-restore.md` — restore procedure + cron automation
- `docs/updating-services.md` — safe upgrade process
- `docs/troubleshooting.md` — common issues
- `docs/adr/` — architecture decision records (reverse proxy choice, shared Postgres, two-network topology)
