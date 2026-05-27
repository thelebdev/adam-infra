---
name: vps-document
description: Documents a VPS into the servers-inventory GitHub repo. Captures services, ports, certs, backup status, and access info. Use when a server's config changes meaningfully, after provisioning, or as a periodic audit.
---

# Document a VPS

## Where docs live

Private GitHub repo: `servers-inventory` (or current repo name — confirm with me on first use).
Structure:
```
servers-inventory/
  README.md                     # overview, conventions
  servers/
    <server-slug>.md            # one file per server
  templates/
    server-template.md
```

## Self-update on invocation

1. WebSearch for current best practices on infrastructure documentation.
2. Propose updates to the template. Apply with my approval.

## Steps

1. Determine server slug: `<provider>-<region>-<purpose>` (e.g., `hetzner-fsn1-operator`).
2. Pull current state from the server:
   - OS version, kernel, uptime.
   - Specs: vCPU, RAM, disk usage.
   - Open ports (ss / netstat).
   - Running services (systemctl, docker ps).
   - Caddy sites and the domains they serve.
   - Cron jobs.
   - User accounts and their sudo status.
   - Firewall rules.
   - Fail2ban status.
   - Disk and filesystem layout.
   - Backup status (last successful, where stored).
   - TLS cert expiry dates (from Caddy or certbot).
3. Write `servers/<slug>.md` using this structure:
   ```markdown
   # <server-slug>

   ## Overview
   - Provider, region, plan
   - Public IP, hostname
   - Created: <date>
   - Purpose
   - Owner

   ## Access
   - SSH: <user>@<host> -p <port>
   - SSH key: <key-file-name>, held on <local-machine>
   - Console: <provider-link>

   ## Specs
   - CPU, RAM, Disk

   ## Services
   | Service | Port | Domain | Container | Notes |

   ## Networking
   - Open ports
   - Firewall rules
   - DNS records pointing here

   ## TLS
   - Domain → cert expiry → renewal mechanism

   ## Backups
   - Strategy, schedule, last run, storage location

   ## Monitoring
   - Endpoint, alerts wired, on-call

   ## Notes / known issues

   ## Changelog
   - YYYY-MM-DD: change description
   ```
4. Commit to `servers-inventory` with conventional commit message: `docs(<server-slug>): <change>`.
5. STOP before pushing. Show me the diff. I push.

## Checkpoints

- NEVER include secrets, passwords, API keys, or any credential in these docs.
- ASK before adding any sensitive operational detail (specific paths, internal IPs of other services).
- The repo is private — but treat it as if it could leak. No secrets.

<!-- last_reviewed: 2026-05-12 -->
