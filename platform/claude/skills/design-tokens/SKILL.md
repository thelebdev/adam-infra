---
name: design-tokens
description: Sets up design tokens (colors, spacing, typography, radii, shadows) for a new project. Asks for project-specific brand inputs or uses the configured default brand source if user picks Default. Use when starting any frontend project.
---

# Design tokens setup

## Self-update on invocation

1. WebSearch for "design tokens best practices 2026" and current standards (W3C design tokens format, Style Dictionary, etc.).
2. Propose updates. Apply with my approval.

## Steps

1. Ask me which mode to use:
   - **Default**: Use the configured default brand source. (See "fetch defaults" below.)
   - **Custom**: Walk through a series of questions for this specific project.
   - **From screenshots/palettes**: I'll provide reference images, you derive tokens from them.

### Fetch defaults (Default mode)

1. Ask me for the default brand source URL (or read `DEFAULT_BRAND_URL` from the environment if set). WebFetch it to extract current brand colors and typography.
2. If the URL is unreachable or unset, ask me to paste the hex values and font names.
3. Use those as the project defaults.

### Custom mode questions (ask in this order, one at a time)

1. Primary brand color (hex or describe the mood).
2. Secondary/accent color, if any.
3. Neutral palette preference: warm gray, cool gray, true gray.
4. Mood/tone: serious, playful, technical, luxurious, friendly.
5. Typography: do you have specific fonts, or pick from current best-practice pairings?
6. Border radius vibe: sharp (0-2px), rounded (4-8px), pill-friendly (12px+).
7. Dark mode required at launch, or light-only is fine?

### From screenshots/palettes

1. Ask me to upload references.
2. Identify the dominant palette (3-5 hues), typography, spacing rhythm.
3. Propose token values. Wait for approval.

## Output

Generate a tokens file in the format the framework expects:
- Next.js + Tailwind: `tailwind.config.ts` with extended theme + `app/globals.css` with CSS variables.
- CSS-only: `tokens.css` with CSS custom properties.
- Design Tokens W3C format: `tokens.json` if generating cross-platform.

Include:
- Color: brand, neutral, semantic (success, warning, error, info), states (hover, focus, disabled).
- Spacing scale (4-based or 8-based; ask).
- Typography: families, sizes, weights, line heights.
- Radius scale.
- Shadow scale.
- Z-index scale.
- Motion tokens (durations, easings).

## Checkpoints

- ASK at every major choice in Custom mode.
- ASK before introducing dark mode tokens (doubles the surface area).

## Related skills

- `component-conventions`
- `responsive-design`

<!-- last_reviewed: 2026-05-12 -->
