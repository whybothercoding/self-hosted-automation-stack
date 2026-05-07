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
- **`.github/workflows/validate.yml`** — CI runs on every push to main and every PR: validates both compose files and shellchecks all scripts in `scripts/`

## Validation

Before committing changes to compose files or scripts, run these locally (mirrors the CI checks):

```bash
# Validate compose syntax (requires .env to exist)
cp .env.example .env
docker compose config --quiet
docker compose -f docker-compose.yml -f docker-compose.dev.yml config --quiet
rm .env

# Lint shell scripts
shellcheck --severity=error scripts/setup.sh scripts/backup.sh scripts/update.sh
```

## Critical Constraints

- `N8N_ENCRYPTION_KEY` — generated once by `setup.sh` via `openssl rand -hex 32`. **Never change it after first run**; doing so breaks all stored n8n credentials.
- `BASEROW_SECRET_KEY` — Django secret key; same rule applies.
- Both databases (`N8N_DB_NAME`, `BASEROW_DB_NAME`) are created automatically by each app on first run inside the shared Postgres container. The `POSTGRES_DB` var is just the default DB created at container init and isn't used by n8n or Baserow directly.
- Volume names in `backup.sh` are detected dynamically via `docker compose config` — no hardcoded prefix. The script requires `.env` to exist so compose config can resolve variable substitutions.
- `backup.sh` backs up `n8n_data`, `baserow_data`, and `postgres_data` only. `caddy_data` and `caddy_config` are intentionally excluded — certificates are re-issuable from Let's Encrypt for free.
- n8n and Baserow start only after Postgres passes its healthcheck (`pg_isready`). If either service fails to start, confirm Postgres is `(healthy)` first: `docker compose ps postgres`.
- `setup.sh` uses a `sed_inplace()` helper (macOS vs Linux `sed -i` differences). Any additions to that script that write to `.env` must use the same helper.

## Docs

- `docs/initial-setup.md` — full fresh-VPS walkthrough
- `docs/ssl-configuration.md` — how TLS works, troubleshooting cert issuance
- `docs/backup-and-restore.md` — restore procedure + cron automation
- `docs/updating-services.md` — safe upgrade process
- `docs/troubleshooting.md` — common issues
