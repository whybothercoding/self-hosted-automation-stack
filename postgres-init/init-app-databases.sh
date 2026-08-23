#!/bin/sh
set -e

# Runs automatically on first container init (only when the data directory
# is empty) — this is the official postgres image's docker-entrypoint-initdb.d
# mechanism, not custom logic.
#
# POSTGRES_DB only gets one database created for free at initdb time. n8n and
# Baserow each need their own database on this shared instance, and neither
# app creates its own database on connect — n8n's pg client and Baserow's
# Django/psycopg both just fail with "database does not exist" if it isn't
# already there. This script creates both explicitly, once, at first boot.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE "$N8N_DB_NAME";
    CREATE DATABASE "$BASEROW_DB_NAME";
EOSQL
