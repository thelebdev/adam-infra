---
name: before-commit
description: Pre-commit checklist — tests, lint, type check, secret scan, verify nothing sensitive staged. Use before every commit. Trigger on intent to commit, push, or finalize changes.
---

# Pre-commit checklist

## Steps

1. Run linter on staged files. Fix issues. If issues are non-trivial, surface them to me.
2. Run formatter on staged files. Confirm the diff didn't introduce surprises.
3. Run type checker (mypy, tsc, etc.). All errors fixed or explicitly waived with a comment.
4. Run tests:
   - Unit tests for changed modules — must pass.
   - E2E tests if any changed code is exercised by them — must pass.
   - If a test takes >30s and isn't affected, skip it and note that I should run the full suite locally.
5. Scan for secrets:
   - Run `gitleaks` or current best-practice scanner.
   - Grep for common patterns: `api_key`, `secret`, `password`, `BEGIN PRIVATE KEY`, AWS access keys, Bitwarden tokens.
   - Inspect `.env*` and config files in the diff.
6. Verify no .env, no .DS_Store, no node_modules, no __pycache__ staged.
7. Verify no large files (>1MB) staged unless they're explicitly meant to be tracked.
8. Write the commit message in conventional commit format. Mention versioning impact.
9. STOP. Show me the diff summary, the test results, and the proposed commit message. Wait for approval.

## Checkpoints

- ALWAYS stop before the actual commit. I approve every commit.
- NEVER `git push --force`.
- NEVER amend an already-pushed commit without asking.

<!-- last_reviewed: 2026-05-12 -->
