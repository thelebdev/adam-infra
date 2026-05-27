#!/usr/bin/env bash
# 07 - ttyd: web terminal that serves per-user browser sessions.
# Reachable at sessions.<PRIMARY_DOMAIN> through Caddy (gated by Authelia).
# Binds to 127.0.0.1:7681 only. Each session runs either a login shell
# (default) or Claude Code if `claude` is installed (09-claude-code).
#
# Runs as the admin user via systemd so the PTY inherits the admin's $HOME
# and PATH. No container — keeps the moving parts small.
#
# No-op if PRIMARY_DOMAIN is unset (no public surface to attach to).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping ttyd (would have no public route anyway)."
  exit 0
fi

# Optional component: the browser terminal can be deselected at bootstrap.
INSTALL_SESSIONS="${INSTALL_SESSIONS:-true}"
if [ "${INSTALL_SESSIONS}" != "true" ]; then
  log INFO "INSTALL_SESSIONS=${INSTALL_SESSIONS}; skipping the ttyd web terminal"
  systemctl disable --now ttyd-sessions.service 2>/dev/null || true
  # Migration: also clear any pre-rename unit from earlier versions.
  systemctl disable --now ttyd-claude.service   2>/dev/null || true
  rm -f /etc/systemd/system/ttyd-sessions.service /etc/systemd/system/ttyd-claude.service
  systemctl daemon-reload 2>/dev/null || true
  exit 0
fi

# Resolve admin user (same logic as 01-user-and-ssh, 09-claude-code).
ADMIN="${SERVER_ADMIN_USER:-${SUDO_USER:-}}"
if [ -z "${ADMIN}" ] || [ "${ADMIN}" = "root" ]; then
  ADMIN="$(stat -c '%U' "${INFRA_ROOT}" 2>/dev/null || true)"
fi
[ -n "${ADMIN}" ] && [ "${ADMIN}" != "root" ] || die "cannot resolve admin user"
ADMIN_HOME="$(getent passwd "${ADMIN}" | cut -d: -f6)"
[ -n "${ADMIN_HOME}" ] || die "cannot resolve home for ${ADMIN}"

# Install ttyd + tmux from Ubuntu universe. tmux is what makes the browser
# sessions persistent: the session helper runs commands inside it, so a
# refresh or a dropped connection never kills a session.
#
# bubblewrap   — `shell` sessions run inside a bwrap jail so an accidental
#                `cd /etc; rm -rf .` from the browser doesn't reach the host.
# python3-cryptography — used by /usr/local/sbin/break to validate the
#                operator's Authelia TOTP code against the encrypted secret
#                in Authelia's SQLite store (the "TOTP gate" for break-out).
apt_ensure ttyd tmux bubblewrap python3-cryptography

# Ubuntu's ttyd package ships /usr/lib/systemd/system/ttyd.service which is
# auto-enabled and runs `ttyd -i lo -p 7681 -O login` as root — i.e. a
# password-login prompt exposed on port 7681. We replace that with our own
# unit running as the admin user, gated by Authelia. Stop+mask the default.
if systemctl list-unit-files ttyd.service >/dev/null 2>&1; then
  systemctl stop    ttyd.service 2>/dev/null || true
  systemctl disable ttyd.service 2>/dev/null || true
  systemctl mask    ttyd.service 2>/dev/null || true
  log INFO "default ttyd.service stopped + masked (replaced by ttyd-sessions.service)"
fi

# Migration: tear down the old ttyd-claude.service from before the rename.
# We do this BEFORE the new unit lands so port 7681 is free.
if systemctl list-unit-files ttyd-claude.service >/dev/null 2>&1 \
   || [ -f /etc/systemd/system/ttyd-claude.service ]; then
  systemctl stop    ttyd-claude.service 2>/dev/null || true
  systemctl disable ttyd-claude.service 2>/dev/null || true
  rm -f /etc/systemd/system/ttyd-claude.service
  systemctl daemon-reload 2>/dev/null || true
  log INFO "removed legacy ttyd-claude.service (renamed to ttyd-sessions.service)"
fi

