# Changelog

Human-readable history of infrastructure changes for this fork.

## Format

Each entry: date, mode (Maintain / Manage / Create), one-line summary.

## Entries

- **2026-05-27** — Create — **Drag-and-drop file upload into browser
  sessions.** New `POST /api/upload` on the session-manager service
  accepts multipart bodies up to 25 MiB and writes them to
  `~/workspace/uploads/<authelia-user>/<unix-ts>-<safe-filename>`. The
  /m/ wrapper grows three input paths into that endpoint:
  (1) a `+` toolbar button that opens the OS file picker (Photos /
  Files on iOS, Gallery / Files on Android, Finder on macOS, etc.);
  (2) drag-and-drop onto the page on desktop, with a translucent overlay
  while the file is in the air; (3) clipboard paste of an image —
  handy when you screenshot something on mobile and want to drop it
  straight into a session. On success a toast surfaces the absolute path
  with **Copy path** and **Send to terminal** buttons. The second one
  types `@<path> ` into the active session, which Claude Code reads as
  an attached file. Caddy gains a `/api/*` route on `sessions.<domain>`
  alongside the existing one on `dashboard.<domain>` so the wrapper
  can hit the API same-origin without CORS.

- **2026-05-27** — Maintain — **One-tap toggle to select-and-copy text from
  the browser terminal.** Tmux mouse mode is on by default — great for
  scrollback, but it owns click-drag, so text "selected" with the mouse
  goes to tmux's buffer instead of being highlighted in the browser the
  way it would be on any other web page. The fix is a tmux binding
  `prefix C-s` that flips mouse mode, with a status-bar confirmation of
  the new state. On desktop the operator types `Ctrl-b Ctrl-s` and then
  drags to select / Cmd-C to copy. On mobile the /m/ wrapper exposes a
  "Sel" toolbar button that sends the same sequence — one tap and
  long-press → Copy works like any iOS/Android web page. Tap "Sel"
  again to put mouse mode back on for scrolling.

- **2026-05-27** — Create — **Mobile-friendly browser sessions.** Mobile
  user agents hitting `sessions.<domain>/` are 302'd to a static wrapper
  at `/m/` that iframes ttyd and overlays a CLI key bar — Esc, Tab,
  arrows, sticky Ctrl modifier, ^C/^D/^R/^U/^W/^Z/^L, Home/End, PgUp/PgDn,
  and the punctuation that mobile keyboards bury two taps deep
  (`|` `~` `/` `-` `_` `$` `*` `&` `#`). The wrapper also patches
  xterm.js's hidden helper textarea on load to disable iOS/Android
  first-letter capitalization, autocorrect, autocomplete and spellcheck —
  the things that turned `ls` into `Ls` and `cd ..` into `cd…`. Desktop
  UAs see the unmodified ttyd at `/`; the redirect is UA-gated. Adds
  `platform/caddy/sessions-mobile/index.html`, a `secure_headers_sessions`
  Caddy snippet (X-Frame-Options SAMEORIGIN so the same-origin iframe
  loads), and a bind-mount of the new dir into the Caddy container.

- **2026-05-26** — Create — **Sandboxed shell sessions with TOTP-gated
  break-out.** Browser shell sessions now run inside a `bubblewrap` jail
  by default. The jail mounts the host root read-only, hides every
  user's home with a tmpfs, and bind-mounts only `~/workspace` writable.
  Accidental `cd /etc; rm -rf .` from the browser can't reach the host;
  SSH keys at `~/.ssh`, GPG keys at `~/.gnupg`, secrets at `~/.config`
  are invisible from inside.
  
  The escape valve is `sudo break`, with two factors required:
  1. The operator's host sudo password (forced every invocation via
     `Defaults!break timestamp_timeout=0` so a stale 5-minute sudo cache
     can never substitute).
  2. A fresh 6-digit Authelia TOTP code, validated locally against the
     encrypted secret in Authelia's SQLite store (AES-256-GCM with
     SHA-256(storage_key) as the key — same encryption Authelia itself
     uses on login).
  
  On success, `break` invokes `tmux respawn-pane` to replace the calling
  pane's process with an unconfined `bash -l`. The replacement is spawned
  by tmux (outside the jail), so the pane *becomes* unconfined — same
  window, same scrollback, no new tab.
  
  Claude sessions (cmd=claude) deliberately skip the jail: Claude needs
  `~/.claude/credentials.json`, git config, ssh keys, and write access to
  project files. Bind-mounting every one would defeat the point. The
  dashboard's command picker still defaults to "shell" — Claude is opt-in.
  
  New files: `platform/ttyd/sandbox-shell` (bwrap launcher),
  `platform/ttyd/break.py` (TOTP-gated breakout),
  `platform/ttyd/break.sudoers.template`. 07-ttyd.sh now
  `apt_ensure`s `bubblewrap` + `python3-cryptography`, installs the
  helpers, and renders + validates (`visudo -cf`) the sudoers fragment
  before moving it into place. 15 new break.py unit tests cover the
  TOTP arithmetic (RFC 6238 vectors, ±1 window skew tolerance, input
  validation, username resolution order).
- **2026-05-26** — Maintain — **Version surface + standalone-safe render
  steps.** Two related changes that together prevent a silent failure
  mode: a merged commit doesn't match the live config because a render
  step didn't actually run. Each render script (`06-caddy`, `07-ttyd`,
  `10-dashboard`, `11-session-manager`) now stamps a sibling
  `.version.json` next to its artifact via the new `write_version_json`
  helper in `lib/common.sh`. The session-manager API exposes
  `GET /api/version` (unauthenticated): current git HEAD plus each
  component's last-render sha and timestamp plus a `drift` flag. The
  dashboard footer shows the rendered versions inline and a yellow
  drift banner above the footer if anything's stale. Separately,
  numbered scripts that read `.env` (05, 06, 07, 09, 10, 01, 02, 08)
  now self-`load_env` so they're safe to run via
  `sudo bash bootstrap/0X-thing.sh` directly — sudo otherwise strips
  the parent shell's env, the script sees `PRIMARY_DOMAIN=""` and
  silently exits via the early-skip branch (the bug that left the
  Caddyfile stale after the per-app gate fix in PR #8).
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
