---
name: monitor-vps
description: Wires up monitoring and alerting for a VPS — uptime, resources, log aggregation. Pluggable across self-hosted and SaaS options. Use after provisioning a new server.
---

# Monitor a VPS

## Self-update on invocation

1. WebSearch for "self-hosted monitoring 2026" and "free tier monitoring SaaS 2026".
2. Propose updates. Apply with my approval.

## Three monitoring layers

### 1. Uptime (external probe)

Something outside the server checks it's responding. Tools:
- **Uptime Kuma** (self-hosted, free)
- **Better Stack** (free tier: 10 monitors)
- **Cronitor** (free tier)

Probe: `GET https://<domain>/health` every 60s. Alert on 2 consecutive failures.

### 2. Resources (on-server agent)

- **Netdata** (self-hosted, ships data nowhere by default, optionally streams)
- **node_exporter + Prometheus + Grafana** (more setup, full control)
- **Better Stack agent** (paid beyond free tier)

Watch:
- CPU > 80% for 5min
- Memory > 90% for 5min
- Disk > 85% (warn) / 95% (critical)
- Load average > 2x CPU count for 5min
- Swap in use steady state

### 3. Logs (aggregation)

- **Loki + Grafana** (self-hosted, pairs with Prometheus)
- **Better Stack Logs** (free tier: 1GB/month)
- **Axiom** (free tier: 500GB/month)

Ship: Caddy access logs, application logs, system journal.

## Alerting channels

- Email always.
- WhatsApp/Telegram via a bot for critical alerts.
- Phone call for critical alerts (Better Stack supports this on paid tier; consider for production-grade services).

## Steps

1. Confirm: which tier of monitoring matches this server's importance? Personal experiment vs production service.
2. Pick tools per layer.
3. Install/configure each.
4. Verify alerts fire: deliberately break something and confirm you got paged.
5. Document the monitoring setup in `vps-document`.

## Checkpoints

- ASK before configuring SMS or phone-call alerts (cost-bearing).
- VERIFY alerts actually fire before declaring done.

## Related skills

- `vps-document`
- `add-observability`

<!-- last_reviewed: 2026-05-12 -->
