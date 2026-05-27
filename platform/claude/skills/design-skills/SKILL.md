---
name: build-feature
description: Used when the user asks to build, add, implement, or create a feature, especially in plain English without technical specifics. Triggers on phrases like "build a", "add a", "implement a", "create a", "make a", "I want", "I need", "can you build", "let's add". Coordinates UI/UX skills automatically so designs aren't an afterthought.
---

# Build a feature (design-aware)

## When to use

Any time the user asks for a feature in plain English, especially without specifying technical or design details. The user expects you to bring design thinking by default, not after they ask twice.

## Steps

1. Parse the request. Does it involve any UI? (forms, screens, components, pages, dashboards, anything visual).
   - If yes → continue this skill.
   - If no (pure backend/CLI/data) → defer to the appropriate technical skill instead.

2. **Before writing any code, summarize in 3-5 bullets:**
   - What the user is trying to accomplish (the underlying job).
   - The UI surfaces involved (which screens, which components).
   - The primary states that need to exist (default, loading, empty, error, success).
   - Any data dependencies (what needs to load before this works).
   - Open questions you have.

3. STOP. Wait for the user to confirm or correct the plan.

4. Once confirmed, invoke these skills in order:
   - `design-tokens` — if the project doesn't have tokens yet, set them up.
   - `responsive-design` — bake mobile-first into the implementation from the start.
   - `component-conventions` — for any new component being created.
   - `ux-review` — review the implementation before declaring done.
   - `accessibility-audit` — only if user explicitly asks (this is a secondary skill).

5. Implement the feature with the conventions from those skills already applied — not retrofitted.

6. After implementation, run a self-review against `ux-review` checklist. Surface any issues you noticed but didn't fix.

## Hard rules

- NEVER skip step 2 (the summary). Plain-English requests almost always have hidden assumptions.
- NEVER ship a UI without: loading state, empty state, error state. Default state alone is incomplete.
- NEVER use raw color values, raw spacing values, or raw font sizes. Always use the project's design tokens.
- NEVER add a feature that breaks responsive behavior at common viewport widths.

## Related skills

- `design-tokens`
- `responsive-design`
- `component-conventions`
- `ux-review`
- `accessibility-audit`
- `add-api-endpoint` (when the feature needs a backend)

<!-- last_reviewed: 2026-05-13 -->