# Install the session helper that ttyd runs in the browser terminal. It
# attaches to (or creates) per-user, per-name, workspace-confined tmux
# sessions running either a shell or claude — see platform/ttyd/session.
HELPER_SRC="${INFRA_ROOT}/platform/ttyd/session"
HELPER="${ADMIN_HOME}/.local/bin/session"
[ -f "${HELPER_SRC}" ] || die "missing ${HELPER_SRC}"
install -d -o "${ADMIN}" -g "${ADMIN}" "${ADMIN_HOME}/.local/bin"
install -m 755 -o "${ADMIN}" -g "${ADMIN}" "${HELPER_SRC}" "${HELPER}"
log INFO "installed session helper for ${ADMIN} (from ${HELPER_SRC})"
# Clean up the old helper name if present, so the admin's PATH only sees the
# new command.
rm -f "${ADMIN_HOME}/.local/bin/claude-session"

# sandbox-shell — the bwrap launcher invoked by `session` when cmd=shell.
# Lives in /usr/local/bin so any OS user can exec it (it's the entry point
# for the jail, not the privileged escape route).
SANDBOX_SRC="${INFRA_ROOT}/platform/ttyd/sandbox-shell"
[ -f "${SANDBOX_SRC}" ] || die "missing ${SANDBOX_SRC}"
install -m 755 -o root -g root "${SANDBOX_SRC}" /usr/local/bin/sandbox-shell
log INFO "installed /usr/local/bin/sandbox-shell"

# break — the TOTP-gated "exit the sandbox" helper. Lives in /usr/local/sbin
# and is exec'd by tmux via `respawn-pane` (the in-sandbox `break` shim
# triggers that). NOT invoked via sudo: bwrap's unprivileged user namespace
# makes sudo impossible inside the sandbox (PR_SET_NO_NEW_PRIVS=1 + nobody
# UID mapping). The script validates TOTP directly against the Authelia
# SQLite DB, which is readable by the admin user via group membership
# (see bootstrap/05-authelia.sh — chmod 640 root:<admin>).
BREAK_SRC="${INFRA_ROOT}/platform/ttyd/break.py"
[ -f "${BREAK_SRC}" ] || die "missing ${BREAK_SRC}"
install -m 755 -o root -g root "${BREAK_SRC}" /usr/local/sbin/break
log INFO "installed /usr/local/sbin/break"

# claude-break-out — same model as break, but execs Claude Code after the
# TOTP validation instead of dropping to bash. The in-sandbox `claude`
# shim respawns the pane with this helper; this helper validates TOTP
# and execs `bash -l -c 'exec claude'` so .profile sets up PATH for the
# admin's `~/.local/bin/claude`.
CLAUDE_BREAK_SRC="${INFRA_ROOT}/platform/ttyd/claude-break-out.py"
[ -f "${CLAUDE_BREAK_SRC}" ] || die "missing ${CLAUDE_BREAK_SRC}"
install -m 755 -o root -g root "${CLAUDE_BREAK_SRC}" /usr/local/sbin/claude-break-out
log INFO "installed /usr/local/sbin/claude-break-out"

# Ensure the in-sandbox shim sources are executable. sandbox-shell bind-
# mounts them directly from the repo (no copy elsewhere), so the +x bit
# must be set on the repo files themselves.
for shim in claude-shim break-shim; do
  SHIM_SRC="${INFRA_ROOT}/platform/ttyd/${shim}"
  [ -f "${SHIM_SRC}" ] || die "missing ${SHIM_SRC}"
  chmod 0755 "${SHIM_SRC}"
  log INFO "ensured +x on ${SHIM_SRC}"
done

# Cleanup: the old sudoers fragment (when break required `sudo`) is no
# longer used. Remove it if a previous bootstrap installed it so the
# unused rule doesn't outlive the design that needed it.
if [ -f /etc/sudoers.d/break ]; then
  rm -f /etc/sudoers.d/break
  log INFO "removed /etc/sudoers.d/break (no longer needed; break+claude use tmux respawn)"
fi

