#!/usr/bin/env bash
# 11 - session-manager: the dashboard backend for the browser terminal sessions.
#
# A small standard-library Python HTTP service (platform/session-manager/
# server.py) that lets the dashboard's "Terminal sessions" section list,
# create, and stop the per-user, tmux-backed sessions ttyd serves in the
# browser. Bound to 127.0.0.1:7682; Caddy reverse-proxies the dashboard's
# /api/* routes to it, gated by Authelia.
#
# Runs as a systemd unit under the admin user — the same account as ttyd —
# so it shares that account's per-user tmux sockets and can find `tmux` and
# `claude` on PATH. No container, by the same reasoning as 07-ttyd.
#
# Installed only when the browser terminal AND the dashboard are both
# present (without the dashboard there is no page to host the session UI).
# No-op if PRIMARY_DOMAIN is unset (no Caddy to front it).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
# 07-ttyd persists WORKSPACE_ROOT to .env mid-bootstrap; reload so it is seen.
load_env

UNIT=/etc/systemd/system/session-manager.service

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping session-manager (no Caddy to front it)."
  exit 0
fi

INSTALL_SESSIONS="${INSTALL_SESSIONS:-true}"
INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
if [ "${INSTALL_SESSIONS}" != "true" ] || [ "${INSTALL_DASHBOARD}" != "true" ]; then
  log INFO "INSTALL_SESSIONS=${INSTALL_SESSIONS} INSTALL_DASHBOARD=${INSTALL_DASHBOARD}; skipping session-manager"
  systemctl disable --now session-manager.service 2>/dev/null || true
  rm -f "${UNIT}"
  systemctl daemon-reload 2>/dev/null || true
  exit 0
fi

# Resolve admin user (same logic as 07-ttyd, 09-claude-code).
ADMIN="${SERVER_ADMIN_USER:-${SUDO_USER:-}}"
if [ -z "${ADMIN}" ] || [ "${ADMIN}" = "root" ]; then
  ADMIN="$(stat -c '%U' "${INFRA_ROOT}" 2>/dev/null || true)"
fi
[ -n "${ADMIN}" ] && [ "${ADMIN}" != "root" ] || die "cannot resolve admin user"
ADMIN_HOME="$(getent passwd "${ADMIN}" | cut -d: -f6)"
[ -n "${ADMIN_HOME}" ] || die "cannot resolve home for ${ADMIN}"

# WORKSPACE_ROOT is resolved + persisted to .env by 07-ttyd, which always runs
# before this step when INSTALL_SESSIONS=true. Fall back to the same default,
# and resolve a leading ~ / relative value the same way 07-ttyd does.
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${ADMIN_HOME}/workspace}"
# shellcheck disable=SC2088
case "${WORKSPACE_ROOT}" in
  "~")    WORKSPACE_ROOT="${ADMIN_HOME}" ;;
  "~/"*)  WORKSPACE_ROOT="${ADMIN_HOME}/${WORKSPACE_ROOT:2}" ;;
  /*)     : ;;
  *)      WORKSPACE_ROOT="${ADMIN_HOME}/${WORKSPACE_ROOT}" ;;
esac
SOCKET_DIR="${ADMIN_HOME}/.terminal-sessions"
install -d -o "${ADMIN}" -g "${ADMIN}" "${WORKSPACE_ROOT}"
install -d -m 700 -o "${ADMIN}" -g "${ADMIN}" "${SOCKET_DIR}"

SERVER="${INFRA_ROOT}/platform/session-manager/server.py"
TEMPLATE="${INFRA_ROOT}/platform/session-manager/session-manager.service.template"
[ -f "${SERVER}" ]   || die "missing ${SERVER}"
[ -f "${TEMPLATE}" ] || die "missing ${TEMPLATE}"
command -v python3 >/dev/null 2>&1 || die "python3 not found (bootstrap prerequisite)"

# Render the systemd unit.
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
write_version_json "${INFRA_ROOT}/platform/session-manager" "11-session-manager"
log INFO "rendered ${UNIT} (user=${ADMIN}, workspace=${WORKSPACE_ROOT})"

systemctl daemon-reload
ensure_service session-manager.service
log INFO "session-manager up on 127.0.0.1:7682; dashboard /api/* proxies to it"
