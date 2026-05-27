#!/usr/bin/env bash
# Add an Authelia user: hash the password, append the user to the live users
# database, enrol a TOTP device, and print the enrolment QR.
#
# Usage:  sudo platform/authelia/add-user.sh <username> [displayname] [email]
#
# This is an operator tool, not a bootstrap step. It edits the LIVE
# users_database.yml (which 05-authelia.sh seeds once and never overwrites on
# re-run) and the LIVE Authelia TOTP store inside the running container.
# Authelia reloads the users file within its refresh_interval (5m); no restart
# is needed.
set -euo pipefail

INFRA_ROOT="${INFRA_ROOT:-/opt/infra}"
AUTHELIA_DIR="${INFRA_ROOT}/platform/authelia"
USERS_DB="${AUTHELIA_DIR}/users_database.yml"

die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root: sudo $0 <username> [displayname] [email]"

USERNAME="${1:-}"
[ -n "${USERNAME}" ] || die "usage: $0 <username> [displayname] [email]"
echo "${USERNAME}" | grep -qE '^[a-z_][a-z0-9_-]{0,30}$' \
  || die "username must be lowercase, start with a letter or '_', and match ^[a-z_][a-z0-9_-]{0,30}$"

DISPLAYNAME="${2:-${USERNAME}}"
EMAIL="${3:-${USERNAME}@localhost}"

[ -f "${USERS_DB}" ] || die "users database not found at ${USERS_DB}; run bootstrap first"

# Authelia must be running: the password is hashed and TOTP enrolled through it.
docker ps --format '{{.Names}}' | grep -qx authelia \
  || die "the 'authelia' container is not running; start it before adding a user"

# Refuse to touch an existing user: never silently overwrite a password or a
# TOTP secret.
if grep -qE "^[[:space:]]+${USERNAME}:[[:space:]]*\$" "${USERS_DB}"; then
  die "user '${USERNAME}' already exists in ${USERS_DB}"
fi

# Password: prompt twice, never echoed.
read -rsp "Password for '${USERNAME}': " PW1 || die "aborted"; echo
read -rsp "Confirm password: " PW2 || die "aborted"; echo
[ -n "${PW1}" ] || die "empty password"
[ "${PW1}" = "${PW2}" ] || die "passwords do not match"

# Hash with Authelia's own argon2id implementation.
HASH="$(docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password "${PW1}" 2>/dev/null \
  | awk '/^Digest:/ {print $2}')"
unset PW1 PW2
[ -n "${HASH}" ] || die "failed to hash the password via authelia/authelia"

# Append the user block. users_database.yml has a single top-level key
# 'users:'; an indented block at EOF is valid YAML. Guarantee a trailing
# newline first so the new block does not run onto the last existing line.
[ -z "$(tail -c1 "${USERS_DB}")" ] || echo >> "${USERS_DB}"
cat >> "${USERS_DB}" <<EOF
  ${USERNAME}:
    disabled: false
    displayname: "${DISPLAYNAME}"
    password: "${HASH}"
    email: "${EMAIL}"
    groups:
      - admins
EOF
echo "Added '${USERNAME}' to ${USERS_DB}."

# Enrol a TOTP device for the new user, capturing the otpauth URI it prints.
GEN_OUT="$(docker exec authelia authelia storage user totp generate "${USERNAME}" \
  --config /config/configuration.yml 2>&1)" \
  || { printf '%s\n' "${GEN_OUT}" >&2; die "TOTP enrolment failed for '${USERNAME}'"; }
URI="$(printf '%s\n' "${GEN_OUT}" | grep -oE 'otpauth://[^[:space:]]+' | head -1)"
[ -n "${URI}" ] || { printf '%s\n' "${GEN_OUT}" >&2; die "could not read the TOTP URI"; }

echo
echo "TOTP enrolment for '${USERNAME}' — have them scan this:"
echo
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ANSIUTF8 "${URI}"
  echo
fi
echo "  Setup key (manual entry, time-based, if the QR will not scan):"
echo "  ${URI}"
echo
echo "Done. Authelia picks up '${USERNAME}' within 5 minutes (refresh_interval)."
echo "They log in at https://auth.<your-domain> with the password + a TOTP code."

# If this Authelia user also happens to have a Linux home directory, deploy
# the Claude skills bundle for them. Otherwise note that the platform side
# is purely a web-auth user — to also give them a shell + skills, create a
# Linux account and re-run bootstrap/12-claude-skills.sh.
DEPLOYER="${INFRA_ROOT}/bootstrap/12-claude-skills.sh"
if [ -x "${DEPLOYER}" ] && getent passwd "${USERNAME}" >/dev/null 2>&1; then
  echo
  echo "Linux account for '${USERNAME}' detected — deploying Claude skills."
  "${DEPLOYER}"
else
  echo
  echo "Note: '${USERNAME}' is currently a web-auth user only (no Linux home)."
  echo "To deploy Claude Code skills for this user, create their Linux account"
  echo "and re-run: sudo ${DEPLOYER}"
fi
