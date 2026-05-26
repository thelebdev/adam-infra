#!/usr/bin/env bash
# 01 - admin user + SSH hardening (key-only, no root login).
# Safe: refuses to disable password auth unless the admin user already has keys,
# so it cannot lock the operator out.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

ADMIN="${SERVER_ADMIN_USER:-${SUDO_USER:-}}"
# Fallback: owner of the repo checkout. `sudo -i` / `su -` can drop SUDO_USER,
# and .env ships SERVER_ADMIN_USER blank; a missing value must not hard-fail
# the 10-minute recovery when the answer is unambiguous on disk.
if [ -z "${ADMIN}" ] || [ "${ADMIN}" = "root" ]; then
  ADMIN="$(stat -c '%U' "${INFRA_ROOT}" 2>/dev/null || true)"
fi
[ -n "${ADMIN}" ] && [ "${ADMIN}" != "root" ] || \
  die "cannot resolve admin user; set SERVER_ADMIN_USER=<user> in ${INFRA_ENV_FILE}"
id "${ADMIN}" >/dev/null 2>&1 || die "admin user ${ADMIN} does not exist"

usermod -aG sudo "${ADMIN}" 2>/dev/null || true
getent group docker >/dev/null 2>&1 && usermod -aG docker "${ADMIN}" 2>/dev/null || true
log INFO "admin user ${ADMIN} present, in sudo (+docker if available)"

AK="$(getent passwd "${ADMIN}" | cut -d: -f6)/.ssh/authorized_keys"
HARDEN_PW="no"
if [ -s "${AK}" ]; then
  HARDEN_PW="yes"
else
  log WARN "no authorized_keys for ${ADMIN}; leaving PasswordAuthentication enabled to avoid lockout"
fi

DROPIN=/etc/ssh/sshd_config.d/10-infra-hardening.conf
{
  echo "# Managed by infra/bootstrap/01-user-and-ssh.sh"
  echo "PermitRootLogin no"
  echo "PubkeyAuthentication yes"
  echo "KbdInteractiveAuthentication no"
  echo "X11Forwarding no"
  echo "MaxAuthTries 3"
  [ "${HARDEN_PW}" = "yes" ] && echo "PasswordAuthentication no"
} > "${DROPIN}"

sshd -t || die "sshd config invalid; not reloading (drop-in left at ${DROPIN} for inspection)"
systemctl reload ssh 2>/dev/null || systemctl reload sshd
log INFO "sshd hardened (root login off; password auth ${HARDEN_PW}=disabled)"
