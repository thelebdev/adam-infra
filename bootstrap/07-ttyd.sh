#!/usr/bin/env bash
# 07 - ttyd: web terminal that serves Claude Code in a browser tab.
# Reachable at claude.<PRIMARY_DOMAIN> through Caddy (gated by Authelia).
# Binds to 127.0.0.1:7681 only.
#
# Runs as the admin user via systemd so the PTY inherits the admin's $HOME,
# PATH, and access to claude / claude-session. No container — keeps the
# stack of moving parts small.
#
# No-op if PRIMARY_DOMAIN is unset (no public surface to attach to).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping ttyd (would have no public route anyway)."
  exit 0
fi

# Optional component: the browser terminal can be deselected at bootstrap.
INSTALL_CLAUDE="${INSTALL_CLAUDE:-true}"
if [ "${INSTALL_CLAUDE}" != "true" ]; then
  log INFO "INSTALL_CLAUDE=${INSTALL_CLAUDE}; skipping the ttyd web terminal"
  systemctl disable --now ttyd-claude.service 2>/dev/null || true
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
# sessions persistent: claude-session runs Claude inside it, so a refresh or
# a dropped connection never kills a session.
apt_ensure ttyd tmux

# Ubuntu's ttyd package ships /usr/lib/systemd/system/ttyd.service which is
# auto-enabled and runs `ttyd -i lo -p 7681 -O login` as root — i.e. a
# password-login prompt exposed on port 7681. We replace that with our own
# unit running as the admin user, gated by Authelia. Stop+mask the default.
if systemctl list-unit-files ttyd.service >/dev/null 2>&1; then
  systemctl stop    ttyd.service 2>/dev/null || true
  systemctl disable ttyd.service 2>/dev/null || true
  systemctl mask    ttyd.service 2>/dev/null || true
  log INFO "default ttyd.service stopped + masked (replaced by ttyd-claude.service)"
fi

# Sanity: claude-session helper should exist (09-claude-code installs it).
# But on first bootstrap 07 runs BEFORE 09 — so it may not be there yet.
# That's fine; the service will retry on Restart=on-failure once 09 lands it.
if [ ! -x "${ADMIN_HOME}/.local/bin/claude-session" ]; then
  log INFO "claude-session not yet present at ${ADMIN_HOME}/.local/bin/ — 09-claude-code installs it"
fi

# Resolve WORKSPACE_ROOT: the directory tree that holds the projects browser
# Claude sessions may open in. Every session is confined to this tree — it
# can never run in $HOME or above the workspace root. Defaults to
# ~/workspace; an explicit value in .env is used as-is. Persisted to .env so
# re-runs and disaster-recovery runs stay non-interactive.
#
# CLAUDE_WORKDIR — the single fixed directory used before per-session
# directories existed — is obsolete. Any existing value is left untouched in
# .env and simply ignored.
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
# listable by other accounts. claude-session and the session-manager API
# both derive this path the same way (~/.claude-sessions).
SOCKET_DIR="${ADMIN_HOME}/.claude-sessions"
install -d -m 700 -o "${ADMIN}" -g "${ADMIN}" "${SOCKET_DIR}"
log INFO "per-user session socket dir ${SOCKET_DIR} ready"

# Render the systemd unit.
TEMPLATE="${INFRA_ROOT}/platform/ttyd/ttyd-claude.service.template"
UNIT=/etc/systemd/system/ttyd-claude.service
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
log INFO "rendered ${UNIT} (user=${ADMIN}, workspace=${WORKSPACE_ROOT})"

systemctl daemon-reload
systemctl enable ttyd-claude.service >/dev/null 2>&1 || true
systemctl restart ttyd-claude.service
# Give it a moment; restart=on-failure handles the case where claude-session
# isn't installed yet (first bootstrap, before step 09).
sleep 1
systemctl is-active --quiet ttyd-claude.service || \
  log WARN "ttyd-claude not yet active (likely waiting for 09-claude-code to install claude-session); will retry on restart"
log INFO "ttyd-claude unit installed; reachable via ${SUBDOMAIN_CLAUDE:-claude}.${PRIMARY_DOMAIN} after 09-claude-code lands"
