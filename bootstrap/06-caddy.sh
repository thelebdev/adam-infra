#!/usr/bin/env bash
# 06 - Caddy reverse proxy. Terminates TLS for everything served on
# *.PRIMARY_DOMAIN and consults Authelia (started by 05-authelia.sh) on every
# request via forward_auth.
#
# Caddy obtains and renews Let's Encrypt certs automatically for each
# subdomain referenced in the rendered Caddyfile.
#
# If PRIMARY_DOMAIN is unset this step is a no-op — dashboards are reachable
# only via SSH port-forward, and Authelia is also skipped.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping Caddy. Dashboards reachable only via SSH port-forward."
  exit 0
fi
require_env CADDY_ACME_EMAIL

CADDY_DIR="${INFRA_ROOT}/platform/caddy"
[ -d "${CADDY_DIR}" ] || die "caddy dir ${CADDY_DIR} not found"
[ -f "${CADDY_DIR}/Caddyfile.template" ] || die "missing ${CADDY_DIR}/Caddyfile.template"

# Render Caddyfile.template -> Caddyfile with literal string replacement.
# Component selection: strip the Caddy server block for anything not installed
# so Caddy never advertises a dead route or fetches an unused certificate.
INSTALL_SESSIONS="${INSTALL_SESSIONS:-true}"
INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
INSTALL_DOZZLE="${INSTALL_DOZZLE:-true}"
INSTALL_GLANCES="${INSTALL_GLANCES:-true}"
INSTALL_NTOPNG="${INSTALL_NTOPNG:-true}"
PROFILE="${OBSERVABILITY_PROFILE:-lightweight}"
disabled=""
[ "${INSTALL_SESSIONS}"  = "true" ] || disabled="${disabled},sessions"
[ "${INSTALL_DASHBOARD}" = "true" ] || disabled="${disabled},dashboard"
# The /api route inside the dashboard block (component:sessions-api) exists
# only when both the dashboard (to host the page) and the sessions stack
# (to have sessions to manage) are installed.
if [ "${INSTALL_SESSIONS}" != "true" ] || [ "${INSTALL_DASHBOARD}" != "true" ]; then
  disabled="${disabled},sessions-api"
fi
# Glances/Dozzle/ntopng exist only on the lightweight profile.
if [ "${PROFILE}" = "lightweight" ]; then
  [ "${INSTALL_DOZZLE}"  = "true" ] || disabled="${disabled},dozzle"
  [ "${INSTALL_GLANCES}" = "true" ] || disabled="${disabled},glances"
  [ "${INSTALL_NTOPNG}"  = "true" ] || disabled="${disabled},ntopng"
else
  disabled="${disabled},dozzle,glances,ntopng"
fi
# Grafana exists only on the full profile.
[ "${PROFILE}" = "full" ] || disabled="${disabled},grafana"

# Resolve subdomain labels (default to the conventional names).
SUBDOMAIN_AUTH="${SUBDOMAIN_AUTH:-auth}"
SUBDOMAIN_DASHBOARD="${SUBDOMAIN_DASHBOARD:-dashboard}"
SUBDOMAIN_SESSIONS="${SUBDOMAIN_SESSIONS:-sessions}"
SUBDOMAIN_DOZZLE="${SUBDOMAIN_DOZZLE:-dozzle}"
SUBDOMAIN_GLANCES="${SUBDOMAIN_GLANCES:-glances}"
SUBDOMAIN_NTOPNG="${SUBDOMAIN_NTOPNG:-ntopng}"
SUBDOMAIN_GRAFANA="${SUBDOMAIN_GRAFANA:-grafana}"
subs="AUTH=${SUBDOMAIN_AUTH},DASHBOARD=${SUBDOMAIN_DASHBOARD},SESSIONS=${SUBDOMAIN_SESSIONS}"
subs="${subs},DOZZLE=${SUBDOMAIN_DOZZLE},GLANCES=${SUBDOMAIN_GLANCES}"
subs="${subs},NTOPNG=${SUBDOMAIN_NTOPNG},GRAFANA=${SUBDOMAIN_GRAFANA}"

CADDYFILE="${CADDY_DIR}/Caddyfile"
python3 - "${CADDY_DIR}/Caddyfile.template" "${CADDYFILE}" \
  "${PRIMARY_DOMAIN}" "${CADDY_ACME_EMAIL}" "${disabled}" "${subs}" <<'PYEOF'
import re, sys
src, dst, domain, email, disabled, subs = sys.argv[1:7]
content = open(src).read()
for comp in (c for c in disabled.split(",") if c):
    content = re.sub(
        r"# >>>component:%s\b.*?# <<<component:%s\b[^\n]*\n" % (comp, comp),
        "", content, flags=re.S)
# Drop the component markers around the blocks that were kept.
content = re.sub(r"^# (?:>>>|<<<)component:[^\n]*\n", "", content, flags=re.M)
for pair in subs.split(","):
    key, val = pair.split("=", 1)
    content = content.replace("__SUBDOMAIN_%s__" % key, val)
content = content.replace("__PRIMARY_DOMAIN__", domain)
content = content.replace("__CADDY_ACME_EMAIL__", email)
open(dst, "w").write(content)
PYEOF
chmod 644 "${CADDYFILE}"
log INFO "rendered ${CADDYFILE} (disabled blocks:${disabled:-none})"

# Strip any legacy Caddy basic-auth secrets from /opt/infra/.env — Authelia
# replaces them. Idempotent: noop if absent.
for k in CADDY_BASIC_AUTH_USER CADDY_BASIC_AUTH_PASSWORD CADDY_BASIC_AUTH_HASH; do
  if grep -q "^${k}=" "${INFRA_ENV_FILE}" 2>/dev/null; then
    tmp="$(mktemp)"
    grep -v "^${k}=" "${INFRA_ENV_FILE}" > "${tmp}"
    mv "${tmp}" "${INFRA_ENV_FILE}"
    chmod 600 "${INFRA_ENV_FILE}"
    log INFO "stripped legacy ${k} from ${INFRA_ENV_FILE} (Authelia replaces basic-auth)"
  fi
done
rm -f "${CADDY_DIR}/.basicauth.env"

log INFO "starting caddy (domain=${PRIMARY_DOMAIN})"
# Pull the latest caddy:2 image so re-runs pick up patch releases — notably
# the forward_auth header-spoofing fix (>= v2.11.2, CVE-2026-30851). The
# Caddyfile already strips client-supplied identity headers, so this is the
# belt to that suspenders, not the sole defence.
docker compose --project-name infra-caddy \
  -f "${CADDY_DIR}/docker-compose.yml" pull --quiet 2>/dev/null || \
  log WARN "caddy image pull failed; continuing with the cached image"
# --force-recreate so a re-run picks up changes to the bind-mounted Caddyfile
# (compose does not detect file-mount content changes on its own).
docker compose \
  --project-name infra-caddy \
  -f "${CADDY_DIR}/docker-compose.yml" \
  up -d --remove-orphans --force-recreate

docker compose --project-name infra-caddy \
  -f "${CADDY_DIR}/docker-compose.yml" ps
log INFO "caddy up for ${PRIMARY_DOMAIN}; the ${SUBDOMAIN_AUTH} portal is open, all other subdomains gated by authelia"
