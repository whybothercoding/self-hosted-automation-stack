# Updating Services

## Standard Update

```bash
bash scripts/update.sh
```

This runs:
1. `docker compose pull` — downloads new image layers for all services
2. `docker compose up -d --remove-orphans` — recreates containers with new images, removes any obsolete containers
3. `docker image prune -f` — removes unused old image layers to free disk space

Each service restarts independently. Expect a few seconds of downtime per service.

## Before Updating

Always back up first, especially before n8n updates (which have historically included breaking changes between minor versions):

```bash
bash scripts/backup.sh
bash scripts/update.sh
```

## Version Pins and Dependabot

`docker-compose.yml` pins all four images to specific versions rather than `:latest` — an update is a deliberate, reviewable change, not something that silently happens on the next `docker compose pull`.

[Dependabot](../.github/dependabot.yml) watches those pinned tags (`package-ecosystem: docker`, GA support for `docker-compose.yml` since Feb 2025) and opens a PR whenever n8n, Baserow, Postgres, or Caddy cut a new release. **Review the linked changelog before merging** — Dependabot bumps the tag, it doesn't read the release notes for you. For n8n specifically, check the breaking-changes guidance below before merging a major-version bump.

To bump a version by hand instead of waiting for Dependabot, edit the `image:` line for that service in `docker-compose.yml` directly:

```yaml
services:
  n8n:
    image: n8nio/n8n:2.36.0   # example — check the current release first
```

Check available versions:
- **n8n:** https://hub.docker.com/r/n8nio/n8n/tags
- **Baserow:** https://hub.docker.com/r/baserow/baserow/tags
- **PostgreSQL:** https://hub.docker.com/_/postgres/tags

After editing (or merging a Dependabot PR), apply:

```bash
docker compose pull
docker compose up -d
```

## Updating n8n — Breaking Changes

n8n follows semantic versioning. Minor and patch updates (e.g. `1.88.x` → `1.89.x`) are generally safe. Major version bumps may include breaking changes to workflow nodes or the database schema.

**Before any n8n update:**
1. Check the [n8n release notes](https://github.com/n8n-io/n8n/releases) for your target version
2. Run `bash scripts/backup.sh`
3. Test critical workflows after the update

If an update breaks a workflow, restore from backup (see [backup-and-restore.md](backup-and-restore.md)) and pin to the previous version while you investigate.

## Updating PostgreSQL — Major Version Warning

PostgreSQL **patch updates** (e.g. `15.6` → `15.7`) are safe — just pull and redeploy.

PostgreSQL **major version upgrades** (e.g. `15` → `16`) **cannot** be done by pulling a new image. The data directory format changes and the new version will refuse to start.

To perform a major version upgrade:

```bash
# 1. Export all databases
docker compose exec postgres pg_dumpall -U $POSTGRES_USER > all_databases_$(date +%Y%m%d).sql

# 2. Stop the stack
docker compose down

# 3. Remove the old volume (data exported above)
PROJ=$(docker compose config | grep -m1 '^name:' | awk '{print $2}')
docker volume rm ${PROJ}_postgres_data

# 4. Update docker-compose.yml to the new major version
#    e.g. postgres:15-alpine → postgres:16-alpine

# 5. Start only postgres with the new version
docker compose up -d postgres

# 6. Wait for it to be healthy
docker compose ps postgres

# 7. Import the exported data
docker compose exec -T postgres psql -U $POSTGRES_USER < all_databases_$(date +%Y%m%d).sql

# 8. Start the remaining services
docker compose up -d
```

## Rollback

If an update breaks something:

1. Stop the stack: `docker compose down`
2. Restore volumes from backup (see [backup-and-restore.md](backup-and-restore.md))
3. Pin the previously working image versions in `docker-compose.yml`
4. Start the stack: `docker compose up -d`
