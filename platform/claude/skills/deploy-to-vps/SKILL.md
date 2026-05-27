---
name: deploy-to-vps
description: Deploys a Dockerized service to an Ubuntu VPS (Hetzner, RackNerd, Linode, or any provider) using Caddy for TLS termination. Use when deploying a service to a server for the first time, or setting up a new deployment.
---

# Deploy to VPS

## Steps

1. Confirm: which server? If it's a new server, run `provision-vps` skill first.
2. Confirm: which domain or subdomain? DNS already pointed at the server? If not, document the DNS record needed and ask me to add it.
3. SSH key documented? If not, run the SSH key step from `provision-vps` first.
4. Deploy method (in order of preference):
   - **Container registry pull**: build locally or in CI, push to GHCR (free for public, $0 small private), pull on server.
   - **Git pull + build on server**: only if image build is fast and server has resources.
   - **Direct file copy via rsync**: only for very small services with no CI.
5. Service definition lives in `/opt/<service-name>/docker-compose.yml` on the server.
6. Env file lives in `/opt/<service-name>/.env`, mode 600, owner root.
7. Caddy reverse proxy: run `caddy-reverse-proxy` skill to configure TLS and routing.
8. Set up systemd unit OR rely on `docker compose --restart=unless-stopped`. Pick one consistently.
9. Run `vps-backup-strategy` skill if not already configured.
10. Run `monitor-vps` skill to wire up monitoring.
11. Run `vps-document` skill to capture this service in the servers-inventory repo.
12. Smoke test: hit the service via its public URL, verify TLS, verify healthcheck, verify logs.

## Checkpoints

- ASK before exposing any port other than 80/443 publicly.
- ASK before deploying without TLS.
- ASK before deploying without backups configured.
- ASK before deploying without basic auth or proper auth on admin endpoints.

## Related skills

- `provision-vps`
- `caddy-reverse-proxy`
- `vps-backup-strategy`
- `monitor-vps`
- `vps-document`
- `harden-for-production`

<!-- last_reviewed: 2026-05-12 -->
