---
name: add-mcp-server
description: Scaffolds a new MCP (Model Context Protocol) server. Use when exposing tools to Claude, Claude Code, or other LLM clients across a process or network boundary. Don't use for tools that live inside the same agent process — use direct PydanticAI tools for that.
---

# Add an MCP server

## When NOT to use

If the tool only needs to be called by one agent in one process, use a direct PydanticAI/SDK tool instead. MCP earns its place when:
- Multiple agents share the tool, or
- The tool runs in a different process/machine/language, or
- The user wants the tool available from Claude Desktop / Claude Code.

If none apply, push back and propose a direct tool instead.

## Self-update on invocation

1. WebSearch for "MCP server best practices 2026" and "Anthropic MCP SDK".
2. Check for newer transport options (stdio, SSE, streamable HTTP) and current recommendations.
3. Propose updates. Apply with my approval.

## Steps

1. Confirm: what's the tool's single responsibility? (One server, one bounded capability.)
2. Pick language. Match the language of the system being exposed.
3. Pick transport:
   - `stdio` for local tools called by Claude Code / Claude Desktop.
   - `streamable HTTP` for remote tools, multi-client.
4. Layout (Python example):
   ```
   src/<server_name>/
     __init__.py
     server.py         # MCP server bootstrap
     tools/            # one file per tool
     resources/        # if exposing resources
     auth.py           # if HTTP transport with auth
   ```
5. Tool definitions: name + description + JSON schema for inputs. The description is what the LLM sees — be specific about when to call this tool and what it returns.
6. Tool output: always structured, never raw strings unless that's the contract.
7. Error handling: every tool catches its own exceptions, returns a clear error result. Never crash the server on a bad tool call.
8. Logging: structured. Log every tool invocation with args (redacting sensitive fields) and result status.
9. Auth (HTTP transport only): bearer token or OAuth, never basic auth.
10. Add an `mcp.json` config example showing how to wire it into Claude Desktop / Claude Code.
11. Test with the MCP inspector tool before claiming it works.

## Checkpoints

- ASK before adding tools that write external state (CRM, payments, anything with side effects).
- ASK before deploying an HTTP MCP server publicly — auth needs review.

## Related skills

- `add-observability`
- `harden-for-production`

<!-- last_reviewed: 2026-05-12 -->
