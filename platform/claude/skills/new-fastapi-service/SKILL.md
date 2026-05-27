---
name: new-fastapi-service
description: Bootstraps a new Python FastAPI service following current best practices. Use whenever starting a new HTTP API, microservice, agent backend, or any Python-based backend project. Triggers on phrases like "new FastAPI", "new Python API", "new backend service", "new microservice in Python".
---

# Bootstrap a new FastAPI service

## When to use

Starting any new Python-based HTTP service or backend.

## Self-update on invocation

1. WebSearch for "FastAPI best practices 2026" and "Python project structure 2026".
2. WebSearch for current recommended package manager (uv vs poetry vs others).
3. WebSearch for current recommended lint/format/test tooling (ruff/pytest still standard? Anything newer?).
4. Propose updates to this skill based on findings. Apply only with my approval.

## Steps

1. Confirm the project name and purpose with me in one line.
2. Create project with current recommended package manager (likely `uv init` as of last review; verify).
3. Pin Python version to current stable supported by FastAPI.
4. Add core dependencies: `fastapi`, `uvicorn[standard]`, `pydantic`, `pydantic-settings`, `structlog` (or current best-practice logger).
5. Add dev dependencies: `ruff`, `pytest`, `pytest-asyncio`, `httpx` (for test client), `mypy`.
6. Create project layout:
   ```
   src/<package_name>/
     __init__.py
     main.py           # FastAPI app
     config.py         # pydantic-settings, reads from env
     logging.py        # structured JSON logger setup
     routes/
     models/           # Pydantic models
     services/         # business logic
     db/               # database access if needed
   tests/
     unit/
     e2e/
   ```
7. `main.py`: include health check (`/health`), structured logging middleware, request ID middleware, CORS only if needed (ask).
8. `config.py`: env-driven, with `.env.example` documenting every variable.
9. Add `.gitignore` covering Python, IDE files, `.env`, build artifacts.
10. Add `Dockerfile` (multi-stage, non-root user, healthcheck) — invoke `dockerize-service` skill.
11. Add `pyproject.toml` with ruff config (line length 100, target current Python), pytest config (coverage on, fail under 80%).
12. Initial commit using conventional commit format.
13. Run `add-observability` skill to wire logging properly.
14. Run `before-commit` skill before any commit.

## Checkpoints

- ASK before adding any dependency not in the standard list above.
- ASK before configuring CORS.
- ASK before adding auth — propose the lightest viable option first.

## Related skills

- `dockerize-service` — for Dockerfile and compose
- `postgres-with-pgvector` — when adding a database
- `add-api-endpoint` — for every new endpoint
- `add-observability` — for production logging
- `before-commit` — before every commit

<!-- last_reviewed: 2026-05-12 -->
