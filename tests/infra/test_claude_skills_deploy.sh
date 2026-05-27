#!/usr/bin/env bash
# Unit tests for bootstrap/12-claude-skills.sh.
#
# Sources the deployer in library mode (CLAUDE_SKILLS_LIB=1) so the helper
# functions can be exercised against tmp fixtures without root, tmux, docker,
# or a real ~/.claude. The link_into / copy_if_missing semantics are the
# load-bearing pieces — these tests pin them.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../../bootstrap/12-claude-skills.sh"

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected [$2], got [$3])"; fi; }

[ -f "${SCRIPT}" ] || { echo "missing ${SCRIPT}"; exit 1; }

CLAUDE_SKILLS_LIB=1
# shellcheck disable=SC1090
. "${SCRIPT}"
set +eu  # helpers may use -e; tests must continue past assertion failures

USER="$(id -un)"

# Fresh fixture: a tmp "infra root" with skills/commands/templates, and a tmp
# "home dir" to deploy into.
FIX_ROOT="$(mktemp -d)"
trap 'rm -rf "${FIX_ROOT}"' EXIT

REPO="${FIX_ROOT}/repo"
HOME_FAKE="${FIX_ROOT}/home"
SKILLS_SRC="${REPO}/platform/claude/skills"
COMMANDS_SRC="${REPO}/platform/claude/commands"
CLAUDE_MD_SRC="${REPO}/platform/claude/CLAUDE.md.example"
SETTINGS_SRC="${REPO}/platform/claude/settings.json.example"

mkdir -p "${SKILLS_SRC}/alpha" "${SKILLS_SRC}/beta" "${COMMANDS_SRC}" "${HOME_FAKE}"
printf 'alpha skill\n'  > "${SKILLS_SRC}/alpha/SKILL.md"
printf 'beta skill\n'   > "${SKILLS_SRC}/beta/SKILL.md"
printf 'cmd alpha\n'    > "${COMMANDS_SRC}/alpha.md"
printf 'template md\n'  > "${CLAUDE_MD_SRC}"
printf '{"x":1}\n'      > "${SETTINGS_SRC}"

echo "extract_authelia_users:"
DB="${FIX_ROOT}/users_database.yml"
cat > "${DB}" <<'YAML'
# leading comment
users:
  alice:
    disabled: false
  bob_2:
    disabled: false
  Invalid-User:
    disabled: false
not_in_block:
  trap:
    disabled: false
YAML
got="$(extract_authelia_users "${DB}" | tr '\n' ' ')"
eq "extracts valid usernames only" "alice bob_2 " "${got}"
got="$(extract_authelia_users "${FIX_ROOT}/does-not-exist.yml" | wc -l | tr -d ' ')"
eq "missing file yields no output" "0" "${got}"

echo
echo "link_into:"
DST_DIR="${HOME_FAKE}/.claude/skills"
mkdir -p "${DST_DIR}"
SRC="${SKILLS_SRC}/alpha"
DST="${DST_DIR}/alpha"

link_into "${USER}" "${SRC}" "${DST}" >/dev/null 2>&1
[ -L "${DST}" ] && ok "creates symlink when target absent" || no "creates symlink when target absent"
eq "symlink points to source" "${SRC}" "$(readlink "${DST}")"

# Second call is a no-op (idempotent).
mtime_before="$(stat -f %m "${DST}" 2>/dev/null || stat -c %Y "${DST}")"
sleep 1
link_into "${USER}" "${SRC}" "${DST}" >/dev/null 2>&1
mtime_after="$(stat -f %m "${DST}" 2>/dev/null || stat -c %Y "${DST}")"
eq "idempotent: same symlink not touched" "${mtime_before}" "${mtime_after}"

# Stale symlink (points elsewhere) gets replaced.
rm -f "${DST}"
ln -s "${FIX_ROOT}/elsewhere" "${DST}"
link_into "${USER}" "${SRC}" "${DST}" >/dev/null 2>&1
eq "stale symlink replaced" "${SRC}" "$(readlink "${DST}")"

