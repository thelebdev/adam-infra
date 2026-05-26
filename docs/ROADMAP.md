# Roadmap

Forward-looking work for the platform layer. Items here are scoped enough to
be actionable but small enough to ship one at a time. Promoted to the
CHANGELOG when delivered.

## Recently delivered

### Generic browser terminal sessions (shell or Claude)

The browser terminal stack is now command-agnostic. The subdomain moves
from `claude.<domain>` to `sessions.<domain>`; each session runs either a
login shell (default) or Claude Code (opt-in via the dashboard form or
helper menu). `INSTALL_CLAUDE` splits into `INSTALL_SESSIONS` (the ttyd +
tmux + dashboard panel) and `INSTALL_CLAUDE` (the `claude` binary), so you
can have terminal sessions without Claude, or the binary without the
browser panel. The helper renames `claude-session` → `session`; the
per-session command is recorded in a marker file so resume always re-opens
into the same command. Systemd unit renames (`ttyd-claude.service` →
`ttyd-sessions.service`) and env var renames (`CLAUDE_*` → `SESSION_*`)
ride along. Tests extend with allowlist + marker coverage; 07-ttyd
migrates the old unit/socket dir on re-run.

### Persistent, multi-session, per-user browser Claude

ttyd serves named, tmux-backed sessions through the session helper. A
session survives a browser refresh, a logoff, or a dropped connection;
`sessions.<domain>/?arg=<name>` gives each browser tab its own independent
session. Each Authelia user gets a private set — a per-user tmux socket
keyed off `$TTYD_USER` (ttyd `-H Remote-User`). New sessions are confined
to `WORKSPACE_ROOT`; they can never run in `$HOME` or above it. The
dashboard has a live **Terminal sessions** section (list / open / start /
stop) backed by the `session-manager` service (`11-session-manager.sh`).
Caddy was hardened against the `forward_auth` identity-header spoof
(CVE-2026-30851). Session-level isolation only — all sessions still run as
the one admin OS account; OS-level isolation (per-user Linux accounts)
remains a possible future step.

### Platform dashboard + configurable Claude working directory

A static landing page at the apex domain and `dashboard.<domain>` indexes
every platform tool, gated by Authelia (`10-dashboard.sh`). The browser
Claude session opens in a working directory chosen at bootstrap
(`CLAUDE_WORKDIR`, prompted by `07-ttyd.sh`). Additional Authelia users can
be added with `platform/authelia/add-user.sh`; `users_database.yml` is now
rendered once so they survive bootstrap re-runs.

### Better secure-access mechanism — Authelia SSO + TOTP, ttyd for sessions in browser

Replaced public-SSH-with-basic-auth-on-dashboards with Authelia (single
sign-on, password + TOTP) gating every subdomain under PRIMARY_DOMAIN.
Added ttyd serving browser terminal sessions at sessions.<domain> (formerly
claude.<domain>), so the agent — or a plain shell — is reachable from any
device with a browser, without an SSH client.

## Near term

### Verify the dashboard /api/* auth gate actually fires (carry-over from 2026-05-25)

The dashboard's `/api/sessions` and `/api/workspace` still return 401
"missing or ambiguous identity" through Caddy, even with the user logged
in. Three back-to-back fixes were merged that night and the symptom
persists:

- PR #6 wrapped the `authelia_gate` snippet in `route { }` so
  `request_header` runs before `forward_auth` (Caddy reorders by directive
  priority).
- PR #7 fixed an unrelated parsing bug: tmux 3.x escapes 0x1f in `-F`
  output, so the API was returning `[]` even with a valid identity.
- PR #8 moved the `route { }` wrapper from inside the snippet to *around*
  the entire site block, so `handle /api/*` (higher priority than `route`)
  doesn't preempt `forward_auth`.

After PR #8 was merged, the on-disk Caddyfile.template has 9 `route {`
occurrences but the rendered Caddyfile only has 2, and the live admin-API
config still shows the old handler order: `[reverse_proxy → 7682,
file_server, forward_auth]`. So PR #8's render didn't actually land on the
running container — `06-caddy.sh` may not have re-rendered, or Caddy
didn't pick up the new file. Diagnostic priorities:

1. `bash bootstrap/06-caddy.sh` and inspect its output; verify
   `/opt/infra/platform/caddy/Caddyfile` mtime updates and contains the
   expected `route { }` wrappers.
2. Walk the live Caddy config via `curl 127.0.0.1:2019/config/...` after
   the re-render; confirm `forward_auth` precedes `handle /api/*`.
3. If still wrong, the directive-priority theory may be incomplete; try
   replacing all the `handle` blocks with explicit `route` blocks (or move
   `/api/*` to its own subdomain like `api.<domain>` to sidestep the
   shared site block).

**Status.** Open. Direct curls to `127.0.0.1:7682/api/sessions` with a
manually-set `Remote-User: admin` header return 200 + the session list, so
session-manager and the marker logic are fine; the failure is purely in
Caddy forwarding the verified identity to `/api/*` inside the dashboard
block.

### Bubblewrap-confined shell sessions with break-out (DELIVERED 2026-05-26)

Browser shell sessions now run inside a `bwrap` jail: rootfs read-only,
homes tmpfs, only `~/workspace` writable. `sudo break` (sudo password +
Authelia TOTP) replaces the calling pane's process with an unconfined
`bash -l` via `tmux respawn-pane`. Claude sessions skip the jail (cmd=
claude → unconfined `claude`). See CHANGELOG 2026-05-26.

Implementation cleared up one design assumption: a separate "supervisor"
process turned out to be unnecessary. `tmux respawn-pane` already
spawns the new process in tmux's context (outside the bwrap), so the
pane simply *becomes* unconfined — same window, same scrollback.

### Per-app Authelia gate toggle in the dashboard

A new "Public surface" panel on the dashboard that lists every subdomain
Caddy is serving and lets the operator toggle "behind Authelia" on/off
per subdomain. Discovery via Caddy's admin API at
`127.0.0.1:2019/config/apps/http/servers/srv0/routes`. State persisted in
a new `platform/caddy/gates.yml`; toggle hits a new session-manager
endpoint that re-renders the Caddyfile, then calls
`docker exec caddy caddy reload --config /etc/caddy/Caddyfile`. Toggling
itself should require the same TOTP-from-CLI re-auth as `sudo break`
(reuses the same TOTP-validation plumbing).

**Status.** Not started. Specification draft pending.

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
