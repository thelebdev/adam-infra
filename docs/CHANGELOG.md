# Changelog

Human-readable history of infrastructure changes for this fork.

## Format

Each entry: date, mode (Maintain / Manage / Create), one-line summary.

## Entries

- **2026-05-25** — Maintain — The browser terminal stack is now
  **command-agnostic**: each session runs either a login shell (default) or
  Claude Code. The subdomain moves from `claude.<domain>` to
  `sessions.<domain>` (old subdomain dropped, no redirect). `INSTALL_CLAUDE`
  splits into two independent flags: `INSTALL_SESSIONS` (the ttyd + tmux +
  dashboard panel) and `INSTALL_CLAUDE` (the `claude` binary). The helper
  renames `claude-session` → `session` and accepts the chosen command via a
  per-session marker file written by the session-manager API; resume reads
  the marker so the dashboard, listing, and tmux all agree on what's
  running. systemd units rename `ttyd-claude.service` →
  `ttyd-sessions.service`; env vars rename `CLAUDE_WORKSPACE_ROOT/SOCKET_DIR/
  TMUX_CONF` → `SESSION_*`; the per-user socket dir moves from
  `~/.claude-sessions` to `~/.terminal-sessions`. 07-ttyd takes over
  installing the session helper from 09-claude-code (so the browser
  terminal works without the Claude binary). Migration is built into
  07-ttyd: it stops/disables the old unit and cleans up the old socket dir
  on re-run. Tests extend the existing suite with command-allowlist,
  marker round-trip, and shell-vs-claude argv coverage.
- **2026-05-23** — Create — The browser Claude terminal is now
  **multi-session and per-user**. ttyd runs the new `claude-session` helper,
  which attaches to (or creates) named, tmux-backed sessions: a browser
  refresh, a logoff, or a dropped connection no longer kills anything, and
  `claude.<domain>/?arg=<name>` opens an independent Claude in each tab. ttyd
  forwards the Authelia identity (`-H Remote-User` → `$TTYD_USER`); each user
  gets a private tmux socket and sees only their own sessions. New sessions
  are confined to `WORKSPACE_ROOT` (default `~/workspace`) — never `$HOME` or
  above it; the old single-directory `CLAUDE_WORKDIR` is retired (any value
  left in `.env` is ignored). New **session-manager** service
  (`11-session-manager.sh` — standard-library Python on `127.0.0.1:7682`)
  backs a live **Claude sessions** section on the dashboard: list, open,
  start, and stop sessions. tmux mouse mode is on, so the browser scroll
  wheel scrolls the buffer instead of walking shell history. Caddy now strips
  client-supplied `Remote-*` headers before `forward_auth` (CVE-2026-30851)
  and is pulled to the latest patched image; `ttyd-claude` and
  `session-manager` use `KillMode=process` so sessions survive a restart or a
  bootstrap re-run. First unit tests landed under `tests/infra/`.
- **2026-05-21** — Create — `bootstrap.sh` now offers to customize the
  subdomain label for each component (`SUBDOMAIN_*` flags, prompted behind a
  single yes/no gate, persisted to `.env`). `auth`, `claude`, `grafana` and
  the rest are now defaults rather than hardcoded; the Caddyfile, the Authelia
  config and the dashboard all render from the chosen labels.
- **2026-05-21** — Create — `bootstrap.sh` now prompts once for which optional
  components to install (Glances, Dozzle, ntopng, Claude, dashboard), at
  per-tool granularity. Answers persist to `.env` as `INSTALL_*` flags so
  re-runs and disaster-recovery runs are non-interactive. Each optional step,
  the Caddy routes, the dashboard tool list, and `99-verify.sh` honour the
  selection; the hardened base stays mandatory.
- **2026-05-21** — Maintain — Disabled ntopng's built-in login
  (`--disable-login=1`). Access to `ntopng.<PRIMARY_DOMAIN>` is now gated
  solely by Authelia, consistent with Dozzle and Glances. ntopng stays bound
  to `127.0.0.1`.
- **2026-05-21** — Create — Added a **platform dashboard**: a static landing
  page indexing every tool, served by Caddy at the apex domain and
  `dashboard.<PRIMARY_DOMAIN>`, gated by Authelia (new `10-dashboard.sh`
  step; apex added to Authelia's two-factor rule). The browser Claude
  session's **working directory is now configurable** — `07-ttyd.sh` prompts
  for `CLAUDE_WORKDIR` on an interactive first install, creates it, and
  persists it to `.env`. `05-authelia.sh` now renders `users_database.yml`
  **once** so users added later survive re-runs; added
  `platform/authelia/add-user.sh` to add an Authelia user (password + TOTP).
- **2026-05-20** — Maintain — Replaced Caddy HTTP basic-auth with **Authelia
  SSO + TOTP** gating every subdomain via Caddy `forward_auth`. Added **ttyd**
  serving Claude Code in a browser tab at `claude.<PRIMARY_DOMAIN>` (gated
  by Authelia). Bootstrap renumbered to fit the new gate-first ordering:
  `00 prereq → 01 user/ssh → 02 firewall → 03 kernel → 04 docker → 05 authelia → 06 caddy → 07 ttyd → 08 observability → 09 claude-code → 99 verify`.
  `qrencode` added to prerequisites; TOTP enrollment QR printed once at
  bootstrap and stashed at `/opt/infra/.authelia-enrollment`.
