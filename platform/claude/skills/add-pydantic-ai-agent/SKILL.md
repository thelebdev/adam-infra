---
name: add-pydantic-ai-agent
description: Adds a PydanticAI agent to an existing service with conventions for memory, tool integration, structured outputs, and observability. Use when adding an LLM-powered feature to a project. Triggers on "add agent", "add AI", "integrate Claude", "LLM feature".
---

# Add a PydanticAI agent

## Self-update on invocation

1. WebSearch for "PydanticAI best practices 2026" — framework still recommended? Alternatives matured?
2. WebSearch for current Anthropic / OpenAI model lineup and pricing — defaults stale fast.
3. Propose updates. Apply with my approval.

## Steps

1. Confirm: what does this agent do? (One job per agent.)
2. Define the agent profile in code or DB:
   - System prompt (start short, expand only when needed)
   - Tools (start with the minimum)
   - Model: default to current Sonnet-equivalent for routine work, Opus-equivalent for hard reasoning
   - Structured output schema (Pydantic model)
3. Memory:
   - Always implement at least Tier 1 (active conversation history).
   - Add Tier 2 (rolling summary) when conversations regularly exceed 15 turns.
   - Tier 3 (customer profile) when same user interacts repeatedly across conversations.
   - Tier 4 (episodic vector memory) only when actually needed.
4. Tool integration:
   - Direct tools (`@agent.tool`) for in-process functions.
   - MCP for cross-process or shared tools (see `add-mcp-server` skill).
   - Every tool: name, description, Pydantic input schema, structured output.
5. Logging: every agent run logged with input snapshot, output, tokens, cost, latency.
6. Cost controls:
   - Per-turn token budget (cut off at threshold).
   - Per-conversation token budget.
   - Model routing: cheap model for routine, expensive only when needed.
7. Rules layer: pre-response and post-response validation against business rules.
8. Tests:
   - Unit tests for each tool.
   - Integration tests for the agent loop with mocked LLM responses.
   - Eval suite: 20+ real-world prompts with expected behavior. Run on every change.

## Checkpoints

- ASK which model tier to default to.
- ASK before increasing the token budget if existing one is being hit.
- ASK before exposing the agent to public traffic.

## Related skills

- `add-mcp-server`
- `add-observability`
- `harden-for-production`

<!-- last_reviewed: 2026-05-12 -->
