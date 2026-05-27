#!/usr/bin/env bash
# 05 - Authelia: single-sign-on gate for everything Caddy fronts.
# Generates 3 secrets + argon2 password hash; renders configuration.yml and
# users_database.yml from templates; starts the container; prints the
# operator's TOTP enrollment QR code once.
#
# No-ops if PRIMARY_DOMAIN is unset (Caddy is also a no-op in that case).
#
# Implementation notes:
# - Secrets are written to platform/authelia/secrets/ as plain files (mode 600,
#   root-owned) and mounted into the container at /secrets:ro. Authelia reads
#   them via the *_FILE env var convention. This avoids any docker-compose
#   env interpolation surprises with the secret values.
# - Argon2 hashing is done by running authelia/authelia transiently.
# - TOTP enrollment is one-shot: this script registers the user via Authelia's
#   storage CLI and prints a QR code. The otpauth:// URI is also stashed at
#   /opt/infra/.authelia-enrollment (root, 0600) so the operator can re-scan
#   it later if needed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

if [ -z "${PRIMARY_DOMAIN:-}" ]; then
  log WARN "PRIMARY_DOMAIN unset; skipping Authelia. Dashboards reachable only via SSH port-forward."
  exit 0
fi

AUTHELIA_DIR="${INFRA_ROOT}/platform/authelia"
[ -d "${AUTHELIA_DIR}" ] || die "authelia dir ${AUTHELIA_DIR} not found"
[ -f "${AUTHELIA_DIR}/configuration.yml.template" ] || die "missing configuration.yml.template"
[ -f "${AUTHELIA_DIR}/users_database.yml.template" ] || die "missing users_database.yml.template"

# --- 1. Generate the three Authelia secrets if absent.
SECRETS_DIR="${AUTHELIA_DIR}/secrets"
install -d -m 0700 -o root -g root "${SECRETS_DIR}"
for s in jwt session storage; do
  path="${SECRETS_DIR}/${s}"
  if [ ! -s "${path}" ]; then
    openssl rand -hex 32 > "${path}"
    chmod 600 "${path}"
    log INFO "generated authelia secret: ${s}"
  fi
done

# --- 2. Ensure operator credentials in .env.
: "${AUTHELIA_USER:=admin}"
set_env_var AUTHELIA_USER "${AUTHELIA_USER}"

if [ -z "${AUTHELIA_PASSWORD:-}" ]; then
  AUTHELIA_PASSWORD="$(openssl rand -hex 16)"
  set_env_var AUTHELIA_PASSWORD "${AUTHELIA_PASSWORD}"
  log INFO "generated AUTHELIA_PASSWORD in ${INFRA_ENV_FILE} (copy to your secret store)"
fi

# --- 3. Render configuration.yml every run (stateless; picks up template edits).
EMAIL="${CADDY_ACME_EMAIL:-admin@${PRIMARY_DOMAIN}}"
SUBDOMAIN_AUTH="${SUBDOMAIN_AUTH:-auth}"
python3 - "${AUTHELIA_DIR}/configuration.yml.template" "${AUTHELIA_DIR}/configuration.yml" \
  "${PRIMARY_DOMAIN}" "${SUBDOMAIN_AUTH}" <<'PYEOF'
import sys
src, dst, domain, sub_auth = sys.argv[1:5]
content = open(src).read()
content = content.replace("__SUBDOMAIN_AUTH__", sub_auth)
content = content.replace("__PRIMARY_DOMAIN__", domain)
open(dst, "w").write(content)
PYEOF
chmod 600 "${AUTHELIA_DIR}/configuration.yml"
log INFO "rendered authelia configuration.yml (portal: ${SUBDOMAIN_AUTH}.${PRIMARY_DOMAIN})"

# --- 4. Render users_database.yml ONCE. It is the live user list: users added
# later via platform/authelia/add-user.sh must survive bootstrap re-runs, so a
# re-run must never overwrite it. AUTHELIA_PASSWORD only seeds the FIRST render;
# rotate the operator password afterwards with add-user.sh or a manual re-hash.
USERS_DB="${AUTHELIA_DIR}/users_database.yml"
if [ -f "${USERS_DB}" ]; then
  log INFO "authelia users database exists; left intact (preserves added users)"
else
  HASH="$(docker run --rm authelia/authelia:latest \
    authelia crypto hash generate argon2 --password "${AUTHELIA_PASSWORD}" 2>/dev/null \
    | awk '/^Digest:/ {print $2}')"
  [ -n "${HASH}" ] || die "failed to hash AUTHELIA_PASSWORD via authelia/authelia"
  python3 - "${AUTHELIA_DIR}/users_database.yml.template" "${USERS_DB}" \
    "${AUTHELIA_USER}" "Operator" "${EMAIL}" "${HASH}" <<'PYEOF'
