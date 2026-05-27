Audit dependencies for the current project:

1. Identify the package manager and dependency files.
2. Run the appropriate audit command:
   - Python: `uv pip list --outdated`, then `pip-audit` or current best practice.
   - Node: `pnpm audit` (or npm/yarn/bun equivalent), `pnpm outdated`.
3. WebSearch for current security advisories on any pinned versions that look old.
4. Report findings:
   - CRITICAL: known vulnerabilities, must update.
   - WARNING: major version updates available.
   - INFO: minor/patch updates available.
5. STOP. Don't update anything without my approval.
