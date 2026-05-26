#!/usr/bin/env bash
# 08 - observability stack. Profile-selectable:
#   lightweight (default) -> Glances + Dozzle + ntopng  (fits ~1 GiB RAM)
#   full                  -> Loki + Prometheus + Grafana (>= 2 GiB RAM)
# On the lightweight profile each tool is individually selectable via the
# INSTALL_GLANCES / INSTALL_DOZZLE / INSTALL_NTOPNG flags; the full profile is
# all-or-nothing (its services are interdependent).
# All UIs bind ONLY to 127.0.0.1 on the host. They are reached from outside
# through the Caddy reverse proxy (06-caddy.sh), gated by Authelia.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

PROFILE="${OBSERVABILITY_PROFILE:-lightweight}"
COMPOSE_DIR="${INFRA_ROOT}/platform/observability"
PROJECT=infra-observability
[ -d "${COMPOSE_DIR}" ] || die "compose dir ${COMPOSE_DIR} not found (is the repo at ${INFRA_ROOT}?)"

# Generate any missing dashboard secrets ON THE SERVER. Never printed to logs.
# Operator copies them from ${INFRA_ENV_FILE} into their own secret store.
gen_secret() {
  local key="$1"
  local cur; cur="$(grep -m1 "^${key}=" "${INFRA_ENV_FILE}" 2>/dev/null | cut -d= -f2-)"
  [ -n "${cur}" ] && return 0
  local val; val="$(openssl rand -hex 24)"
  if grep -q "^${key}=" "${INFRA_ENV_FILE}" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "${INFRA_ENV_FILE}"
  else
    echo "${key}=${val}" >> "${INFRA_ENV_FILE}"
  fi
  log INFO "generated ${key} into ${INFRA_ENV_FILE} (copy to your secret store)"
}

# --- Full profile: all-or-nothing (Loki/Prometheus/Grafana are interdependent).
if [ "${PROFILE}" = "full" ]; then
  gen_secret GRAFANA_ADMIN_PASSWORD
  COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.full.yml"
  log INFO "deploying observability profile=full (all services)"
  docker compose --project-name "${PROJECT}" --env-file "${INFRA_ENV_FILE}" \
    -f "${COMPOSE_FILE}" up -d --remove-orphans
  docker compose --project-name "${PROJECT}" -f "${COMPOSE_FILE}" ps
  log INFO "observability profile=full up"
  exit 0
fi

[ "${PROFILE}" = "lightweight" ] \
  || die "unknown OBSERVABILITY_PROFILE='${PROFILE}' (expected: lightweight|full)"

# --- Lightweight profile: per-tool selection.
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.lightweight.yml"
INSTALL_GLANCES="${INSTALL_GLANCES:-true}"
INSTALL_DOZZLE="${INSTALL_DOZZLE:-true}"
INSTALL_NTOPNG="${INSTALL_NTOPNG:-true}"

dc() {
  docker compose --project-name "${PROJECT}" --env-file "${INFRA_ENV_FILE}" \
    -f "${COMPOSE_FILE}" "$@"
}

want=""
[ "${INSTALL_GLANCES}" = "true" ] && want="${want} glances"
[ "${INSTALL_DOZZLE}"  = "true" ] && want="${want} dozzle"
[ "${INSTALL_NTOPNG}"  = "true" ] && want="${want} ntopng ntopng-redis"

if [ -z "${want}" ]; then
  log INFO "no observability tools selected; tearing the stack down"
  dc down --remove-orphans 2>/dev/null || true
  log INFO "observability: nothing installed (all tools deselected)"
  exit 0
fi

log INFO "deploying observability (lightweight); selected:${want}"
# shellcheck disable=SC2086
dc up -d --remove-orphans ${want}

# Remove any tool defined in the compose file but not selected, so a re-run
# with a changed selection actually reflects it.
for svc in glances dozzle ntopng ntopng-redis; do
  case " ${want} " in
    *" ${svc} "*) : ;;
    *) dc rm -sf "${svc}" >/dev/null 2>&1 || true ;;
  esac
done

dc ps
log INFO "observability (lightweight) up; selected:${want}"
