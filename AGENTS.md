# self-hosted-automation-stack

Docker Compose stack running **n8n + Baserow + PostgreSQL + Caddy** on a single VPS (public OSS repo). Caddy does reverse proxy and automatic Let's Encrypt TLS. Two internal networks: `proxy-network` (Caddy, n8n, Baserow) and `backend-network` (n8n, Baserow, PostgreSQL). Only Caddy exposes 80/443; PostgreSQL is unreachable from the proxy layer.

## Commands

Prefer `make <target>`: `setup` (first-run interactive, writes `.env`), `up`, `down`, `restart`, `logs`, `dev` (direct ports n8n :5678, Baserow :8080, no Caddy), `backup` (stops stack → snapshots volumes → restarts), `restore TIMESTAMP=20260823_140000`, `update` (pull, redeploy, prune), `test` (boots dev stack, curls both health endpoints: the real smoke test), `backup-test` (backup → destroy volumes → restore → verify; needs a running stack), `security-scan` (local Trivy on the four pinned images). Services: `n8n`, `baserow`, `postgres`, `caddy`.

## Architecture notes

- `docker-compose.dev.yml` ports n8n and Baserow directly and puts Caddy behind a `production` profile. `postgres-init/init-app-databases.sh` creates the `n8n` and `baserow` databases on first init of an empty volume only. `Caddyfile` reads domain/subdomain from env via `{$VAR}`.
- **Don't use `docker compose up --wait`** for boot verification: it fails permanently on the first "unhealthy" transition, and Baserow's first-boot migration briefly reports unhealthy under CI contention. Use `scripts/wait-for-healthy.sh <service...>` (polls `docker inspect`, fails only on a genuine timeout); used by `validate.yml`, `backup-drill.yml`, `scripts/backup-drill.sh`, `make test`.
- CI: `validate.yml` (every push/PR: both compose files, shellcheck, boots the dev stack and curls health endpoints), `security.yml` (weekly Trivy on the four images, non-blocking), `backup-drill.yml` (weekly: marker row → backup → destroy volumes → restore → fail if the marker is missing; logic in `scripts/backup-drill.sh`, shared with `make backup-test`), Dependabot on image tags and Actions.
- **Third-party GitHub Actions are pinned by commit SHA, not tag** (tags are mutable; `aquasecurity/trivy-action` had 75 of 76 tags force-pushed with malware in March 2026). Re-resolve the current SHA when adding one; don't copy an old one.
- `scripts/restore.sh` restores all three volumes from a `backup.sh` snapshot and respects `COMPOSE_FILE`, so it works against the dev override.
- **Container hardening:** every service has `no-new-privileges`; Caddy/n8n/Postgres have `cap_drop: [ALL]` plus only the caps each needs. **Baserow is deliberately not capability-dropped** (its all-in-one supervisor's root requirements are unconfirmed): don't add `cap_drop` there without verifying on a live container (`docs/troubleshooting.md` § Container Won't Start After a Capability Change).
- `docs/adr/` holds architecture decision records (reverse proxy, shared Postgres, two-network topology): add one for a similarly consequential choice, don't retrofit for routine changes. Other docs in `docs/`: initial-setup, ssl-configuration, backup-and-restore, updating-services, troubleshooting.

## Validation

Before committing compose or script changes (mirrors CI):

```bash
cp .env.example .env && docker compose config --quiet \
  && docker compose -f docker-compose.yml -f docker-compose.dev.yml config --quiet; rm .env
shellcheck --severity=error scripts/setup.sh scripts/backup.sh scripts/update.sh scripts/restore.sh scripts/backup-drill.sh scripts/wait-for-healthy.sh
```

Runtime behaviour is verified only by `make test` (needs a local Docker daemon) or the `validate.yml` smoke-test job on a pushed branch; don't claim it verified without one actually running.

## Critical constraints

- `N8N_ENCRYPTION_KEY` (generated once by `setup.sh`, `openssl rand -hex 32`) and `BASEROW_SECRET_KEY` (Django): **never change after first run**; it breaks all stored n8n credentials. `.env.example` ships both blank by design: anything booting from it directly (CI, quick local test) must generate real values first, or Baserow's Django backend won't start (see "Prepare .env" in `validate.yml`).
- `POSTGRES_DB` is only the default DB created at init; **neither app creates its own database on connect**. `postgres-init/init-app-databases.sh` creates `N8N_DB_NAME` and `BASEROW_DB_NAME`, and runs only against an empty `postgres_data` volume; an older volume needs them created manually (`docs/troubleshooting.md` § Can't Connect to PostgreSQL).
- `backup.sh` detects volume names dynamically via `docker compose config` (needs `.env`). It backs up `n8n_data`, `baserow_data`, `postgres_data` only; `caddy_data`/`caddy_config` are excluded on purpose (certs are re-issuable).
- n8n and Baserow start only after Postgres passes `pg_isready`: if either fails, check `docker compose ps postgres` first.
- `setup.sh` uses a `sed_inplace()` helper (macOS vs Linux `sed -i`); any addition writing to `.env` must use it.
- All four images are version-pinned (no `:latest`). Bump via the Dependabot PR and review the changelog first.
