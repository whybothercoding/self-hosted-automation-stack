# Initial Setup Guide

This guide walks you through deploying the stack on a fresh Ubuntu VPS from scratch.

## 1. Provision Your VPS

You need a VPS with:
- Ubuntu 20.04 LTS or later
- At least 2 GB RAM (4 GB recommended for running both n8n and Baserow)
- Ports 80 and 443 open in the firewall

### Open Firewall Ports (UFW)

```bash
sudo ufw allow 22/tcp    # SSH — ensure this is open before enabling ufw
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

## 2. Point DNS at Your Server

Before starting the stack, create DNS A records for both subdomains:

| Record                    | Type | Value              |
|---------------------------|------|--------------------|
| `n8n.yourdomain.com`      | A    | Your VPS public IP |
| `baserow.yourdomain.com`  | A    | Your VPS public IP |

**Wait for DNS to propagate before running setup.** You can verify with:

```bash
dig +short n8n.yourdomain.com
# Should return your VPS IP
```

DNS propagation typically takes 5–30 minutes with modern registrars. Caddy's automatic SSL will fail if DNS hasn't propagated yet.

## 3. Install Docker on Ubuntu

```bash
# Remove any old versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Allow current user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
docker compose version
```

## 4. Clone the Repository

```bash
git clone https://github.com/theoslasha/self-hosted-automation-stack.git
cd self-hosted-automation-stack
```

## 5. Run Setup

```bash
bash scripts/setup.sh
```

The script will prompt you for:

- **Domain name** — your root domain (e.g. `example.com`)
- **n8n subdomain** — defaults to `n8n` → becomes `n8n.example.com`
- **Baserow subdomain** — defaults to `baserow` → becomes `baserow.example.com`
- **Email for SSL** — used for Let's Encrypt registration
- **PostgreSQL password** — choose a strong password (not shown in terminal)
- **Encryption keys** — auto-generated with `openssl rand -hex 32`; the n8n key is printed on screen — **save it immediately**

The script then:
1. Writes your answers to `.env`
2. Runs `docker compose pull` to download images (~1-2 GB, takes a few minutes)
3. Runs `docker compose up -d` to start all services

## 6. Verify Everything is Running

```bash
docker compose ps
```

Expected: all four services showing `Up` (postgres will also show `healthy`):

```
NAME       STATUS          PORTS
postgres   Up (healthy)
n8n        Up
baserow    Up
caddy      Up              0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

### Check SSL Certificate Issuance

```bash
docker compose logs caddy --tail=50
```

Look for lines containing `certificate obtained successfully`. This may take 1–2 minutes after first start.

Once SSL is confirmed:
- **n8n:** `https://n8n.yourdomain.com` — account creation wizard
- **Baserow:** `https://baserow.yourdomain.com` — registration page

## 7. First-Run Configuration

### n8n

On first visit, n8n shows an account creation form. Create your admin account. Your workflows, credentials, and settings are stored in the `n8n_data` volume and PostgreSQL.

### Baserow

Baserow shows a registration page on first visit. Create your admin account. All table data is in PostgreSQL; file uploads are in the `baserow_data` volume.

## 8. Next Steps

- [Set up automated backups](backup-and-restore.md)
- [Understand how SSL works and troubleshoot issues](ssl-configuration.md)
- [Learn how to update services safely](updating-services.md)
