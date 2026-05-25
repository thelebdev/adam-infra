#!/usr/bin/env bash
# 99 - post-bootstrap health checks. Non-destructive. Exits non-zero on failure.
# Component checks are gated by the INSTALL_* flags: only what was actually
# installed is asserted.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

INSTALL_SESSIONS="${INSTALL_SESSIONS:-true}"
INSTALL_CLAUDE="${INSTALL_CLAUDE:-true}"
INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
INSTALL_GLANCES="${INSTALL_GLANCES:-true}"
INSTALL_DOZZLE="${INSTALL_DOZZLE:-true}"
INSTALL_NTOPNG="${INSTALL_NTOPNG:-true}"

fail=0
check() { if eval "$2" >/dev/null 2>&1; then log INFO "OK: $1"; else log ERROR "FAIL: $1"; fail=1; fi; }

check "ufw active"               'ufw status | grep -q "Status: active"'
check "ssh rate-limited"         'ufw status | grep -E "^22/tcp\s+LIMIT"'
check "fail2ban active"          'systemctl is-active --quiet fail2ban'
check "docker active"            'systemctl is-active --quiet docker'

# Authelia + Caddy are only deployed when PRIMARY_DOMAIN is set.
if [ -n "${PRIMARY_DOMAIN:-}" ]; then
  check "authelia container running" 'docker ps --format "{{.Names}}" | grep -qx authelia'
  check "authelia health endpoint"   'curl -sf http://127.0.0.1:9091/api/health'
  check "caddy container running"    'docker ps --format "{{.Names}}" | grep -qx caddy'
  if [ "${INSTALL_SESSIONS}" = "true" ]; then
    check "ttyd-sessions service active" 'systemctl is-active --quiet ttyd-sessions.service'
  fi
  if [ "${INSTALL_DASHBOARD}" = "true" ]; then
    check "dashboard page rendered"    'test -f "${INFRA_ROOT}/platform/dashboard/index.html"'
  fi
  if [ "${INSTALL_SESSIONS}" = "true" ] && [ "${INSTALL_DASHBOARD}" = "true" ]; then
    check "session-manager service active" 'systemctl is-active --quiet session-manager.service'
    check "session-manager API healthy"    'curl -sf http://127.0.0.1:7682/api/health'
  fi
else
  log INFO "SKIP: authelia/caddy/ttyd checks (PRIMARY_DOMAIN unset; intentionally not deployed)"
fi

if [ "${INSTALL_CLAUDE}" = "true" ]; then
  check "claude code installed"    'sudo -u "${SERVER_ADMIN_USER:-${SUDO_USER}}" bash -lc "command -v claude"'
fi

# Dashboards must NOT be on the public interface. Caddy front-doors them.
check "dashboards bound to localhost only" "! ss -tlnp | grep -E '0\.0\.0\.0:(3000|8080|61208|3001|7681|7682|9091)\b'"

if [ "${INSTALL_GLANCES}" = "true" ] || [ "${INSTALL_DOZZLE}" = "true" ] || [ "${INSTALL_NTOPNG}" = "true" ]; then
  check "observability containers up" 'docker ps -q --filter "label=com.docker.compose.project=infra-observability" --filter "status=running" | grep -q .'
else
  log INFO "SKIP: observability containers (all observability tools deselected)"
fi

[ "${fail}" -eq 0 ] && log INFO "verify: all checks passed" || die "verify: one or more checks FAILED"
