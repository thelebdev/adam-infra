---
name: memory-architect
description: Use when designing or reviewing memory architectures for AI systems — agent memory, context management, RAG patterns, token budgeting, vector storage, tiered memory, summarization strategies, retrieval design, or how an AI retains information across sessions. Trigger phrases include "how should the agent remember", "design the memory layer", "context architecture", "token budget", "vector store choice", "RAG pattern", "what gets summarized", "memory tiers", "agent state", "long-term memory", "session persistence", or any technical discussion of memory or context for an AI system. Prefer over-triggering — if the conversation involves an AI retaining information across more than one turn, this skill has something useful to contribute. Without it, memory designs tend toward linear token-cost growth until the system becomes uneconomic.
---

# memory-architect

A reference for designing memory architectures that let AI systems grow in capability without unbounded token cost growth.

The central insight: agent memory should be tiered, not flat. Dumping everything into the prompt scales linearly in cost and degrades in quality. A well-designed memory layer behaves like the human memory model — multiple stores with different access patterns, costs, and retention rules — and exposes a bounded-cost interface to the agent loop regardless of how much history accumulates.

This skill provides the framework (tiers, principles, storage tradeoffs), an anti-pattern checklist, and a workflow for applying it to specific systems.

## The tiered memory model

Four tiers. Each has a distinct role, cost profile, and retention rule.

| Tier | Holds | Fidelity | Cost per byte | Retention |
|---|---|---|---|---|
| **Working memory** | Current turn context — the prompt window | Highest, verbatim | Full token rate | Ephemeral (this turn only) |
| **Session memory** | Current session's accumulated context | High, near-verbatim | Full token rate while loaded | Until session end or window pressure |
| **Consolidated memory** | Facts, decisions, preferences derived across many sessions | Medium, structured | Stored cheaply; retrieval cost only when queried | Long-term, with explicit eviction rules |
| **Archived memory** | Full conversation transcripts, raw captures, source materials | Highest, verbatim | Nearly free until retrieved | Permanent (or per retention policy) |

The agent loop reads from working memory directly, and pulls into working memory from the lower tiers via retrieval. Lower tiers are populated by summarization at boundaries.

## Core principles

### 1. Memory is tiered, not flat