# Real directory is preserved (never clobbered).
rm -f "${DST}"
mkdir -p "${DST}"
printf 'local override\n' > "${DST}/SKILL.md"
link_into "${USER}" "${SRC}" "${DST}" >/dev/null 2>&1
[ -d "${DST}" ] && [ ! -L "${DST}" ] && ok "real dir preserved (no clobber)" \
  || no "real dir preserved (no clobber)"
eq "real dir contents intact" "local override" "$(cat "${DST}/SKILL.md")"

# Real file is preserved.
rm -rf "${DST}"
printf 'real file\n' > "${DST}"
link_into "${USER}" "${SRC}" "${DST}" >/dev/null 2>&1
[ -f "${DST}" ] && [ ! -L "${DST}" ] && ok "real file preserved (no clobber)" \
  || no "real file preserved (no clobber)"

echo
echo "copy_if_missing:"
SEED_DST="${HOME_FAKE}/.claude/CLAUDE.md"
rm -f "${SEED_DST}"
copy_if_missing "${USER}" "${CLAUDE_MD_SRC}" "${SEED_DST}" 644 >/dev/null 2>&1
[ -f "${SEED_DST}" ] && [ ! -L "${SEED_DST}" ] && ok "seeds file when missing" \
  || no "seeds file when missing"
eq "seeded content matches source" "template md" "$(cat "${SEED_DST}")"

printf 'user customization\n' > "${SEED_DST}"
copy_if_missing "${USER}" "${CLAUDE_MD_SRC}" "${SEED_DST}" 644 >/dev/null 2>&1
eq "existing file not overwritten" "user customization" "$(cat "${SEED_DST}")"

echo
echo "deploy_for_user (end-to-end against tmp fixture):"
USER_HOME="${HOME_FAKE}/u1"
mkdir -p "${USER_HOME}"

# deploy_for_user reads these globals; the production script sets them.
CLAUDE_SRC="${REPO}/platform/claude"
deploy_for_user "${USER}" "${USER_HOME}" >/dev/null 2>&1

[ -L "${USER_HOME}/.claude/skills/alpha" ] && ok "deploy: alpha skill linked" \
  || no "deploy: alpha skill linked"
[ -L "${USER_HOME}/.claude/skills/beta" ] && ok "deploy: beta skill linked" \
  || no "deploy: beta skill linked"
[ -L "${USER_HOME}/.claude/commands/alpha.md" ] && ok "deploy: command linked" \
  || no "deploy: command linked"
[ -f "${USER_HOME}/.claude/CLAUDE.md" ] && [ ! -L "${USER_HOME}/.claude/CLAUDE.md" ] \
  && ok "deploy: CLAUDE.md seeded as real file" \
  || no "deploy: CLAUDE.md seeded as real file"
[ -f "${USER_HOME}/.claude/settings.json" ] && [ ! -L "${USER_HOME}/.claude/settings.json" ] \
  && ok "deploy: settings.json seeded" \
  || no "deploy: settings.json seeded"

# Run again — fully idempotent.
deploy_for_user "${USER}" "${USER_HOME}" >/dev/null 2>&1
ok "deploy: idempotent re-run did not error"

# Add a new skill to the source; second run should pick it up.
mkdir -p "${SKILLS_SRC}/gamma"
printf 'gamma skill\n' > "${SKILLS_SRC}/gamma/SKILL.md"
deploy_for_user "${USER}" "${USER_HOME}" >/dev/null 2>&1
[ -L "${USER_HOME}/.claude/skills/gamma" ] && ok "deploy: newly-added skill picked up on re-run" \
  || no "deploy: newly-added skill picked up on re-run"

# User customization is preserved across re-runs.
rm -f "${USER_HOME}/.claude/skills/alpha"
mkdir -p "${USER_HOME}/.claude/skills/alpha"
printf 'local hack\n' > "${USER_HOME}/.claude/skills/alpha/SKILL.md"
deploy_for_user "${USER}" "${USER_HOME}" >/dev/null 2>&1
[ -d "${USER_HOME}/.claude/skills/alpha" ] && [ ! -L "${USER_HOME}/.claude/skills/alpha" ] \
  && ok "deploy: user-customized real dir preserved" \
  || no "deploy: user-customized real dir preserved"
eq "deploy: user customization intact" "local hack" \
  "$(cat "${USER_HOME}/.claude/skills/alpha/SKILL.md")"

echo
printf 'pass=%d fail=%d\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
