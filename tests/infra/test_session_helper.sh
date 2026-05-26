#!/usr/bin/env bash
# Unit tests for platform/ttyd/session.
#
# Sources the helper in library mode (SESSION_LIB=1) so its pure
# functions can be exercised without tmux or claude. No VPS, no network.
# The directory-confinement tests need GNU `realpath -m` (Ubuntu, the deploy
# target) and are skipped — not failed — elsewhere.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${HERE}/../../platform/ttyd/session"

pass=0; fail=0; skip=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
skp() { skip=$((skip + 1)); printf '  skip  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected [$2], got [$3])"; fi; }
yes() { if "$@" >/dev/null 2>&1; then ok "$*"; else no "$*"; fi; }
nope() { if "$@" >/dev/null 2>&1; then no "unexpectedly ok: $*"; else ok "rejects: $*"; fi; }

[ -f "$HELPER" ] || { echo "missing $HELPER"; exit 1; }

WS="$(mktemp -d)"
SOCK="$(mktemp -d)"
trap 'rm -rf "$WS" "$SOCK"' EXIT
mkdir -p "$WS/proj-a" "$WS/proj-b/sub"

export SESSION_WORKSPACE_ROOT="$WS"
export SESSION_SOCKET_DIR="$SOCK"
export SESSION_LIB=1
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

echo "valid_cmd:"
yes  valid_cmd shell
yes  valid_cmd claude
nope valid_cmd ""
nope valid_cmd "bash"
nope valid_cmd "rm"
nope valid_cmd "shell;evil"

echo "resolve_cmd_argv:"
# `shell` sessions must launch via /usr/local/bin/sandbox-shell so they run
# inside the bwrap jail — never spawn an unconfined bash directly.
eq "shell argv[0] is sandbox-shell" \
   "/usr/local/bin/sandbox-shell" \
   "$(resolve_cmd_argv shell "$WS/proj-a" | head -1)"
eq "shell argv[1] is the requested dir" \
   "$WS/proj-a" \
   "$(resolve_cmd_argv shell "$WS/proj-a" | sed -n 2p)"
eq "shell argv defaults dir to workspace root" \
   "$WS" \
   "$(resolve_cmd_argv shell | sed -n 2p)"
eq "claude argv is 'claude'" "claude" "$(resolve_cmd_argv claude)"
nope resolve_cmd_argv bogus

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

echo "markers:"
USER_ID="alice"
write_marker "foo" "claude"
eq "marker round-trip claude" "claude" "$(read_marker foo)"
write_marker "bar" "shell"
eq "marker round-trip shell"  "shell"  "$(read_marker bar)"
eq "default when missing"     "shell"  "$(read_marker nonexistent)"
clear_marker "foo"
eq "cleared marker → default" "shell"  "$(read_marker foo)"

echo "open_session (dry-run):"
export SESSION_DRYRUN=1
tm() { return 1; }   # stub: session does not exist
eq "creates when absent (shell default)" \
   "CREATE foo $WS/foo shell" "$(open_session foo "$WS/foo")"
eq "creates when absent (claude explicit)" \
   "CREATE bar $WS/bar claude" "$(open_session bar "$WS/bar" claude)"
eq "bad cmd falls back to default" \
   "CREATE baz $WS/baz shell" "$(open_session baz "$WS/baz" bogus)"
tm() { return 0; }   # stub: session exists
eq "attaches when present" "ATTACH foo"        "$(open_session foo)"

echo
printf 'session helper: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
