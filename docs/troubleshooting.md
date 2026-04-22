# Troubleshooting

## Viewing Logs

Always start here:

```bash
docker compose logs <service> --tail=100 --follow
# Services: postgres, n8n, baserow, caddy
```

All services at once:

```bash
docker compose logs --tail=50
```

---

## Container Won't Start

**Symptom:** `docker compose ps` shows a service as `Exiting` or `Restarting`.

**Step 1:** Read the logs for the failing service:

```bash
docker compose logs <service> --tail=50
```

**Step 2:** Check for missing or malformed environment variables:

```bash
cat .env
```

Compare against `.env.example`. Every variable must have a non-empty value (except optional SMTP fields).

**Step 3:** In dev mode only — check for port conflicts:

```bash
sudo lsof -i :5678   # n8n
sudo lsof -i :8080   # baserow
sudo lsof -i :80
sudo lsof -i :443
```

Kill the conflicting process or change the port in `docker-compose.dev.yml`.

---

## Can't Connect to PostgreSQL

**Symptom:** n8n or Baserow logs show `connection refused`, `password authentication failed`, or `database does not exist`.

**Check 1: Is PostgreSQL healthy?**

```bash
docker compose ps postgres
```

It must show `(healthy)`. If it shows `(health: starting)`, wait 15–30 seconds and check again.

```bash
docker compose logs postgres --tail=30
```

**Check 2: Do credentials match?**

The `POSTGRES_USER` and `POSTGRES_PASSWORD` in `.env` must match what PostgreSQL was initialised with. If you changed the password in `.env` after first start, PostgreSQL still has the original password. Update it:

```bash
docker compose exec postgres psql -U $POSTGRES_USER -c "ALTER USER $POSTGRES_USER WITH PASSWORD 'newpassword';"
```

Then update `.env` to match and restart: `docker compose restart n8n baserow`

**Check 3: Database doesn't exist yet**

n8n and Baserow create their own databases on first startup. If they crash before the DB is created, restart them after PostgreSQL is healthy:

```bash
docker compose restart n8n
docker compose restart baserow
```

---

## SSL Not Issuing

See the full guide in [ssl-configuration.md](ssl-configuration.md).

Quick checklist:

- [ ] DNS A records for both subdomains resolve to this server's IP: `dig +short n8n.yourdomain.com`
- [ ] Port 80 is open in UFW: `sudo ufw status`
- [ ] Port 80 is open in your cloud provider's firewall panel
- [ ] You haven't hit the Let's Encrypt rate limit (5 certs/week per domain)

Check Caddy logs for specific errors:

```bash
docker compose logs caddy --tail=100 | grep -iE "error|acme|certificate|tls"
```

If DNS only recently propagated, restart Caddy to trigger a new attempt:

```bash
docker compose restart caddy
```

---

## n8n Webhooks Not Working

**Symptom:** Webhook triggers don't fire, or external services can't reach n8n webhooks.

**Check 1: WEBHOOK_URL is set correctly**

```bash
grep WEBHOOK_URL .env
```

It must be your full public HTTPS URL:

```
WEBHOOK_URL=https://n8n.yourdomain.com
```

Not `http://`, not `localhost`. After changing, restart n8n:

```bash
docker compose restart n8n
```

**Check 2: Webhook URL is reachable externally**

From your local machine:

```bash
curl -I https://n8n.yourdomain.com/webhook-test/test
# Should return 404 (expected — no workflow listening)
# Should NOT return connection refused or 502
```

A 502 means Caddy can't reach n8n. Check n8n is running: `docker compose ps n8n`.

**Check 3: Dev mode webhooks**

In dev mode (`docker-compose.dev.yml`), `WEBHOOK_URL` is set to `http://localhost:5678`. External services cannot reach `localhost` — use production mode (with Caddy) for external webhook testing.

---

## Baserow Database Errors

**Symptom:** Baserow shows an error page, or logs contain database migration errors.

**Check 1: Still running migrations?**

On first start, Baserow runs Django migrations which can take 1–3 minutes. Watch the logs:

```bash
docker compose logs baserow --tail=50 --follow
```

Wait for a message like `Starting Baserow...` or the Gunicorn startup message.

**Check 2: Partial migration state**

If Baserow was stopped mid-migration, the database may be in an inconsistent state. Drop and recreate the Baserow database:

```bash
docker compose exec postgres psql -U $POSTGRES_USER -c "DROP DATABASE IF EXISTS baserow;"
docker compose exec postgres psql -U $POSTGRES_USER -c "CREATE DATABASE baserow;"
docker compose restart baserow
```

**Check 3: DATABASE_URL contains special characters**

If your PostgreSQL password contains characters like `@`, `#`, or `%`, they must be URL-encoded in the `DATABASE_URL`. The simplest fix is to use a password with only alphanumeric characters and underscores. Update `.env` and recreate the PostgreSQL user with the new password.

---

## Port Conflicts (Production)

**Symptom:** Caddy fails to start with `bind: address already in use`.

Another process is using port 80 or 443:

```bash
sudo lsof -i :80
sudo lsof -i :443
```

Common culprits: nginx, Apache, another Caddy instance, or Certbot's standalone mode.

Stop the conflicting service:

```bash
sudo systemctl stop nginx
# or
sudo systemctl stop apache2
```

Then restart Caddy:

```bash
docker compose restart caddy
```

---

## Resetting the Stack

To wipe all data and start completely fresh:

```bash
docker compose down -v
docker compose up -d
```

The `-v` flag removes all named volumes — **all data will be lost**. Only use this if you have a backup to restore from, or you're setting up from scratch.
