#!/usr/bin/env bash
# Run the infrastructure unit tests.
#
# Pure-function tests only — no VPS, no Docker, no network. Safe to run on any
# host with bash and python3. The fuller suite described in this directory's
# README (full-bootstrap on a fresh VPS, health checks) is separate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0

echo "== session helper (shell) =="
bash "${HERE}/test_session_helper.sh" || rc=1
echo

echo "== claude-skills deploy (shell) =="
bash "${HERE}/test_claude_skills_deploy.sh" || rc=1
echo

echo "== session-manager (python) =="
python3 -m unittest discover -s "${HERE}" -p 'test_*.py' -v || rc=1
echo

if [ "${rc}" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "${rc}"
