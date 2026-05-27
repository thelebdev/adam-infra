---
name: responsive-design
description: Mobile-first responsive design conventions and breakpoint patterns. Use when building any UI.
---

# Responsive design

## Self-update on invocation

1. WebSearch for "responsive design best practices 2026", "container queries adoption 2026".
2. Propose updates. Apply with my approval.

## Principles

- **Mobile first, always.** Write the smallest viewport's CSS as the base, layer up with min-width media queries.
- **Content first.** Decide what's most important on small screens; large screens get progressive enhancement.
- **Container queries over media queries** when a component's layout depends on its container, not the viewport.
- **Fluid > breakpoints** where possible. `clamp()` for typography, `min()`/`max()` for sizing.

## Breakpoint conventions

Default scale (Tailwind-style, adjust per project):
- `sm`: 640px (large phones, small tablets)
- `md`: 768px (tablets)
- `lg`: 1024px (small laptops)
- `xl`: 1280px (desktops)
- `2xl`: 1536px (large desktops)

Only branch at breakpoints when the layout *needs* to change. Don't pre-emptively add breakpoints.

## Patterns

- **Stack on mobile, side-by-side on larger**: flex-direction column → row.
- **Grid with auto-fit**: `grid-template-columns: repeat(auto-fit, minmax(280px, 1fr))` adapts without media queries.
- **Hide on mobile, show on desktop** (or vice versa): only when truly necessary; first try to design something that works at both.
- **Navigation**: hamburger on mobile, expanded on desktop. Always keyboard-accessible.
- **Tables**: horizontal scroll on mobile is acceptable. Or transform to cards.
- **Modals**: full-screen on mobile, dialog on desktop.

## Testing

- Test at 320px, 375px, 768px, 1024px, 1440px.
- Test with browser zoom at 200%.
- Test landscape and portrait on mobile sizes.
- Test with both touch and mouse input.

## Checkpoints

- ASK before using media queries based on device features (touch, hover, pointer) — they have edge cases.
- ASK before fixing aspect ratios that might clip content at unusual sizes.

## Related skills

- `accessibility-audit`
- `design-tokens`

<!-- last_reviewed: 2026-05-12 -->
