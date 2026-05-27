#!/usr/bin/env bash
# 12 - Deploy Claude Code skills, commands, and starter templates to every
# operator on the box.
#
# For each target user, symlink the publishable skills/commands from this
# repo into ~/.claude/, and seed CLAUDE.md / settings.json from the example
# templates ONLY if those files don't exist yet. Existing real files and
# user-modified directories are never touched.
#
# Target users:
#   - SERVER_ADMIN_USER (always; this user already has the claude binary
#     installed by 09-claude-code.sh)
#   - Every Authelia user from platform/authelia/users_database.yml that
#     also exists as a Linux user with a real home directory
#
# Idempotent: safe to re-run after a `git pull` to roll out skill updates.
# Non-destructive: never overwrites a file or replaces a real directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Library mode: source the file (CLAUDE_SKILLS_LIB=1) to expose the helper
# functions for unit testing without executing the deploy. The library mode
# uses a minimal stub `log` if common.sh is not available, so tests can run
# anywhere with just bash.
if [ "${CLAUDE_SKILLS_LIB:-0}" = "1" ]; then
  if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    # shellcheck source=lib/common.sh
    . "${SCRIPT_DIR}/lib/common.sh"
  fi
  if ! declare -F log >/dev/null 2>&1; then
    log() { local lvl="$1"; shift; printf '[%s] %s\n' "${lvl}" "$*" >&2; }
    die() { log ERROR "$*"; exit 1; }
  fi
else
  # shellcheck source=lib/common.sh
  . "${SCRIPT_DIR}/lib/common.sh"
  require_root
  load_env
fi

if [ "${CLAUDE_SKILLS_LIB:-0}" != "1" ]; then
  INSTALL_CLAUDE_SKILLS="${INSTALL_CLAUDE_SKILLS:-true}"
  if [ "${INSTALL_CLAUDE_SKILLS}" != "true" ]; then
    log INFO "INSTALL_CLAUDE_SKILLS=${INSTALL_CLAUDE_SKILLS}; skipping skills deploy"
    exit 0
  fi
fi

# Build the deduplicated target list: admin first, then Authelia users that
# also exist as Linux users with a home directory. Linux-only users (no
# Authelia row) are not targeted; Authelia-only users (no Linux home) are
# logged and skipped.
#
# Plain arrays only (no `declare -A`) — bash 3.2 on macOS doesn't ship
# associative arrays, and the unit tests run on the dev box.
SEEN_USERS=()
TARGETS=()

_seen() {
  local u="$1" s
  for s in "${SEEN_USERS[@]+"${SEEN_USERS[@]}"}"; do
    [ "${s}" = "${u}" ] && return 0
  done
  return 1
}

add_target() {
  local user="$1" home
  [ -n "${user}" ] || return 0
  _seen "${user}" && return 0
  home="$(getent passwd "${user}" 2>/dev/null | cut -d: -f6 || true)"
  if [ -z "${home}" ] || [ ! -d "${home}" ]; then
    log WARN "user '${user}' has no Linux home directory; skipping"
    SEEN_USERS+=("${user}")
    return 0
  fi
  SEEN_USERS+=("${user}")
  TARGETS+=("${user}:${home}")
}

# Extract usernames from an Authelia users_database.yml. Pure-function: takes
# the file path on argv, prints one username per line.
extract_authelia_users() {
  local file="$1"
  [ -f "${file}" ] || return 0
  awk '
    /^users:[[:space:]]*$/ { in_users=1; next }
    in_users && /^[^[:space:]]/ { in_users=0 }
    in_users && /^  [a-z_][a-z0-9_-]*:[[:space:]]*$/ {
      sub(/^[[:space:]]+/, ""); sub(/:.*$/, ""); print
    }
  ' "${file}"
}

# Install a directory with ownership flags only when running as root. The
# script's production callsite is always root; this guard exists so the
# helpers can be exercised in unit tests under an unprivileged user.
_own_install_d() {
  local mode="$1" user="$2" path="$3"
  if [ "$(id -u)" -eq 0 ]; then
    install -d -m "${mode}" -o "${user}" -g "${user}" "${path}"
  else
    install -d -m "${mode}" "${path}"
  fi
}

_own_install_f() {
  local mode="$1" user="$2" src="$3" dst="$4"
  if [ "$(id -u)" -eq 0 ]; then
    install -m "${mode}" -o "${user}" -g "${user}" "${src}" "${dst}"
  else
    install -m "${mode}" "${src}" "${dst}"
  fi
}

