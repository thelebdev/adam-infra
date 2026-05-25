#!/usr/bin/env bash
# 09 - Claude Code on the host (remote-management agent).
# Installs the `claude` binary for the admin user so it can be selected as
# the command for a browser terminal session (07-ttyd) and used directly
# over SSH. Idempotent. Auth is a deliberate manual step: either
# `claude login` over the SSH session, or ANTHROPIC_API_KEY from .env
# exported in the admin shell.
#
# INSTALL_CLAUDE is independent of INSTALL_SESSIONS — you can have the
# binary without the browser terminal (SSH-only use), and you can have the
# browser terminal without the binary (shell-only sessions).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root

INSTALL_CLAUDE="${INSTALL_CLAUDE:-true}"
if [ "${INSTALL_CLAUDE}" != "true" ]; then
  log INFO "INSTALL_CLAUDE=${INSTALL_CLAUDE}; skipping Claude Code install"
  exit 0
fi

ADMIN="${SERVER_ADMIN_USER:-${SUDO_USER:-}}"
if [ -z "${ADMIN}" ] || [ "${ADMIN}" = "root" ]; then
  ADMIN="$(stat -c '%U' "${INFRA_ROOT}" 2>/dev/null || true)"
fi
[ -n "${ADMIN}" ] && [ "${ADMIN}" != "root" ] || \
  die "cannot resolve admin user; set SERVER_ADMIN_USER=<user> in ${INFRA_ENV_FILE}"
ADMIN_HOME="$(getent passwd "${ADMIN}" | cut -d: -f6)"

if sudo -u "${ADMIN}" bash -lc 'command -v claude' >/dev/null 2>&1; then
  log INFO "claude code already installed for ${ADMIN}"
else
  log INFO "installing claude code for ${ADMIN}"
  sudo -u "${ADMIN}" bash -lc 'curl -fsSL https://claude.ai/install.sh | bash'
fi

# The installer drops the binary in ~/.local/bin, which is not reliably on
# PATH for non-interactive/login shells. Put it there idempotently for both
# login (.profile) and interactive (.bashrc) shells, owned by the admin user.
PATHLINE='export PATH="$HOME/.local/bin:$PATH"'
for rc in "${ADMIN_HOME}/.profile" "${ADMIN_HOME}/.bashrc"; do
  ensure_line "${PATHLINE}" "${rc}"
  chown "${ADMIN}:${ADMIN}" "${rc}" 2>/dev/null || true
done

# Make the API key available to the admin shell only if provided (never logged).
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  ENVLINE='export ANTHROPIC_API_KEY="$(grep -m1 "^ANTHROPIC_API_KEY=" '"${INFRA_ENV_FILE}"' | cut -d= -f2-)"'
  ensure_line "${ENVLINE}" "${ADMIN_HOME}/.bashrc"
  log INFO "ANTHROPIC_API_KEY wired into ${ADMIN} shell from .env"
else
  log WARN "ANTHROPIC_API_KEY not set; run 'claude login' over SSH to authenticate"
fi

# If ttyd-sessions is already up, kick it so the session-manager + ttyd see
# the freshly-installed claude binary on the next session spawn. Harmless
# if the unit doesn't exist yet.
if systemctl is-active --quiet ttyd-sessions.service 2>/dev/null; then
  systemctl restart ttyd-sessions.service 2>/dev/null || true
fi
if systemctl is-active --quiet session-manager.service 2>/dev/null; then
  systemctl restart session-manager.service 2>/dev/null || true
fi

VER="$(sudo -u "${ADMIN}" bash -lc 'claude --version' 2>/dev/null || echo unknown)"
log INFO "claude code ready for ${ADMIN} (version: ${VER})"
