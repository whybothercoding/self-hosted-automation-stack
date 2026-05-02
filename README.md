# Self-Hosted Automation Stack

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Validate](https://github.com/whybothercoding/self-hosted-automation-stack/actions/workflows/validate.yml/badge.svg)](https://github.com/whybothercoding/self-hosted-automation-stack/actions/workflows/validate.yml)

A production-ready Docker Compose stack running **n8n**, **Baserow**, and **PostgreSQL** behind **Caddy** with automatic HTTPS. Clone, configure, and deploy a self-hosted automation suite on any VPS in minutes — no manual SSL certificate management, no external dependencies.

## Architecture

```
                 ┌──────────────────────────────────────────────────┐
                 │                VPS (Docker host)                  │
                 │                                                  │
  Internet       │  ┌─────────┐        proxy-network               │
 ──:80/:443 ────►│  │  Caddy  │──► n8n (:5678)                     │
                 │  │  (TLS)  │└──► Baserow (:80)                   │
                 │  └─────────┘         │          │                │
                 │                      │          │ backend-network │
                 │                      ▼          ▼                │
                 │                   ┌──────────────────┐           │
                 │                   │    PostgreSQL     │           │
                 │                   └──────────────────┘           │
                 └──────────────────────────────────────────────────┘
```

Caddy terminates TLS and proxies to n8n and Baserow over `proxy-network`. Neither Caddy nor the internet can reach PostgreSQL directly — it is only reachable from n8n and Baserow via `backend-network`.

## Services

| Service    | Image                     | Purpose                             | Default URL                      |
|------------|---------------------------|-------------------------------------|----------------------------------|
| n8n        | `n8nio/n8n:latest`        | Workflow automation                 | `https://n8n.yourdomain.com`     |
| Baserow    | `baserow/baserow:latest`  | No-code database / spreadsheet UI  | `https://baserow.yourdomain.com` |
| PostgreSQL | `postgres:15-alpine`      | Shared database backend             | Internal only                    |
| Caddy      | `caddy:2-alpine`          | Reverse proxy + automatic TLS       | Handles 80/443                   |

## Prerequisites

- A VPS running Ubuntu 20.04 or later
- [Docker](https://docs.docker.com/engine/install/) and [Docker Compose v2](https://docs.docker.com/compose/install/) installed
- A domain name with DNS A records pointing to your server's public IP
- Ports 80 and 443 open in your firewall

## Quick Start

```bash
git clone https://github.com/whybothercoding/self-hosted-automation-stack.git
cd self-hosted-automation-stack
bash scripts/setup.sh
```

The setup script prompts for your domain, email, and passwords, writes `.env`, pulls images, and starts the stack. Caddy automatically issues Let's Encrypt certificates for both subdomains.

## Usage

### First Run

Once the stack is up, open your browser:

- **n8n:** `https://n8n.yourdomain.com` — create your admin account, then start building workflows
- **Baserow:** `https://baserow.yourdomain.com` — create your admin account, then create databases and tables

SSL certificates are issued within 1–2 minutes of first start. If your browser shows a certificate warning, wait a moment and refresh.

### Daily Management

```bash
make up         # Start the stack
make down       # Stop and remove containers
make restart    # Restart all services
make logs       # Follow logs for all services
make dev        # Start in dev mode (direct ports, no Caddy)
```

Or with Docker Compose directly:

```bash
docker compose ps
docker compose logs n8n --follow
docker compose restart n8n
```

### Backup

```bash
make backup
# or: bash scripts/backup.sh
```

Stops the stack, snapshots all volumes to `./backups/`, and restarts. See [Backup & Restore](docs/backup-and-restore.md) for restore instructions and cron automation.

### Update

```bash
make update
# or: bash scripts/update.sh
```

Pulls latest images and redeploys. Always run a backup first.

## Development Mode

Run locally without Caddy — services are exposed on direct ports:

```bash
make dev
# or: docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

- n8n: [http://localhost:5678](http://localhost:5678)
- Baserow: [http://localhost:8080](http://localhost:8080)

## Environment Variables

| Variable             | Description                                           | Example                       |
|----------------------|-------------------------------------------------------|-------------------------------|
| `DOMAIN`             | Root domain                                           | `example.com`                 |
| `N8N_SUBDOMAIN`      | Subdomain for n8n                                     | `n8n`                         |
| `BASEROW_SUBDOMAIN`  | Subdomain for Baserow                                 | `baserow`                     |
| `POSTGRES_USER`      | PostgreSQL superuser name                             | `automation`                  |
| `POSTGRES_PASSWORD`  | PostgreSQL password                                   | *(strong random string)*      |
| `POSTGRES_DB`        | Default DB created at init                            | `automation`                  |
| `N8N_DB_NAME`        | Database name for n8n                                 | `n8n`                         |
| `BASEROW_DB_NAME`    | Database name for Baserow                             | `baserow`                     |
| `N8N_ENCRYPTION_KEY` | Encrypts n8n credentials — never change after set     | *(openssl rand -hex 32)*      |
| `BASEROW_SECRET_KEY` | Django secret key for Baserow                         | *(openssl rand -hex 32)*      |
| `GENERIC_TIMEZONE`   | Timezone for n8n scheduling                           | `Europe/Athens`               |
| `LETSENCRYPT_EMAIL`  | Email for Let's Encrypt registration                  | `you@example.com`             |
| `N8N_EMAIL_MODE`     | Email sending mode: `smtp` or empty                   | `smtp`                        |
| `N8N_SMTP_HOST`      | SMTP server hostname                                  | `smtp.example.com`            |
| `N8N_SMTP_PORT`      | SMTP port                                             | `587`                         |
| `N8N_SMTP_USER`      | SMTP username                                         | `user@example.com`            |
| `N8N_SMTP_PASS`      | SMTP password                                         | *(your smtp password)*        |
| `WEBHOOK_URL`        | Public URL for n8n webhooks                           | `https://n8n.example.com`     |

All variables are documented with comments in [`.env.example`](.env.example).

## Scripts

| Script               | Description                                                          |
|----------------------|----------------------------------------------------------------------|
| `scripts/setup.sh`   | Interactive first-run: writes `.env`, pulls images, starts stack     |
| `scripts/backup.sh`  | Stops stack, snapshots all volumes to `backups/`, restarts stack     |
| `scripts/update.sh`  | Pulls latest images, redeploys with `--remove-orphans`, prunes old   |

## Documentation

- [Initial Setup Guide](docs/initial-setup.md) — Full walkthrough from fresh VPS to running stack
- [SSL Configuration](docs/ssl-configuration.md) — How TLS works and troubleshooting
- [Backup & Restore](docs/backup-and-restore.md) — Backup volumes and restore procedures
- [Updating Services](docs/updating-services.md) — Safely updating n8n, Baserow, and Postgres
- [Troubleshooting](docs/troubleshooting.md) — Common issues and solutions

## License

MIT — see [LICENSE](LICENSE)
