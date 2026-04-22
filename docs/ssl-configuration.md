# SSL Configuration

## How It Works

Caddy handles all TLS automatically using Let's Encrypt. When you start the stack:

1. Caddy reads the `Caddyfile` and sees your domain names
2. It performs an HTTP-01 ACME challenge — Caddy temporarily serves a verification file on port 80
3. Let's Encrypt verifies domain ownership and issues the certificate
4. Caddy stores certificates in the `caddy_data` volume and **automatically renews them** 30 days before expiry

You do not need Certbot, manual renewals, or any cron jobs for certificate management.

## Requirements for Automatic SSL

SSL will only issue if all three conditions are met:

1. **DNS points to this server** — Both subdomains must have A records resolving to your VPS public IP
2. **Port 80 is reachable from the internet** — The ACME HTTP-01 challenge uses port 80. If it's blocked, issuance fails
3. **Port 443 is reachable** — Caddy must serve HTTPS after certificate issuance

## Checking SSL Status

```bash
docker compose logs caddy --tail=100 | grep -iE "certificate|tls|acme|error"
```

Successful issuance looks like:

```
certificate obtained successfully  domain=n8n.example.com
certificate obtained successfully  domain=baserow.example.com
```

Verify from your local machine:

```bash
curl -I https://n8n.yourdomain.com
# Should return HTTP/2 200 with no certificate errors
```

## Troubleshooting

### SSL Not Issuing — DNS Not Propagated

Check that your domain resolves to the correct IP:

```bash
dig +short n8n.yourdomain.com
nslookup n8n.yourdomain.com
```

If these return empty or the wrong IP, wait for propagation and then restart Caddy:

```bash
docker compose restart caddy
```

### SSL Not Issuing — Port 80 Blocked

Test from outside your server (your local machine or a remote host):

```bash
curl -v http://n8n.yourdomain.com
```

A timeout means port 80 is blocked. Check:

- **UFW firewall:** `sudo ufw status` — ensure port 80 is allowed
- **Cloud provider firewall:** Hetzner, DigitalOcean, Vultr, AWS, etc. all have separate firewall rules in their control panel — enable port 80 there too
- **VPS provider blocking:** some providers block port 80 by default; check your provider's documentation

### Let's Encrypt Rate Limits

Let's Encrypt allows a maximum of 5 duplicate certificates per registered domain per week. If you're seeing rate limit errors in Caddy logs, you must wait for the limit to reset.

To avoid hitting limits during testing, add the staging CA to the global block in `Caddyfile`:

```caddyfile
{
    email {$LETSENCRYPT_EMAIL}
    acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

Staging certificates are not trusted by browsers but let you test the issuance flow without consuming rate limit quota. Remove the `acme_ca` line for production.

### Certificate Not Renewing

Caddy renews automatically as long as it's running and port 80 remains accessible. If a certificate expires:

1. Check Caddy is still running: `docker compose ps caddy`
2. Check port 80 is still accessible
3. Force a renewal attempt by restarting Caddy: `docker compose restart caddy`

## Using Custom Certificates

If you have your own certificates (wildcard cert, internal CA, etc.):

1. Copy your certificate and private key files to the server
2. Create a `certs/` directory in the project and place them there
3. Update `docker-compose.yml` to mount the certs directory into Caddy:

```yaml
caddy:
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile:ro
    - ./certs:/etc/caddy/certs:ro
    - caddy_data:/data
    - caddy_config:/config
```

4. Update your `Caddyfile` to reference the cert files directly:

```caddyfile
n8n.example.com {
    tls /etc/caddy/certs/cert.pem /etc/caddy/certs/key.pem

    header {
        X-Frame-Options SAMEORIGIN
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
    }

    reverse_proxy n8n:5678
}
```

5. Restart Caddy: `docker compose restart caddy`

## Certificate Storage

Certificates are stored in the `caddy_data` Docker volume. They survive container restarts and image updates. The `scripts/backup.sh` script does **not** back up `caddy_data` by default (certificates are re-issuable for free), but if you want to avoid reissuance downtime after a server migration, include it in your backup routine.
