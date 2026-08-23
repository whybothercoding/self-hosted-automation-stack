# ADR-0002: One shared PostgreSQL instance, separate databases per app

## Context

Both n8n and Baserow need a PostgreSQL database. They could each run their own `postgres` container, or share one instance with separate logical databases.

## Decision

Run a single `postgres` service; n8n and Baserow each get their own database inside it (`N8N_DB_NAME`, `BASEROW_DB_NAME`), created automatically by each app on first connection. `POSTGRES_DB` only exists because the official Postgres image requires a default database at init — neither app uses it directly.

For a stack sized for a single small-to-mid VPS, running two separate Postgres containers means two sets of memory overhead, two volumes to back up, and two processes to keep healthy for no functional gain — n8n and Baserow never query each other's data, so there's no coupling risk from sharing the instance.

## Consequences

- One `postgres_data` volume, one healthcheck, one memory budget to size instead of two.
- `scripts/backup.sh` backs up a single volume that contains both apps' data — simpler, but a restore of that volume restores both apps' state together, not independently.
- A Postgres major-version upgrade (e.g. 15 → 16) affects both apps at once and needs `pg_dumpall`, documented in [Updating Services](../updating-services.md) — this is the real cost of sharing the instance, and worth re-evaluating if either app's data volume grows large enough that independent upgrade cadences become valuable.
- Credentials are shared at the PostgreSQL-user level (both apps connect as `POSTGRES_USER`) but data is isolated at the database level — acceptable here since both apps are operated by the same person on the same VPS, not a multi-tenant setup.
