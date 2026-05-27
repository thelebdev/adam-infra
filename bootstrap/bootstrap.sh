#!/usr/bin/env bash
# Platform bootstrap orchestrator.
#
# Privilege model: root-shell-via-sudo. The operator runs:
#     sudo -i
#     cd /opt/infra && ./bootstrap/bootstrap.sh
# No permanent passwordless sudo is configured. The password is entered once
# (by `sudo -i`); every numbered script then runs as root, unattended.
#
# Idempotent: safe to re-run on a fresh or already-provisioned VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_root
load_env

# Ask once which optional components to install. Answers persist to .env via
# set_env_var, so re-runs and disaster-recovery runs are non-interactive.
# Without a TTY (CI) undecided components default to install. The hardened
# base (00-04) and verify (99) always run and are never prompted for.
select_components() {
  local var label ans profile
  profile="${OBSERVABILITY_PROFILE:-lightweight}"
  for entry in \
    "INSTALL_GLANCES|Glances (host metrics)" \
    "INSTALL_DOZZLE|Dozzle (container logs)" \
    "INSTALL_NTOPNG|ntopng (network traffic, ~256 MB RAM)" \
    "INSTALL_SESSIONS|Browser terminal sessions (shell + tmux + dashboard panel)" \
    "INSTALL_CLAUDE|Claude Code binary (available as a session command)" \
    "INSTALL_CLAUDE_SKILLS|Claude skills + starter templates deployed to ~/.claude/" \
    "INSTALL_DASHBOARD|platform dashboard landing page"
  do
    var="${entry%%|*}"
    label="${entry#*|}"
    # Already decided in .env -> keep it (non-interactive on re-runs).
    if [ -n "${!var:-}" ]; then
      continue
    fi
    # The lightweight-only tools do not exist on the full profile.
    case "${var}" in
      INSTALL_GLANCES|INSTALL_DOZZLE|INSTALL_NTOPNG)
        if [ "${profile}" != "lightweight" ]; then continue; fi ;;
    esac
    ans=""
    if [ -t 0 ]; then
      printf '  Install %s? [Y/n]: ' "${label}" >&2
      read -r ans || true
    fi
    case "${ans}" in
      [Nn]*) ans=false ;;
      *)     ans=true ;;
    esac
    set_env_var "${var}" "${ans}"
    log INFO "component ${var}=${ans}"
  done
}
# Ask once for custom subdomain labels, gated behind a single yes/no so the
# common path stays fast. Defaults to the conventional names; persists to
# .env; only prompts for components that will actually be installed.
select_subdomains() {
  [ -n "${PRIMARY_DOMAIN:-}" ] || return 0
  local profile ans e var def tmp label val pending=0
  profile="${OBSERVABILITY_PROFILE:-lightweight}"
  local list=( "SUBDOMAIN_AUTH:auth:Authelia portal" )
  [ "${INSTALL_DASHBOARD:-true}" = "true" ] && list+=( "SUBDOMAIN_DASHBOARD:dashboard:platform dashboard" )
  [ "${INSTALL_SESSIONS:-true}"  = "true" ] && list+=( "SUBDOMAIN_SESSIONS:sessions:Browser terminal sessions" )
  if [ "${profile}" = "lightweight" ]; then
    [ "${INSTALL_DOZZLE:-true}"  = "true" ] && list+=( "SUBDOMAIN_DOZZLE:dozzle:Dozzle" )
    [ "${INSTALL_GLANCES:-true}" = "true" ] && list+=( "SUBDOMAIN_GLANCES:glances:Glances" )
    [ "${INSTALL_NTOPNG:-true}"  = "true" ] && list+=( "SUBDOMAIN_NTOPNG:ntopng:ntopng" )
  else
    list+=( "SUBDOMAIN_GRAFANA:grafana:Grafana" )
  fi
  for e in "${list[@]}"; do
    var="${e%%:*}"
    [ -n "${!var:-}" ] || pending=1
  done
  [ "${pending}" -eq 1 ] || return 0
  ans=n
  if [ -t 0 ]; then
    printf '  Customize subdomain names? Default is auth/sessions/grafana/etc. [y/N]: ' >&2
    read -r ans || true
  fi
  for e in "${list[@]}"; do
    var="${e%%:*}"
    tmp="${e#*:}"; def="${tmp%%:*}"
    label="${e##*:}"
    [ -n "${!var:-}" ] && continue
    val=""
    case "${ans}" in
      [Yy]*)
        if [ -t 0 ]; then
          printf '    %s subdomain [%s]: ' "${label}" "${def}" >&2
          read -r val || true
        fi ;;
    esac
    val="${val:-${def}}"
    printf '%s' "${val}" | grep -qE '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' \
      || die "invalid subdomain label '${val}' for ${var} (DNS label: lowercase letters, digits, hyphens)"
    set_env_var "${var}" "${val}"
    log INFO "subdomain ${var}=${val}"
  done
}

select_components
load_env
select_subdomains
load_env

STEPS=(
  00-prerequisites.sh
  01-user-and-ssh.sh
  02-firewall.sh
  03-kernel-hardening.sh
  04-docker.sh
  05-authelia.sh
  06-caddy.sh
  07-ttyd.sh
  08-observability.sh
  09-claude-code.sh
  10-dashboard.sh
  11-session-manager.sh
  12-claude-skills.sh
  99-verify.sh
)

log INFO "bootstrap starting (${#STEPS[@]} steps)"
for step in "${STEPS[@]}"; do
  path="${SCRIPT_DIR}/${step}"
  [ -x "${path}" ] || chmod +x "${path}"
  log INFO "=== running ${step} ==="
  INFRA_CURRENT_SCRIPT="${step%.sh}" bash "${path}"
  log INFO "=== completed ${step} ==="
done
log INFO "bootstrap complete; platform layer operational"
