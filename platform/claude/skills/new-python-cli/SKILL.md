---
name: new-python-cli
description: Bootstraps a new Python CLI tool. Use when starting a command-line utility, automation script with multiple commands, or developer tool in Python. Triggers on "new CLI", "command line tool", "Python script with subcommands".
---

# Bootstrap a new Python CLI tool

## When to use

Starting a multi-command CLI in Python, or upgrading a one-off script into a proper tool.

## Self-update on invocation

1. WebSearch for "Python CLI best practices 2026" (Typer vs Click vs Rich-CLI vs alternatives).
2. WebSearch for current packaging recommendations (uv tool install patterns).
3. Propose updates. Apply with my approval.

## Steps

1. Confirm tool name, primary command, target install path (global via `uv tool` or project-local).
2. Initialize with current recommended package manager.
3. Add Typer (current default) or current best-practice alternative — verify via WebSearch.
4. Add Rich for output formatting.
5. Layout:
   ```
   src/<tool>/
     __init__.py
     __main__.py       # entry point
     cli.py            # Typer app
     commands/         # one file per command group
     core/             # business logic, no CLI concerns
   ```
6. Define entry point in `pyproject.toml` so `uv tool install` works.
7. Add `--version`, `--verbose`, `--quiet`, `--json` flags as standard across commands.
8. Write tests using Typer's test runner.
9. Add a `--help` example for each command in the README.
10. Initial commit.

## Checkpoints

- ASK before adding interactive prompts — many CLIs are run in scripts where prompts break things.
- ASK if the tool will be distributed publicly (different packaging concerns).

## Related skills

- `before-commit`

<!-- last_reviewed: 2026-05-12 -->
