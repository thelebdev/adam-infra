---
name: dockerize-service
description: Adds Dockerfile and docker-compose.yml to a project with current best practices (multi-stage builds, minimal images, non-root user, healthchecks). Use when preparing a project for containerized deployment.
---

# Dockerize a service

## Self-update on invocation

1. WebSearch for "Dockerfile best practices 2026" and language-specific base image recommendations.
2. Check for any new vulnerabilities in commonly used base images.
3. Propose updates. Apply with my approval.

## Steps

1. Pick base image:
   - Python: `python:X.Y-slim-bookworm` or distroless if no shell needed.
   - Node: `node:X-bookworm-slim` or distroless.
   - Verify current security recommendations via WebSearch.
2. Multi-stage build:
   - Build stage: install build deps, compile.
   - Runtime stage: copy only the artifacts. No build tools in final image.
3. Non-root user. Always.
4. Set workdir to `/app` (or similar non-root path).
5. Pin all dependencies. No `latest` tags anywhere.
6. Healthcheck defined in the Dockerfile.
7. Expose only the ports the service actually serves.
8. `.dockerignore` covering: `.git`, `.env*` (except `.env.example`), `node_modules`, `__pycache__`, tests if not needed at runtime, IDE files.
9. `docker-compose.yml`:
   - Service + database + redis (if needed) + caddy (for local TLS testing optional).
   - Volumes for persistence on dev.
   - Env vars from `.env`.
   - Service-level healthchecks with `depends_on: condition: service_healthy`.
10. Run `docker compose up` locally and verify everything starts cleanly.

## Checkpoints

- ASK before using a non-LTS base image.
- ASK before mounting any host path in production compose configs.

## Related skills

- `deploy-to-vps`
- `add-observability`

<!-- last_reviewed: 2026-05-12 -->