# Resolve WORKSPACE_ROOT: the directory tree that holds the projects browser
# sessions may open in. Every session is confined to this tree — it can
# never run in $HOME or above the workspace root. Defaults to ~/workspace;
# an explicit value in .env is used as-is. Persisted to .env so re-runs and
# disaster-recovery runs stay non-interactive.
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${ADMIN_HOME}/workspace}"
# A value read from .env gets no tilde expansion; expand a leading ~ and
# resolve a still-relative value against the admin home.
# shellcheck disable=SC2088
case "${WORKSPACE_ROOT}" in
  "~")    WORKSPACE_ROOT="${ADMIN_HOME}" ;;
  "~/"*)  WORKSPACE_ROOT="${ADMIN_HOME}/${WORKSPACE_ROOT:2}" ;;
  /*)     : ;;
  *)      WORKSPACE_ROOT="${ADMIN_HOME}/${WORKSPACE_ROOT}" ;;
esac
case "${WORKSPACE_ROOT}" in
  /*) : ;;
  *)  die "could not resolve WORKSPACE_ROOT to an absolute path: '${WORKSPACE_ROOT}'" ;;
esac
set_env_var WORKSPACE_ROOT "${WORKSPACE_ROOT}"
if [ -d "${WORKSPACE_ROOT}" ]; then
  log INFO "workspace root ${WORKSPACE_ROOT} already exists"
else
  install -d -o "${ADMIN}" -g "${ADMIN}" "${WORKSPACE_ROOT}"
  log INFO "created workspace root ${WORKSPACE_ROOT} (owner ${ADMIN})"
fi

# Per-user tmux sockets live here — one socket per Authelia user, so each
# user only ever sees their own sessions. 0700 so the sockets are not even
# listable by other accounts. session and the session-manager API both
# derive this path the same way (~/.terminal-sessions).
SOCKET_DIR="${ADMIN_HOME}/.terminal-sessions"
install -d -m 700 -o "${ADMIN}" -g "${ADMIN}" "${SOCKET_DIR}"
log INFO "per-user session socket dir ${SOCKET_DIR} ready"

# Migration: drop the old socket dir if it still exists. tmux servers are
# stopped above when ttyd-claude was disabled, so the .sock files are stale.
if [ -d "${ADMIN_HOME}/.claude-sessions" ]; then
  rm -rf -- "${ADMIN_HOME}/.claude-sessions"
  log INFO "removed legacy socket dir ${ADMIN_HOME}/.claude-sessions"
fi

# Render the systemd unit.
TEMPLATE="${INFRA_ROOT}/platform/ttyd/ttyd-sessions.service.template"
UNIT=/etc/systemd/system/ttyd-sessions.service
[ -f "${TEMPLATE}" ] || die "missing ${TEMPLATE}"

python3 - "${TEMPLATE}" "${UNIT}" "${ADMIN}" "${ADMIN_HOME}" \
  "${WORKSPACE_ROOT}" "${SOCKET_DIR}" "${INFRA_ROOT}" <<'PYEOF'
import sys
src, dst, user, home, workspace, sockets, infra_root = sys.argv[1:8]
content = open(src).read()
for token, value in (("__ADMIN_USER__", user), ("__ADMIN_HOME__", home),
                     ("__WORKSPACE_ROOT__", workspace),
                     ("__SOCKET_DIR__", sockets),
                     ("__INFRA_ROOT__", infra_root)):
    content = content.replace(token, value)
open(dst, "w").write(content)
PYEOF
chmod 644 "${UNIT}"
write_version_json "${INFRA_ROOT}/platform/ttyd" "07-ttyd"
log INFO "rendered ${UNIT} (user=${ADMIN}, workspace=${WORKSPACE_ROOT})"

systemctl daemon-reload
systemctl enable ttyd-sessions.service >/dev/null 2>&1 || true
systemctl restart ttyd-sessions.service
sleep 1
systemctl is-active --quiet ttyd-sessions.service || \
  log WARN "ttyd-sessions not yet active; check journalctl -u ttyd-sessions.service"
log INFO "ttyd-sessions unit installed; reachable via ${SUBDOMAIN_SESSIONS:-sessions}.${PRIMARY_DOMAIN}"
