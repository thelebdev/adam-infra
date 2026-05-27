---
name: design-handoff
description: Implementation checklist when converting a design (Figma, screenshot, mockup) to code. Use when starting from a visual design. Always asks about specific elements before implementing.
---

# Design handoff

## Steps

1. Ask which design source: Figma file, exported screenshots, sketch, hand-drawn mockup.
2. For each screen / component in the design:
   - Ask me to confirm: what's reusable (component) vs one-off (page).
   - Ask: what's data-driven vs static.
   - Ask: what interaction states exist (hover, focus, active, disabled, loading, error).
   - Ask: what responsive behavior is intended at each breakpoint.
   - Ask: what's animated, and how.
3. Extract design tokens first (see `design-tokens` skill) — colors, spacing, typography, radii from the source.
4. Build out components bottom-up:
   - Atoms first (buttons, inputs, labels).
   - Then molecules (form rows, cards).
   - Then organisms (forms, headers).
   - Then templates / pages.
5. Implement each piece with:
   - Static version first (matches design pixel-close-ish).
   - Then make it responsive.
   - Then make it accessible.
   - Then wire it to data.
   - Then add interaction states.
6. Compare to the design at each stage. Side-by-side screenshots are fine.

## Things to always ask explicitly

- "Is this the final padding/spacing or approximate?"
- "What should this do when there's no data?"
- "What should this do when there are 100 items?"
- "Does this scroll or paginate?"
- "Is this color the actual brand color or a placeholder?"

## Checkpoints

- STOP at each major component for review before moving on.
- ASK before guessing at any unspecified state.

## Related skills

- `design-tokens`
- `component-conventions`
- `responsive-design`
- `accessibility-audit`
- `ux-review`

<!-- last_reviewed: 2026-05-12 -->
