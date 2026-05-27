---
name: harden-for-production
description: Pre-production hardening checklist — auth, rate limits, secret management, monitoring, backups, runbook. Use before shipping a service to users. Trigger on phrases like "ready for production", "going live", "launch this".
---

# Production hardening checklist

## Steps

Walk through each section. For each item: confirmed in place, needs work, or N/A with reason.

### Security
- [ ] HTTPS only. HTTP redirects to HTTPS.
- [ ] HSTS header set.
- [ ] All secrets in env vars or secret manager. None hardcoded.
- [ ] No default credentials anywhere.
- [ ] Auth enforced on every non-public endpoint.
- [ ] Rate limits on every public endpoint.
- [ ] Input validation on every external input.
- [ ] CORS configured correctly (not `*` for non-public APIs).
- [ ] SQL parameterized, no string concatenation in queries.
- [ ] File uploads validated (type, size, content).
- [ ] Security headers: CSP, X-Frame-Options, X-Content-Type-Options.
- [ ] Dependencies scanned for vulnerabilities (run `/audit-deps`).

### Reliability
- [ ] Healthcheck endpoint exists and reflects actual health.
- [ ] Graceful shutdown handles in-flight requests.
- [ ] Timeouts on every external call.
- [ ] Retries with exponential backoff where appropriate.
- [ ] Circuit breakers on flaky external dependencies.
- [ ] Database connection pool sized appropriately.
- [ ] No `latest` tags in production images.

### Observability
- [ ] Structured logging in place (see `add-observability`).
- [ ] Metrics exported.
- [ ] Error tracking configured.
- [ ] Alerts wired for: error rate, latency, downtime, cost spike.

### Operational
- [ ] Backups running and verified (see `vps-backup-strategy`).
- [ ] Restore procedure tested.
- [ ] Runbook documented: how to deploy, rollback, restart, restore.
- [ ] On-call contact info documented.
- [ ] Incident response template ready.

### Data
- [ ] Personal data identified and inventoried.
- [ ] Retention policy documented.
- [ ] Deletion flow for data subject requests works.
- [ ] PII not in logs.

### Cost
- [ ] Per-request cost calculated.
- [ ] Daily/monthly spend cap configured where possible.
- [ ] Cost alerts wired.

## Checkpoints

- STOP after the checklist. Present the unchecked items. Wait for my decisions before fixing.

<!-- last_reviewed: 2026-05-12 -->
