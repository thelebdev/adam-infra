# Roadmap

Forward-looking work for the platform layer. Items here are scoped enough to
be actionable but small enough to ship one at a time. Promoted to the
CHANGELOG when delivered.

## Recently delivered

### Persistent, multi-session, per-user browser Claude

ttyd now serves named, tmux-backed Claude Code sessions through the
`claude-session` helper. A session survives a browser refresh, a logoff, or a
dropped connection; `claude.<domain>/?arg=<name>` gives each browser tab its
own independent Claude. Each Authelia user gets a private set of sessions —
a per-user tmux socket keyed off `$TTYD_USER` (ttyd `-H Remote-User`). New
sessions are confined to `WORKSPACE_ROOT`; they can never run in `$HOME` or
above it. The dashboard gained a live **Claude sessions** section (list /
open / start / stop) backed by the new `session-manager` service
(`11-session-manager.sh`). Caddy was hardened against the `forward_auth`
identity-header spoof (CVE-2026-30851). Session-level isolation only — all
sessions still run as the one admin OS account; OS-level isolation (per-user
Linux accounts) remains a possible future step.

### Platform dashboard + configurable Claude working directory

A static landing page at the apex domain and `dashboard.<domain>` indexes
every platform tool, gated by Authelia (`10-dashboard.sh`). The browser
Claude session opens in a working directory chosen at bootstrap
(`CLAUDE_WORKDIR`, prompted by `07-ttyd.sh`). Additional Authelia users can
be added with `platform/authelia/add-user.sh`; `users_database.yml` is now
rendered once so they survive bootstrap re-runs.

### Better secure-access mechanism — Authelia SSO + TOTP, ttyd for Claude in browser

Replaced public-SSH-with-basic-auth-on-dashboards with Authelia (single
sign-on, password + TOTP) gating every subdomain under PRIMARY_DOMAIN.
Added ttyd serving Claude Code in a browser tab at claude.<domain>, so the
agent is reachable from any device with a browser — phone, work laptop,
anywhere — without an SSH client.

## Near term

### Backup orchestration

restic to S3-compatible storage (Hetzner Storage Box, Backblaze B2, etc.),
daily snapshots, 30/12/12 retention, encrypted with
`BACKUP_ENCRYPTION_PASSPHRASE`. Volumes registered in
`platform/backup/registry.yml`. Restore runbook.

**Status.** Stubbed in `docs/BACKUP_RESTORE.md`. Not implemented. Higher
priority now: Authelia users added via `add-user.sh` live only in gitignored
runtime files (`users_database.yml`, the Authelia SQLite DB,
`platform/authelia/secrets/`). Without backups, a from-zero recovery
restores only the seeded operator.

### Alertmanager + SMTP routing

Prometheus alert rules per-app, alertmanager routing severities to email
(P0–P3). Quiet hours configurable. Foundation for adding Slack/Telegram
later.

**Status.** Stubbed in `docs/ALERTING.md`. Not implemented.

### Authelia email onboarding (SMTP notifier)

Switch Authelia's notifier from `filesystem` to `smtp` so a new user gets a
password-reset link by email (they set their own password) and can self-enrol
TOTP in the browser, instead of the operator running `add-user.sh` and
conveying the password out of band. Authelia cannot delegate to Google or
other social logins (it is an OIDC provider, not a relying party), so an
SMTP-driven self-service flow is the realistic "email onboarding" path.

**Status.** Not started. `add-user.sh` is the current path. Shares the SMTP
wiring with the Alertmanager item above — land SMTP once for both.

### One-shot seed installer (`bootstrap/seed.sh`)

Curl-able installer for a brand-new VPS that fetches the repo to
`/opt/infra` and runs `bootstrap.sh` end-to-end. Cuts the manual M1–M5 setup
to a single command.

**Status.** Not started.

## Later

- **Suricata IDS feeding ntopng** — host-level intrusion detection.
- **Per-app Caddyfile fragments** under `platform/caddy/fragments/` — formal
  contract for applications to declare their public routes and Authelia
  policies (`one_factor` / `two_factor` / `bypass`).
- **WebAuthn / hardware-key second factor** — Authelia supports passkeys
  and FIDO2 in addition to TOTP. Promote once TOTP rollout is stable.
- **Migration to NixOS or similar** for fully declarative host state — only
  if/when the current bash-script approach hits a wall.

## How to use this file

- Add items as they come up. Keep each scoped to one PR's worth of work.
- When taking on an item, link it to a branch or PR.
- When delivered, move to "Recently delivered" above (and add a one-line
  CHANGELOG entry).
