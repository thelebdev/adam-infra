---
name: postgres-with-pgvector
description: Sets up Postgres with pgvector extension and standard schema patterns (snake_case plural tables, uuid PKs, audit columns, proper indexes). Use when adding a database to a project, especially for AI/agent applications needing semantic search. Triggers on "add database", "set up Postgres", "add vector search", "RAG database".
---

# Postgres with pgvector setup

## When to use

Adding a database to a project. Especially when semantic search, embeddings, or RAG is involved.

## Challenge the default first

Before setting up Postgres, ask: does this data actually fit relational? If the answer is one of these, pause and propose an alternative:
- Heavily hierarchical / graph-shaped → consider Neo4j or AGE extension on Postgres
- Time-series heavy → consider TimescaleDB extension on Postgres
- Document-shape with rare joins → MongoDB or Postgres JSONB (default to JSONB unless scale demands otherwise)
- Pure key-value, ephemeral → Redis, not Postgres

If Postgres is right, proceed.

## Self-update on invocation

1. WebSearch for "pgvector best practices 2026", "Postgres index strategies 2026".
2. Check current pgvector version and ivfflat vs hnsw index recommendations.
3. Propose updates. Apply with my approval.

## Steps

1. Use `pgvector/pgvector:pg17` (or current stable) Docker image — plain Postgres image lacks the extension.
2. Add `CREATE EXTENSION` for: `uuid-ossp`, `pgcrypto`, `vector`, `pg_trgm` (for hybrid search later).
3. Schema conventions:
   - Tables: `snake_case`, plural.
   - Primary keys: `uuid PRIMARY KEY DEFAULT gen_random_uuid()`.
   - Audit columns: `created_at`, `updated_at` (auto-updated via trigger) on every table.
   - Foreign keys: always specify `ON DELETE` behavior explicitly.
   - Indexes: name them explicitly, `idx_<table>_<columns>`.
4. For vector columns:
   - Pick embedding model first, fix `vector(N)` dimension to match. Document the model choice.
   - Default index: `ivfflat` until quality demands `hnsw`.
   - Filter columns (e.g., tenant_id, namespace) get their own index for pre-filtering.
5. Migrations:
   - Use Alembic for Python, Drizzle Kit for TS — verify current best practice via WebSearch.
   - Migrations are versioned, idempotent, reversible.
   - Never destructive without my explicit approval.
6. Connection management:
   - Pool size tuned to expected concurrency (start at 10, scale up).
   - Always use connection pooler (PgBouncer or built-in if available) for production.
7. Backups:
   - `pg_dump` daily minimum.
   - Run `vps-backup-strategy` skill to wire offsite backup.

## Checkpoints

- ASK before adding a non-Postgres database (verify the use case warrants it).
- ASK before any DROP, TRUNCATE, or DELETE without WHERE in production.
- ASK before changing the embedding dimension on an existing vector column (requires re-embedding everything).

## Related skills

- `add-database-migration`
- `vps-backup-strategy`
- `add-observability`

<!-- last_reviewed: 2026-05-12 -->
