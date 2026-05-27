---
name: code-review
description: Reviews staged changes against coding standards, security best practices, and operational hygiene. Use when I type /review, ask for a review, or ask for feedback on changes.
---

# Code review

## Steps

1. Pull the diff of staged or specified changes.
2. Review against these dimensions, in order. Note findings as you go; don't fix anything yet.

### Correctness
- Does it do what was intended?
- Edge cases handled (empty, null, max, concurrent, network failure)?
- Off-by-one errors, integer overflow, timezone bugs?

### Security
- Input validation on all external inputs?
- SQL injection, command injection, path traversal possible?
- Secrets hardcoded or logged?
- Authentication and authorization checked at the right boundary?
- Sensitive data in URLs, logs, error responses?

### Operational
- Logging adequate to debug an incident?
- Errors propagate with enough context?
- Retries and timeouts on external calls?
- Resource cleanup (file handles, DB connections)?

### Performance
- N+1 queries?
- Unnecessary allocations in hot paths?
- Synchronous calls that could be async?
- Indexes covering new queries?

### Style
- Conventions consistent with the rest of the codebase?
- Type hints / types present?
- Tests written, edge cases covered?
- Comments explain why where non-obvious?

3. Summarize findings categorized as: blockers, recommendations, nits.
4. STOP. Present findings. Wait for me to decide what to fix.

## Checkpoints

- Do not fix anything without my approval.
- Do not add commits during a review.

<!-- last_reviewed: 2026-05-12 -->
