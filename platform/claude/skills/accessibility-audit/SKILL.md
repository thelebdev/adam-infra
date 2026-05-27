---
name: accessibility-audit
description: WCAG 2.1 AA accessibility audit checklist against a UI. SECONDARY skill — always ask before implementing fixes. Use when explicitly requested.
---

# Accessibility audit

## When to use

When I explicitly ask for an audit. Don't auto-trigger.

## Self-update on invocation

1. WebSearch for "WCAG 2.2 status" and "accessibility best practices 2026".
2. Propose updates. Apply with my approval.

## Steps

Audit, don't fix. Report findings categorized as: blockers (would fail WCAG 2.1 AA), warnings, suggestions.

### Perceivable
- [ ] All non-text content has text alternatives.
- [ ] Color contrast: 4.5:1 for normal text, 3:1 for large text.
- [ ] Don't rely on color alone for meaning.
- [ ] Content reflows at 320px width without horizontal scroll.
- [ ] Text resizable to 200% without loss of content.

### Operable
- [ ] All functionality available via keyboard.
- [ ] Focus visible on every interactive element.
- [ ] Focus order matches visual order.
- [ ] No keyboard traps.
- [ ] Skip-to-content link exists.
- [ ] Sufficient time on time-limited interactions, or no time limits.
- [ ] No content flashes more than 3x/second.

### Understandable
- [ ] Language of page declared.
- [ ] Form inputs have labels associated programmatically.
- [ ] Error messages identify the field and the issue.
- [ ] Consistent navigation across pages.
- [ ] Predictable focus and input behavior.

### Robust
- [ ] Semantic HTML (h1-h6 hierarchy, landmarks, lists for lists).
- [ ] ARIA used correctly, sparingly. (Don't use ARIA when HTML suffices.)
- [ ] No invalid HTML.
- [ ] Status messages programmatically announced (aria-live regions where appropriate).

## Steps after audit

1. Report findings. Don't fix.
2. STOP. Ask which issues to address.
3. Implement approved fixes one batch at a time.

## Checkpoints

- ALWAYS ask before implementing any fix.
- NEVER auto-add ARIA — it's often worse than no ARIA.

## Related skills

- `component-conventions`
- `ux-review`

<!-- last_reviewed: 2026-05-12 -->
