---
name: vps-backup-strategy
description: Sets up automated backups for a VPS — full server snapshot via the provider's API plus daily database dumps to offsite storage. Use when adding backups to a new or existing server.
---

# VPS backup strategy

## Self-update on invocation

1. WebSearch for "Postgres backup best practices 2026" and "VPS backup offsite storage 2026".
2. Verify current pricing on the storage options below.
3. Propose updates. Apply with my approval.

## Backup tiers

Three independent layers. All three must be working before considering backups done.

### Tier 1 — Full server snapshot (provider-level)

Used for: full disaster recovery, including OS, configs, all data.

Options:
- **Hetzner**: built-in snapshots, ~€0.0119/GB/month. Schedule via Hetzner Cloud API or weekly manual.
- **DigitalOcean**: built-in snapshots, $0.06/GB/month. Schedule via API.
- Set up automated weekly snapshots, retain 4 weeks.

### Tier 2 — Database dumps (daily)

Used for: granular DB restore, point-in-time recovery.

1. Script: `pg_dump --format=custom --compress=9` for Postgres.
2. Output: `/var/backups/postgres/<db>_<timestamp>.dump`.
3. Schedule: daily at 03:00 server time via systemd timer (preferred over cron).
4. Retention on server: 7 days.
5. Encryption: gpg encrypt before transfer offsite. Key documented in Bitwarden.

### Tier 3 — Offsite copy (daily)

Used for: surviving total provider failure or account compromise.

Options (rank by cost-to-reliability):
- **Backblaze B2**: $0.006/GB/month storage, $0.01/GB egress. Cheapest credible option.
- **Cloudflare R2**: free egress, $0.015/GB/month. Better if you ever need to read back regularly.
- **Hetzner Storage Box**: €3.20/month for 1TB. Bundled if already on Hetzner.

Tool: `restic` or `rclone` — verify current recommendation via WebSearch.

1. Sync encrypted database dumps to offsite daily, immediately after dump completes.
2. Retain on offsite: 30 days.
3. Restic snapshot lifecycle: keep 7 daily, 4 weekly, 12 monthly.

## Steps to set up

1. Confirm: which provider, which databases, which storage backend.
2. Generate gpg key for backup encryption. Public key on server, private key in Bitwarden.
3. Set up the dump script and systemd timer.
4. Set up the offsite sync (restic init, schedule).
5. Run a manual test: dump → encrypt → sync → list offsite contents.
6. Run a manual restore test: pull a recent backup, decrypt, restore to a test DB, verify integrity.
7. Wire up monitoring: alert if backup hasn't run in 30 hours, alert if offsite size shrinks unexpectedly.
8. Document in `vps-document`: backup strategy, schedule, last successful, last verified restore.

## Checkpoints

- STOP and confirm with me which offsite storage to use before incurring costs.
- ALWAYS test restore before declaring backups working.
- ASK before storing the gpg private key anywhere other than Bitwarden.

## Related skills

- `vps-document`
- `monitor-vps`

<!-- last_reviewed: 2026-05-12 -->
