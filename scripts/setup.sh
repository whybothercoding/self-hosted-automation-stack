#!/usr/bin/env bash
set -e

# -------------------------------------------------------
# setup.sh — Interactive first-run setup for the stack
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "  Self-Hosted Automation Stack Setup"
echo "========================================"
echo ""

# --- Dependency checks ---
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not installed. See https://docs.docker.com/engine/install/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "ERROR: Docker Compose v2 is not available. Update Docker or install the plugin."
  exit 1
fi

# --- Avoid overwriting existing .env ---
if [ -f "$PROJECT_DIR/.env" ]; then
  echo "ERROR: .env already exists. Delete it or edit it manually to re-run setup."
  exit 1
fi

cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"

echo "Please provide the following configuration values."
echo "(Press ENTER to accept the default shown in brackets.)"
echo ""

# --- Prompts ---
read -rp "Domain name (e.g. example.com): " DOMAIN
while [ -z "$DOMAIN" ]; do
  echo "Domain name is required."
  read -rp "Domain name: " DOMAIN
done

read -rp "n8n subdomain [n8n]: " N8N_SUBDOMAIN
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"

read -rp "Baserow subdomain [baserow]: " BASEROW_SUBDOMAIN
BASEROW_SUBDOMAIN="${BASEROW_SUBDOMAIN:-baserow}"

read -rp "Email for SSL certificate (Let's Encrypt): " LETSENCRYPT_EMAIL
while [ -z "$LETSENCRYPT_EMAIL" ]; do
  echo "Email is required for SSL."
  read -rp "Email: " LETSENCRYPT_EMAIL
done

read -rsp "PostgreSQL password: " POSTGRES_PASSWORD
echo ""
while [ -z "$POSTGRES_PASSWORD" ]; do
  echo "Password is required."
  read -rsp "PostgreSQL password: " POSTGRES_PASSWORD
  echo ""
done

N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
echo ""
echo "Generated n8n encryption key: $N8N_ENCRYPTION_KEY"
echo "IMPORTANT: Save this key somewhere safe. Losing it means losing encrypted credentials."
echo ""

BASEROW_SECRET_KEY=$(openssl rand -hex 32)

# --- Write values into .env (cross-platform sed) ---
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

sed_inplace "s|^DOMAIN=.*|DOMAIN=${DOMAIN}|" "$PROJECT_DIR/.env"
sed_inplace "s|^N8N_SUBDOMAIN=.*|N8N_SUBDOMAIN=${N8N_SUBDOMAIN}|" "$PROJECT_DIR/.env"
sed_inplace "s|^BASEROW_SUBDOMAIN=.*|BASEROW_SUBDOMAIN=${BASEROW_SUBDOMAIN}|" "$PROJECT_DIR/.env"
sed_inplace "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}|" "$PROJECT_DIR/.env"
sed_inplace "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" "$PROJECT_DIR/.env"
sed_inplace "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}|" "$PROJECT_DIR/.env"
sed_inplace "s|^BASEROW_SECRET_KEY=.*|BASEROW_SECRET_KEY=${BASEROW_SECRET_KEY}|" "$PROJECT_DIR/.env"
sed_inplace "s|^WEBHOOK_URL=.*|WEBHOOK_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}|" "$PROJECT_DIR/.env"

echo "Configuration written to .env"
echo ""

# --- Pull and start ---
cd "$PROJECT_DIR"
echo "Pulling latest images..."
docker compose pull

echo ""
echo "Starting services..."
docker compose up -d

echo ""
echo "========================================"
echo "  Stack is running!"
echo ""
echo "  n8n:     https://${N8N_SUBDOMAIN}.${DOMAIN}"
echo "  Baserow: https://${BASEROW_SUBDOMAIN}.${DOMAIN}"
echo ""
echo "  Note: SSL certificates may take 1-2 minutes to issue."
echo "  Check logs: docker compose logs -f caddy"
echo "========================================"