# Replace a symlink that points at the wrong target. Skip silently if the
# symlink already points where we want. Refuse to touch a real file or dir.
# Returns: 0 on linked/already-correct, 0 also on refused-clobber (warn only).
# Usage: link_into <user> <src-abs> <dst-abs>
link_into() {
  local user="$1" src="$2" dst="$3" current
  if [ -L "${dst}" ]; then
    current="$(readlink "${dst}" || true)"
    if [ "${current}" = "${src}" ]; then
      return 0
    fi
    log INFO "user=${user}: updating stale symlink ${dst} -> ${src}"
    rm -f "${dst}"
  elif [ -e "${dst}" ]; then
    log WARN "user=${user}: refusing to replace real path ${dst} (preserving local customization)"
    return 0
  fi
  ln -s "${src}" "${dst}"
  [ "$(id -u)" -eq 0 ] && chown -h "${user}:${user}" "${dst}" 2>/dev/null || true
}

# Copy a file from src to dst only if dst doesn't exist. Owner = user, mode 644
# unless overridden.
copy_if_missing() {
  local user="$1" src="$2" dst="$3" mode="${4:-644}"
  if [ -e "${dst}" ]; then
    log INFO "user=${user}: ${dst} already exists; not overwriting"
    return 0
  fi
  _own_install_f "${mode}" "${user}" "${src}" "${dst}"
  log INFO "user=${user}: seeded ${dst} from $(basename "${src}")"
}

deploy_for_user() {
  local user="$1" home="$2"
  local claude_home="${home}/.claude"
  local skills_dst="${claude_home}/skills"
  local commands_dst="${claude_home}/commands"

  # ~/.claude/ (mode 700, owned by the user). install -d is idempotent.
  _own_install_d 700 "${user}" "${claude_home}"
  _own_install_d 755 "${user}" "${skills_dst}"
  _own_install_d 755 "${user}" "${commands_dst}"

  # Link every skill. New ones added to the repo land automatically on next run.
  local entry name
  for entry in "${SKILLS_SRC}"/*/; do
    [ -d "${entry}" ] || continue
    name="$(basename "${entry%/}")"
    link_into "${user}" "${entry%/}" "${skills_dst}/${name}"
  done

  # Link every command file.
  for entry in "${COMMANDS_SRC}"/*.md; do
    [ -f "${entry}" ] || continue
    name="$(basename "${entry}")"
    link_into "${user}" "${entry}" "${commands_dst}/${name}"
  done

  # Seed templates only if missing — never overwrite the operator's own copy.
  copy_if_missing "${user}" "${CLAUDE_MD_SRC}" "${claude_home}/CLAUDE.md" 644
  copy_if_missing "${user}" "${SETTINGS_SRC}" "${claude_home}/settings.json" 644

  log INFO "user=${user}: claude skills deployed"
}

# In library mode, stop here — tests source the file and invoke functions
# directly with their own fixtures.
[ "${CLAUDE_SKILLS_LIB:-0}" = "1" ] && return 0

CLAUDE_SRC="${INFRA_ROOT}/platform/claude"
SKILLS_SRC="${CLAUDE_SRC}/skills"
COMMANDS_SRC="${CLAUDE_SRC}/commands"
CLAUDE_MD_SRC="${CLAUDE_SRC}/CLAUDE.md.example"
SETTINGS_SRC="${CLAUDE_SRC}/settings.json.example"
AUTHELIA_USERS_DB="${INFRA_ROOT}/platform/authelia/users_database.yml"

[ -d "${SKILLS_SRC}" ]   || die "missing ${SKILLS_SRC}; was the repo checked out fully?"
[ -d "${COMMANDS_SRC}" ] || die "missing ${COMMANDS_SRC}"
[ -f "${CLAUDE_MD_SRC}" ]|| die "missing ${CLAUDE_MD_SRC}"
[ -f "${SETTINGS_SRC}" ] || die "missing ${SETTINGS_SRC}"

# Resolve the admin user the same way 09-claude-code.sh does.
ADMIN="${SERVER_ADMIN_USER:-${SUDO_USER:-}}"
if [ -z "${ADMIN}" ] || [ "${ADMIN}" = "root" ]; then
  ADMIN="$(stat -c '%U' "${INFRA_ROOT}" 2>/dev/null || true)"
fi
[ -n "${ADMIN}" ] && [ "${ADMIN}" != "root" ] || \
  die "cannot resolve admin user; set SERVER_ADMIN_USER=<user> in ${INFRA_ENV_FILE}"

add_target "${ADMIN}"

if [ -f "${AUTHELIA_USERS_DB}" ]; then
  while IFS= read -r u; do
    add_target "${u}"
  done < <(extract_authelia_users "${AUTHELIA_USERS_DB}")
else
  log INFO "no Authelia users database at ${AUTHELIA_USERS_DB}; deploying to admin only"
fi

log INFO "deploying claude skills to ${#TARGETS[@]} user(s)"

for t in "${TARGETS[@]}"; do
  user="${t%%:*}"; home="${t#*:}"
  deploy_for_user "${user}" "${home}"
done

write_version_json "${CLAUDE_SRC}" "12-claude-skills.sh"
log INFO "claude skills deploy complete (${#TARGETS[@]} user(s))"
