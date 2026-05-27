---
name: add-database-migration
description: Creates a new database migration with proper conventions, reversibility, and safety checks. Use whenever changing the database schema. Triggers on "add migration", "schema change", "new table", "alter table".
---

# Add a database migration

## When to use

Any time the database schema changes.

## Steps

1. Identify the migration tool in use (Alembic, Drizzle, Prisma, raw SQL). Use the project's existing tool.
2. Name the migration descriptively: `<verb>_<noun>` (e.g., `add_customer_phone_index`, `create_agent_profiles_table`).
3. Write both up and down migrations. Both must be tested.
4. For column additions: make them nullable or with a default. Never add a NOT NULL column without a default to a non-empty table.
5. For column drops: two-phase migration — first deploy code that stops using the column, then drop in a later migration.
6. For renames: same two-phase pattern. Add new column, dual-write, backfill, switch reads, drop old column in a later release.
7. Idempotency: use `IF NOT EXISTS`, `IF EXISTS` where the tool supports it.
8. Index changes:
   - Index creation on large tables: use `CREATE INDEX CONCURRENTLY` (Postgres). Migration tool may not support it natively; may need raw SQL.
9. Vector dimension changes: ASK. This requires re-embedding all rows. Not a routine migration.
10. Run the migration locally first, verify, then commit.

## Checkpoints

- ASK before any DROP TABLE, DROP COLUMN, or TRUNCATE.
- ASK before changing a primary key.
- ASK before changing foreign key cascade behavior on an existing FK.

## Related skills

- `postgres-with-pgvector`
- `before-commit`

<!-- last_reviewed: 2026-05-12 -->
