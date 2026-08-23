# ADR-0001: Caddy as the reverse proxy

## Context

The stack needs a reverse proxy in front of n8n and Baserow that terminates TLS for two subdomains on a single VPS, without requiring the operator to manage certificates by hand. The realistic alternatives were nginx + Certbot, or Traefik.

## Decision

Use Caddy 2.

Caddy issues and renews Let's Encrypt certificates automatically from a declarative `Caddyfile` — no separate Certbot process, no cron job for renewal, no ACME client to wire up. The entire routing + TLS config for this stack is the ~25-line `Caddyfile` in the repo root. nginx would need Certbot bolted on as a second moving part (and a renewal cron job); Traefik's Docker-label-driven config is a better fit for a large, dynamically-changing set of services than for two static virtual hosts known upfront.

## Consequences

- One fewer service, one fewer moving part than nginx + Certbot.
- Config is a plain Caddyfile, not Docker labels — easy to read and diff, but means adding a new subdomain requires a Caddyfile edit + restart rather than being automatic from compose.
- Caddy is less battle-tested at extreme scale than nginx, which is irrelevant here — this stack fronts two low-traffic internal tools, not a public CDN edge.
- Automatic HTTPS depends on ports 80 and 443 being reachable from the internet for the ACME HTTP-01 challenge; documented in [SSL Configuration](../ssl-configuration.md).
