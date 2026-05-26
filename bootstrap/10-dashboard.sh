#!/usr/bin/env bash
# 10 - platform dashboard: a static landing page indexing every tool the
# platform exposes. Rendered from a template and served by Caddy (file_server)
# at the apex domain and <SUBDOMAIN_DASHBOARD>.<PRIMARY_DOMAIN>, gated by
# Authelia.
#
# The page lists only the tools actually installed (per the INSTALL_* flags),
# each at whatever subdomain label was chosen (the SUBDOMAIN_* flags).
# No-op if PRIMARY_DOMAIN is unset, or if INSTALL_DASHBOARD is not "true".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

DASH_DIR="${INFRA_ROOT}/platform/dashboard"
TEMPLATE="${DASH_DIR}/index.html.template"
OUT="${DASH_DIR}/index.html"

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping dashboard (no Caddy to serve it)."
  exit 0
fi

INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
if [ "${INSTALL_DASHBOARD}" != "true" ]; then
  log INFO "INSTALL_DASHBOARD=${INSTALL_DASHBOARD}; skipping the dashboard"
  rm -f "${OUT}"
  exit 0
fi

[ -f "${TEMPLATE}" ] || die "missing ${TEMPLATE}"

PROFILE="${OBSERVABILITY_PROFILE:-lightweight}"
INSTALL_SESSIONS="${INSTALL_SESSIONS:-true}"
INSTALL_DOZZLE="${INSTALL_DOZZLE:-true}"
INSTALL_GLANCES="${INSTALL_GLANCES:-true}"
INSTALL_NTOPNG="${INSTALL_NTOPNG:-true}"
SUBDOMAIN_AUTH="${SUBDOMAIN_AUTH:-auth}"
SUBDOMAIN_DASHBOARD="${SUBDOMAIN_DASHBOARD:-dashboard}"
SUBDOMAIN_SESSIONS="${SUBDOMAIN_SESSIONS:-sessions}"
SUBDOMAIN_DOZZLE="${SUBDOMAIN_DOZZLE:-dozzle}"
SUBDOMAIN_GLANCES="${SUBDOMAIN_GLANCES:-glances}"
SUBDOMAIN_NTOPNG="${SUBDOMAIN_NTOPNG:-ntopng}"
SUBDOMAIN_GRAFANA="${SUBDOMAIN_GRAFANA:-grafana}"

# Emit one tool card. __PRIMARY_DOMAIN__ is substituted by the render below.
mkcard() {
  printf '<a class="card" href="https://%s.__PRIMARY_DOMAIN__"><span class="card-name">%s</span><span class="card-desc">%s</span><span class="card-host">%s.__PRIMARY_DOMAIN__</span></a>' \
    "$1" "$2" "$3" "$1"
}

# Base URL the dashboard's "Terminal sessions" section links to (the per-row
# "Open" buttons point browsers at sessions.<domain>/?arg=<session>).
SESSIONS_BASE_URL="https://${SUBDOMAIN_SESSIONS}.${PRIMARY_DOMAIN}"
SESSIONS_CARD=""
[ "${INSTALL_SESSIONS}" = "true" ] && SESSIONS_CARD="$(mkcard "${SUBDOMAIN_SESSIONS}" 'Terminal sessions' 'Browser terminal — open or start a session')"
# Glances/Dozzle/ntopng exist only on the lightweight profile.
DOZZLE_CARD=""
GLANCES_CARD=""
NTOPNG_CARD=""
if [ "${PROFILE}" = "lightweight" ]; then
  [ "${INSTALL_DOZZLE}"  = "true" ] && DOZZLE_CARD="$(mkcard "${SUBDOMAIN_DOZZLE}" 'Dozzle' 'Live container logs')"
  [ "${INSTALL_GLANCES}" = "true" ] && GLANCES_CARD="$(mkcard "${SUBDOMAIN_GLANCES}" 'Glances' 'Host metrics: CPU, memory, disk')"
  [ "${INSTALL_NTOPNG}"  = "true" ] && NTOPNG_CARD="$(mkcard "${SUBDOMAIN_NTOPNG}" 'ntopng' 'Network traffic and flows')"
fi
GRAFANA_CARD=""
[ "${PROFILE}" = "full" ] && GRAFANA_CARD="$(mkcard "${SUBDOMAIN_GRAFANA}" 'Grafana' 'Metrics and log dashboards')"

python3 - "${TEMPLATE}" "${OUT}" "${PRIMARY_DOMAIN}" "${SUBDOMAIN_AUTH}" \
  "${SESSIONS_CARD}" "${DOZZLE_CARD}" "${GLANCES_CARD}" "${NTOPNG_CARD}" "${GRAFANA_CARD}" \
  "${INSTALL_SESSIONS}" "${SESSIONS_BASE_URL}" <<'PYEOF'
import re, sys
(src, dst, domain, sub_auth, sessions, dozzle, glances, ntopng, grafana,
 install_sessions, sessions_url) = sys.argv[1:12]
content = open(src).read()
# The dynamic "Terminal sessions" section only works when the sessions stack
# (ttyd + session-manager API) is installed. Keep it and drop just the marker
# comments, or strip the whole marked region otherwise.
if install_sessions == "true":
    content = re.sub(r"[ \t]*<!-- (?:>>>|<<<)sessions -->[ \t]*\n", "", content)
else:
    content = re.sub(
        r"[ \t]*<!-- >>>sessions -->.*?<!-- <<<sessions -->[ \t]*\n",
        "", content, flags=re.S)
for token, card in (("__SESSIONS_CARD__", sessions),
                    ("__DOZZLE_CARD__", dozzle),
                    ("__GLANCES_CARD__", glances), ("__NTOPNG_CARD__", ntopng),
                    ("__GRAFANA_CARD__", grafana)):
    content = content.replace(token, card)
content = content.replace("__SESSIONS_BASE_URL__", sessions_url)
content = content.replace("__SUBDOMAIN_AUTH__", sub_auth)
content = content.replace("__PRIMARY_DOMAIN__", domain)
open(dst, "w").write(content)
PYEOF
chmod 644 "${OUT}"
write_version_json "${DASH_DIR}" "10-dashboard"
log INFO "rendered platform dashboard -> ${OUT} (profile=${PROFILE})"
log INFO "dashboard served by Caddy at https://${PRIMARY_DOMAIN} and https://${SUBDOMAIN_DASHBOARD}.${PRIMARY_DOMAIN}"