import sys
src, dst, user, display, email, h = sys.argv[1:7]
content = open(src).read()
content = content.replace("__AUTHELIA_USER__", user)
content = content.replace("__AUTHELIA_DISPLAYNAME__", display)
content = content.replace("__AUTHELIA_EMAIL__", email)
content = content.replace("__AUTHELIA_PASSWORD_HASH__", h)
open(dst, "w").write(content)
PYEOF
  chmod 600 "${USERS_DB}"
  log INFO "rendered authelia users database (first run; seeded operator '${AUTHELIA_USER}')"
fi

# --- 5. Start Authelia. --force-recreate ensures the container picks up any
# changes to the bind-mounted configuration.yml / users_database.yml on re-run
# (compose doesn't detect file-mount changes by default).
log INFO "starting authelia"
docker compose \
  --project-name infra-authelia \
  -f "${AUTHELIA_DIR}/docker-compose.yml" \
  up -d --remove-orphans --force-recreate

docker compose --project-name infra-authelia \
  -f "${AUTHELIA_DIR}/docker-compose.yml" ps

# --- 6. Wait for Authelia to come up before continuing.
log INFO "waiting for authelia health endpoint"
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:9091/api/health" >/dev/null 2>&1; then
    log INFO "authelia healthy"
    break
  fi
  sleep 1
  [ "$i" -eq 30 ] && die "authelia did not come up within 30s"
done

# --- 7. TOTP enrollment for the operator (one-shot).
# Use Authelia's own storage CLI to register a TOTP device for the user.
# It generates the secret, stores it encrypted in the SQLite DB (so Authelia
# accepts it on login), and prints the otpauth URI. We capture that URI,
# stash it in a root-only file, and render a QR to the terminal.
ENROLL_FILE=/opt/infra/.authelia-enrollment
if [ -s "${ENROLL_FILE}" ]; then
  log INFO "authelia TOTP enrollment already present at ${ENROLL_FILE} (skipping)"
else
  log INFO "registering TOTP device for ${AUTHELIA_USER} via authelia storage CLI"
  set +e
  OUTPUT="$(docker compose --project-name infra-authelia \
    -f "${AUTHELIA_DIR}/docker-compose.yml" \
    exec -T authelia authelia storage user totp generate "${AUTHELIA_USER}" \
      --config /config/configuration.yml 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    # Idempotency: when re-running bootstrap after the enrollment file has
    # been removed (e.g. by `git clean -fd` — it was previously untracked),
    # Authelia's DB still holds the TOTP and `generate` refuses with
    # "already has a TOTP configuration". The authenticator app is still
    # paired and login still works — skip with a clear warning.
    if printf '%s\n' "${OUTPUT}" | grep -qiE 'already has a TOTP'; then
      log WARN "${AUTHELIA_USER} already has TOTP in Authelia's DB; ${ENROLL_FILE} is missing"
      log WARN "your existing authenticator app keeps working — no action needed"
      log WARN "to regenerate the QR/backup file (invalidates the current pairing):"
      log WARN "  docker compose --project-name infra-authelia -f ${AUTHELIA_DIR}/docker-compose.yml exec authelia authelia storage user totp generate ${AUTHELIA_USER} --force --config /config/configuration.yml"
    else
      log ERROR "authelia storage user totp generate failed:"
      printf '%s\n' "${OUTPUT}" >&2
      die "could not enroll TOTP for ${AUTHELIA_USER}"
    fi
  else
    OTPAUTH="$(printf '%s\n' "${OUTPUT}" | grep -oE 'otpauth://[^[:space:]]+' | head -1)"
    [ -n "${OTPAUTH}" ] || {
      log ERROR "could not extract otpauth URI; full CLI output:"
      printf '%s\n' "${OUTPUT}" >&2
      die "TOTP enrollment failed"
    }
    umask 077
    printf '%s\n' "${OTPAUTH}" > "${ENROLL_FILE}"
    chmod 600 "${ENROLL_FILE}"

    if command -v qrencode >/dev/null 2>&1; then
      log INFO "TOTP enrollment QR (scan into your authenticator app — 1Password, Authy, Google Authenticator):"
      echo
      qrencode -t ANSIUTF8 "${OTPAUTH}"
      echo
    else
      log WARN "qrencode not installed; otpauth URI saved at ${ENROLL_FILE}"
    fi
    log INFO "otpauth:// URI stashed at ${ENROLL_FILE} (root, 0600). Keep it safe — it is your second factor."
  fi
fi

log INFO "authelia up; will gate every subdomain under *.${PRIMARY_DOMAIN}"
