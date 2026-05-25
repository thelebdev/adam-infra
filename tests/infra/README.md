# Infrastructure tests

Tests that verify the platform behaves as documented.

## Status

Unit tests for the browser-session layer have landed. Run them with
`./run-tests.sh` — pure functions only, no VPS, no Docker, no network:

- `test_session_helper.sh` — the `session` helper: session-name and
  user-identity validation, command allowlist, marker round-trip, and
  workspace-directory confinement (the `..`/symlink/absolute-path escape
  rejections). Directory tests need GNU `realpath -m` and self-skip on
  non-Linux hosts.
- `test_session_manager.py` — the `session-manager` API: directory
  confinement, command allowlist + marker round-trip, `tmux` output
  parsing, error mapping, and the `Remote-User` trust boundary
  (ambiguous/malformed identities are refused).

## Intended structure (still to come)

- `bootstrap-test.sh` — runs the full bootstrap on a fresh VPS, verifies it completes successfully within the SLA
- `health-checks.sh` — verifies each platform service is reachable and producing expected signals
- `recovery-dry-run.sh` — automated quarterly dry-run
