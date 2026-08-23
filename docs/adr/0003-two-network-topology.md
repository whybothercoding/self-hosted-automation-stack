# ADR-0003: Two Docker networks instead of one

## Context

The original version of this stack put all four services (Caddy, n8n, Baserow, Postgres) on a single bridge network. That's the simplest possible setup, but it means Caddy — the one service directly exposed to the internet — is on the same network as Postgres, which has no business being reachable from the proxy layer at all.

## Decision

Split into two bridge networks:

- `proxy-network`: Caddy, n8n, Baserow — Caddy routes to the two apps.
- `backend-network`: n8n, Baserow, Postgres — the apps talk to the database.

n8n and Baserow sit on both networks (they need to reach Caddy's routing and the database); Caddy and Postgres are each on exactly one, and never share a network with each other.

## Consequences

- If Caddy were ever compromised (a config error, a vulnerable module, a bad upstream dependency), it has no network path to Postgres at all — not "credentials would stop it," but "there is no route." That's a meaningfully stronger guarantee than relying on auth alone.
- Two `networks:` blocks and two entries in most services' `networks:` list instead of one — a small readability cost for a real isolation gain.
- No performance cost: Docker bridge networks are cheap, and n8n/Baserow already needed to be on two networks' worth of routes regardless of how many network objects that's expressed as.
- This is the kind of thing that's easy to skip when a stack is stood up quickly and easy to forget to add later — worth stating explicitly here so it doesn't regress back to one flat network in a future edit.
