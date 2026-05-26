#!/usr/bin/env bash
# Shared helpers for all bootstrap scripts.
# Sourced, never executed directly. Every function is idempotent-safe.

set -euo pipefail

INFRA_ROOT="${INFRA_ROOT:-/opt/infra}"
INFRA_LOG_DIR="${INFRA_LOG_DIR:-/var/log/infra}"
INFRA_ENV_FILE="${INFRA_ENV_FILE:-${INFRA_ROOT}/.env}"

# Structured log line to stdout and to a per-script logfile.
# Usage: log INFO "message"
log() {
  local level="$1"; shift
  local script="${INFRA_CURRENT_SCRIPT:-bootstrap}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"script\":\"${script}\",\"msg\":\"$*\"}"
  echo "${line}"
  mkdir -p "${INFRA_LOG_DIR}"
  echo "${line}" >> "${INFRA_LOG_DIR}/${script}.log"
}

die() { log ERROR "$*"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo -i, then run bootstrap.sh)"
}

# Load INFRA_ENV_FILE into the environment if present. Never echoes values.
load_env() {
  if [ -f "${INFRA_ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${INFRA_ENV_FILE}"
    set +a
    log INFO "loaded env from ${INFRA_ENV_FILE}"
  else
    log WARN "no .env at ${INFRA_ENV_FILE}; proceeding with environment as-is"
  fi
}

# Require a non-empty env var. Names the var; never prints the value.
require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || die "required env var ${name} is not set (see .env.example)"
}

# Idempotent apt install: only installs packages not already present.
apt_ensure() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    log INFO "apt: all present (${*})"
    return 0
  fi
  log INFO "apt: installing ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
}

# Ensure an exact line exists in a file (idempotent). Creates the file if absent.
ensure_line() {
  local line="$1" file="$2"
  touch "${file}"
  grep -qxF "${line}" "${file}" || echo "${line}" >> "${file}"
}

# Replace (or append) a KEY=VALUE line in INFRA_ENV_FILE. Idempotent; the file
# is created if absent. Never echoes the value.
set_env_var() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  if [ -f "${INFRA_ENV_FILE}" ]; then
    grep -v "^${key}=" "${INFRA_ENV_FILE}" > "${tmp}" || true
  fi
  printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
  mv "${tmp}" "${INFRA_ENV_FILE}"
  chmod 600 "${INFRA_ENV_FILE}"
}

# Enable + start a systemd unit idempotently.
ensure_service() {
  local unit="$1"
  systemctl enable "${unit}" >/dev/null 2>&1 || true
  systemctl restart "${unit}"
  systemctl is-active --quiet "${unit}" || die "service ${unit} failed to start"
  log INFO "service ${unit} active"
}

# Drop a `.version.json` sentinel next to a rendered artifact. The dashboard
# reads these via /api/version to surface drift between the current git HEAD
# and what was last rendered — the failure mode where a merged commit doesn't
# match the live config is otherwise invisible.
#
# Usage: write_version_json <dir> <by>
write_version_json() {
  local dir="$1" by="$2" sha ts
  sha="$(git -C "${INFRA_ROOT}" rev-parse --short=10 HEAD 2>/dev/null || echo unknown)"
  if [ "${sha}" != "unknown" ] && \
     ! { git -C "${INFRA_ROOT}" diff --quiet 2>/dev/null && \
         git -C "${INFRA_ROOT}" diff --cached --quiet 2>/dev/null; }; then
    sha="${sha}-dirty"
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  install -d "${dir}"
  cat > "${dir}/.version.json" <<EOF
{"git_sha":"${sha}","rendered_at":"${ts}","by":"${by}"}
EOF
  chmod 644 "${dir}/.version.json"
  log INFO "stamped ${dir}/.version.json (sha=${sha}, by=${by})"
}