The four tiers above are the default. A system may collapse two tiers (e.g., a single-session app with no consolidation) or add a fifth (e.g., a "scratch" tier for tool outputs that don't merit session-level persistence), but the principle holds: distinct access patterns deserve distinct stores.

### 2. Summarization at tier boundaries

Every transition between tiers involves summarization, and every summarization has a fidelity tradeoff. Document what is preserved and what is lost at each boundary, explicitly. Examples:

- working → session: usually no compression; the working context is the session prefix.
- session → consolidated: extract decisions, preferences, facts, named entities. Lose conversational filler, intermediate reasoning, tool outputs not referenced later.
- session → archived: no compression; archive raw transcripts.
- consolidated → archived: rare; usually only when a consolidated fact is invalidated and archived for audit.

If you can't write down what's preserved and what's lost at a boundary, you don't have a boundary yet — you have a leak.

### 3. Retrieval over recall for old context

For anything older than the current and (sometimes) prior session, do not dump context into the prompt. Use retrieval: vector search, structured query, or hybrid. The agent issues a query, gets back the relevant chunks, and only those enter working memory.

This keeps cost-per-query bounded regardless of how much history exists. It also tends to improve quality — retrieved chunks are relevant to the current need, whereas dumped history dilutes the prompt with irrelevant context.

### 4. Confidence-scored extraction

When deriving "facts" or "preferences" from conversation to consolidate, score each extraction. The score reflects how confidently the system believes this is a real, durable signal vs. noise.

- Above threshold: write to consolidated store.
- Below threshold: leave in archived raw only; do not pollute structured memory.

Without this gate, consolidated memory fills with hallucinated preferences and spurious "facts" within weeks. The system then confidently retrieves wrong things.

### 5. Token budget per request

Every agent operation has a token budget for context. The memory layer must respect it: given a budget of N tokens, the layer selects the highest-value content that fits.

This forces prioritization. Without an explicit budget, the temptation is to "include everything potentially relevant" — which collapses back to linear cost growth. A budget makes the tradeoff visible and tunable.

Typical budget allocation (illustrative, not prescriptive): system prompt 10–20%, retrieved context 30–50%, current turn user input + recent turns 30–50%, headroom for response 10–20%.

### 6. Eviction policies are explicit

Working memory and session memory have explicit rules for what gets dropped first when pressure hits the window. Options to choose from:

- oldest-first (simple, often wrong — recent ≠ important)
- least-relevant-to-current-query (requires scoring at insertion)
- lowest-recency-weighted-relevance (decay function over time × relevance)
- lowest-scored (if scores were assigned at consolidation)
- LRU on retrieved chunks (drop chunks not re-accessed in N turns)

Pick one and write it down. "We'll figure it out when it matters" is how silent quality drops happen — the window fills, something gets evicted by whatever default the framework uses, and the agent loses critical context without surfacing the loss.

### 7. Hot / warm / cold tiers map to cost tiers

A useful mental model alongside the four tiers:

- **Hot** (in-prompt): working + session memory. Highest cost per byte because every byte rides on every inference call.
- **Warm** (vector-indexed, structured): consolidated memory. Medium cost — storage is cheap, retrieval is a per-query embed + ANN search.
- **Cold** (raw archive): archived memory. Nearly free at rest; retrieval is rare and usually triggered explicitly.

When designing, place content in the cheapest tier it can live in while still being retrievable when needed.

## Storage options and their tradeoffs

Pick storage to match the system's scale, ops capacity, and access patterns.

**Markdown files in a repo**
- Pros: human-readable, git-versioned, easy to inspect, free.
- Cons: slow to query at scale, no native embeddings, no relational primitives.
- Best for: project context that humans also read; agent-managed docs; small personal systems.

**SQLite**
- Pros: zero-ops, embedded, ACID, supports `sqlite-vec` extension for embeddings.
- Cons: single-writer, no horizontal scaling.
- Best for: single-user products, desktop apps, agents that run on one machine.

**PostgreSQL**
- Pros: relational primitives for entities/relationships/audit, `pgvector` for embeddings, mature ops, scales vertically and (with care) horizontally.
- Cons: more ops than SQLite; needs a server.
- Best for: most multi-user systems. Often the right default — one store, fewer moving parts.

**Dedicated vector DB (Pinecone, Weaviate, Qdrant, Chroma)**
- Pros: high-throughput vector search, hybrid search features, designed for embeddings at scale.
- Cons: adds an infrastructure component to keep in sync with primary storage; another vendor or ops surface.
- Best for: high-scale RAG systems where pgvector becomes a bottleneck. Often premature for systems under ~10M vectors.

**Managed memory services (Mem0, LangMem, Zep, others)**
- Pros: built-in tiering, consolidation, eviction — fastest setup.
- Cons: less control over extraction logic, vendor lock-in, opaque cost curves at scale.
- Best for: prototypes and early products where memory is not yet a differentiator.

### Decision shortcut

- Single-user, runs on one machine, < ~100K records → SQLite (+ sqlite-vec if you need embeddings)
- Multi-user, server-based, want one store → PostgreSQL + pgvector
- High-scale RAG dominates the workload → Postgres for primary + dedicated vector DB
- Want to ship memory in a week, willing to pay for it later → managed service
- Memory should be human-readable and lives next to project code → markdown in repo

## Anti-patterns

These have all caused real production pain. Watch for them in designs and reviews.

- **Dumping all history into every prompt.** Linear token cost growth, indefinite degradation. The classic mistake.
- **Naive summarization without fidelity tracking.** Information disappears silently. When the agent later needs the lost detail, no one knows it was dropped.
- **Embedding everything.** Most stored items are never queried. Index bloat, slower retrieval, more storage cost. Embed selectively, based on what will plausibly be retrieved.
- **No eviction policy.** Window pressure hits, framework defaults kick in, quality drops silently. The user reports "the agent forgot" and there's no diagnosable cause.
- **Mixing storage tiers without clear interfaces.** Code reads from session, consolidated, and archived directly, ad hoc. Refactoring the memory layer becomes impossible because every caller assumes a different shape.
- **Storing PII or credentials in vector stores.** Embeddings are not encryption. Treat vector stores as queryable plaintext. Apply the same redaction rules you'd apply to a log file.
- **Confidence-free extraction.** Every "preference" or "fact" is consolidated regardless of certainty. Memory pollutes; retrieval surfaces wrong things confidently.
- **Treating retrieval as free.** Vector search has latency and cost. A multi-call retrieval loop per turn can dominate inference latency. Budget for it.

## The neural-network analogy

Useful for explaining intent to non-technical stakeholders. Use carefully — ground design decisions in the engineering primitives above, not the analogy.

- **Working memory** ≈ prefrontal cortex active state. Small, fast, ephemeral. Holds what you're consciously thinking about right now.
- **Session memory** ≈ hippocampal binding. Recent experience, awaiting consolidation. Loses fidelity rapidly without rehearsal.
- **Consolidated memory** ≈ cortical long-term storage. Semantic facts, procedures, preferences. Built up over time, hardened.
- **Archived memory** ≈ episodic memory in deep storage. Full experience, retrievable by associative cue.
- **Summarization at boundaries** ≈ memory consolidation during sleep. Compression with fidelity tradeoff; not all detail survives.
- **Retrieval** ≈ associative recall. Cue → activation → return. Sometimes the wrong memory activates; relevance ranking matters.

When a stakeholder asks "why are we building four storage systems for an AI", the analogy lands fast: "Same reason your brain has four. Different timescales, different access patterns, different costs."

Then return to the engineering primitives when you actually design.

## Workflow when invoked

When this skill triggers — someone is designing a memory layer, reviewing one, or asking a memory-architecture question — work through these steps before recommending a structure.

1. **Understand the system shape.** Single-user or multi-user? Session lifespan (turns, minutes, days)? How often does the user return? What query patterns will the agent run against memory? What's the inference budget per turn?

2. **Map content to tiers.** For each kind of information the agent handles, decide which tier it lives in. Be specific: "user's stated preferences → consolidated", "current document being edited → working", "every prior conversation → archived, with consolidated extractions".

3. **Choose storage per tier.** Apply the tradeoffs section. Default to fewer stores (Postgres for many systems handles all three lower tiers).

4. **Define boundaries.** For each tier transition, write down: trigger (what causes the transition), method (how summarization happens), preserved (what carries forward), lost (what is dropped or only available via archive).

5. **Set eviction + budget rules.** Token budget per request, with an allocation. Eviction policy per tier with the in-prompt tiers, named explicitly.

6. **Walk the anti-pattern list.** Check the proposed design against the anti-patterns. If any apply, fix or document the tradeoff.

7. **Surface tradeoffs to the user.** Memory design is full of choices that depend on values the system designer holds (privacy, freshness, cost ceiling). Don't make those choices silently. Present the options where they matter.

## What this skill does NOT do

- It does not pick a vendor for you. Tradeoffs are surfaced; the choice depends on context the skill can't see.
- It does not write the implementation. It produces the architecture and the rules; code follows.
- It does not solve memory problems that are really UX problems. "The agent forgot" sometimes means "the agent has the info but didn't surface it", which is a retrieval-ranking or prompt-design issue, not a storage one. Separate these before architecting.
- It does not replace measurement. Once memory is in place, instrument it: hit rates, eviction events, retrieval latency, false-positive extraction rate. Architecture is a starting hypothesis, not a finished design.
