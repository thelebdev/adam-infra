---
name: vps-audit
description: Health and security audit of a VPS. Use periodically (monthly) or when investigating issues. Reports findings, does not fix without approval.
---

# Audit a VPS

## Self-update on invocation

1. WebSearch for "Linux server audit checklist 2026" and "VPS security audit".
2. Propose updates. Apply with my approval.

## Steps

Run each check, capture output, report findings categorized as: critical, warning, info.

### Security
- [ ] Pending security updates: `apt list --upgradable | grep -i security`
- [ ] Unattended upgrades active and last run recent
- [ ] SSH config still hardened (no password auth, no root login)
- [ ] fail2ban active, recent bans logged
- [ ] Firewall enabled, expected rules in place
- [ ] No unexpected listening ports: `ss -tlnp`
- [ ] No unexpected sudo users
- [ ] No unexpected SSH authorized_keys entries
- [ ] No suspicious cron jobs or systemd timers
- [ ] World-writable files in /etc or /var

### Reliability
- [ ] Disk usage on all mounts (alert >80%)
- [ ] Memory pressure (any swap usage in steady state?)
- [ ] Load average vs CPU count
- [ ] OOM kills in journal
- [ ] Long-running processes hogging resources
- [ ] Failed systemd units: `systemctl --failed`
- [ ] Failed docker containers: `docker ps -a --filter status=exited`

### Backup
- [ ] Last successful backup
- [ ] Backup size growing as expected
- [ ] Restore tested in last 90 days
- [ ] Offsite copy verified

### TLS / Caddy
- [ ] All certs renew automatically
- [ ] No certs expiring in <30 days without auto-renewal

### Logs
- [ ] /var/log not full
- [ ] Logrotate working
- [ ] No unusual error spikes

### Docker
- [ ] No containers running with `--privileged` unless documented
- [ ] No images older than 6 months in use
- [ ] No orphaned volumes consuming disk

### Documentation drift
- [ ] Compare actual state to `servers-inventory` entry. Note discrepancies.

## Steps after audit

1. Report findings, grouped by severity.
2. STOP. Wait for me to decide what to fix.
3. For approved fixes: open a checklist, work through it, document changes in `vps-document` skill.

## Checkpoints

- NEVER auto-fix without my approval.
- NEVER restart services without my approval.
- ASK before applying updates that require a reboot.

<!-- last_reviewed: 2026-05-12 -->
