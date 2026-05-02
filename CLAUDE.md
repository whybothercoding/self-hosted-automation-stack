# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Docker Compose stack that runs **n8n + Baserow + PostgreSQL + Caddy** on a single VPS. Caddy handles reverse proxy and automatic Let's Encrypt TLS. Services are split across two internal networks: `proxy-network` (Caddy + n8n + Baserow) and `backend-network` (n8n + Baserow + PostgreSQL). Only Caddy exposes ports 80/443 to the outside; PostgreSQL is unreachable from the proxy layer.

## Commands

```bash
# First-time setup (interactive — writes .env, pulls images, starts stack)
bash scripts/setup.sh

# Dev mode — no Caddy, services on direct ports (n8n :5678, Baserow :8080)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Production management
docker compose ps
docker compose logs <service> --follow   # services: n8n, baserow, postgres, caddy
docker compose restart <service>
docker compose stop / start

# Backup (stops stack → snapshots volumes → restarts)
bash scripts/backup.sh

# Update (pulls latest images, redeploys, prunes old images)
bash scripts/update.sh
```

## Makefile Shortcuts

The Makefile wraps all common operations. Prefer `make <target>` over remembering raw commands:

```bash
make setup    # first-run interactive setup
make up       # docker compose up -d
make down     # docker compose down
make dev      # dev mode with direct ports, no Caddy
make logs     # docker compose logs -f
make backup   # bash scripts/backup.sh
make update   # bash scripts/update.sh
make restart  # docker compose restart
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
- **`Caddyfile`** — reads domain/subdomain from env vars at runtime via `{$VAR}` syntax; adds security headers; gzip on both virtual hosts

## Critical Constraints

- `N8N_ENCRYPTION_KEY` — generated once by `setup.sh` via `openssl rand -hex 32`. **Never change it after first run**; doing so breaks all stored n8n credentials.
- `BASEROW_SECRET_KEY` — Django secret key; same rule applies.
- Both databases (`N8N_DB_NAME`, `BASEROW_DB_NAME`) are created automatically by each app on first run inside the shared Postgres container. The `POSTGRES_DB` var is just the default DB created at container init and isn't used by n8n or Baserow directly.
- Volume names in `backup.sh` are detected dynamically via `docker compose config` — no hardcoded prefix. The script requires `.env` to exist so compose config can resolve variable substitutions.

## Docs

- `docs/initial-setup.md` — full fresh-VPS walkthrough
- `docs/ssl-configuration.md` — how TLS works, troubleshooting cert issuance
- `docs/backup-and-restore.md` — restore procedure + cron automation
- `docs/updating-services.md` — safe upgrade process
- `docs/troubleshooting.md` — common issues
