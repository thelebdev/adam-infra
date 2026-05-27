---
name: add-api-endpoint
description: Adds a new HTTP endpoint following conventions — Pydantic request/response models, error handling, structured logging, OpenAPI tags, tests. Use when extending an existing API or service.
---

# Add an API endpoint

## Steps

1. Confirm: method, path, purpose, request/response shape.
2. Naming convention: `/api/v1/<domain>/<action>` (e.g., `/api/v1/customers/lookup`, `/api/v1/orders/list`).
3. Use REST verbs correctly:
   - GET: read, idempotent, cacheable
   - POST: create or non-idempotent action
   - PUT: full replace
   - PATCH: partial update
   - DELETE: remove
4. Request validation: Pydantic model with descriptive field names, sensible defaults, validators where useful.
5. Response model: Pydantic model. Never return raw dicts.
6. Error responses: structured (`{error: {code, message, details}}`), correct status codes, no stack traces leaked to clients.
7. Logging: log request ID, user/customer ID if known, latency, status code. Don't log request bodies containing sensitive data.
8. Authentication: enforce at route level via dependency. Never trust client claims.
9. Authorization: check permissions in the route, not just authentication.
10. Rate limiting: applied at the framework level (e.g., slowapi for FastAPI). Configure per endpoint based on cost.
11. OpenAPI: meaningful `summary`, `description`, `tags`. Examples in the schema if non-obvious.
12. Tests:
    - Happy path
    - Each failure mode (validation, auth, not found, conflict)
    - Edge cases (empty input, max length, special characters)
    - Error rendering (confirm the response shape on every error)

## Checkpoints

- ASK before adding endpoints that mutate financial state.
- ASK before adding endpoints that bulk-delete or bulk-update.
- ASK before adding public unauthenticated endpoints.

## Related skills

- `before-commit`
- `add-observability`

<!-- last_reviewed: 2026-05-12 -->
