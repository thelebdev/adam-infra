#!/usr/bin/env bash
# Unit tests for platform/ttyd/claude-session.
#
# Sources the helper in library mode (CLAUDE_SESSION_LIB=1) so its pure
# functions can be exercised without tmux or claude. No VPS, no network.
# The directory-confinement tests need GNU `realpath -m` (Ubuntu, the deploy
# target) and are skipped — not failed — elsewhere.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${HERE}/../../platform/ttyd/claude-session"

pass=0; fail=0; skip=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
skp() { skip=$((skip + 1)); printf '  skip  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected [$2], got [$3])"; fi; }
yes() { if "$@" >/dev/null 2>&1; then ok "$*"; else no "$*"; fi; }
nope() { if "$@" >/dev/null 2>&1; then no "unexpectedly ok: $*"; else ok "rejects: $*"; fi; }

[ -f "$HELPER" ] || { echo "missing $HELPER"; exit 1; }

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/proj-a" "$WS/proj-b/sub"

export CLAUDE_WORKSPACE_ROOT="$WS"
export CLAUDE_SESSION_LIB=1
# shellcheck disable=SC1090
. "$HELPER"
set +eu   # the helper enables `set -eu`; assertions must not abort the run.

echo "valid_name:"
yes  valid_name api
yes  valid_name 1proj
yes  valid_name a-b_c
nope valid_name ""
nope valid_name "a.b"
nope valid_name "a b"
nope valid_name "../x"
nope valid_name "$(printf 'x%.0s' {1..33})"

echo "valid_user:"
yes  valid_user admin
yes  valid_user _svc
nope valid_user Admin
nope valid_user ""
nope valid_user 1user

echo "confine_dir:"
if realpath -m / >/dev/null 2>&1; then
  eq "root itself"     "$(realpath -m "$WS")"            "$(confine_dir '')"
  eq "existing subdir" "$(realpath -m "$WS/proj-a")"     "$(confine_dir proj-a)"
  eq "nested subdir"   "$(realpath -m "$WS/proj-b/sub")" "$(confine_dir proj-b/sub)"
  eq "new project dir" "$(realpath -m "$WS/newproj")"    "$(confine_dir newproj)"
  nope confine_dir "../escape"
  nope confine_dir "/etc"
  nope confine_dir "proj-a/../../escape"
  ln -s /etc "$WS/evil"
  nope confine_dir "evil"
else
  skp "confine_dir tests (need GNU realpath -m; this host is not Linux)"
fi

echo "open_session (dry-run):"
export CLAUDE_SESSION_DRYRUN=1
tm() { return 1; }   # stub: session does not exist
eq "creates when absent"  "CREATE foo $WS/foo" "$(open_session foo "$WS/foo")"
tm() { return 0; }   # stub: session exists
eq "attaches when present" "ATTACH foo"        "$(open_session foo)"

echo
printf 'claude-session: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
