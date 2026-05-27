---
name: ux-review
description: UX review against best practices — form design, loading states, empty states, error states, microcopy, navigation. Use when reviewing a UI implementation.
---

# UX review

## Self-update on invocation

1. WebSearch for "UX best practices 2026".
2. Propose updates. Apply with my approval.

## Review dimensions

### Forms
- [ ] One thing per screen on mobile when possible.
- [ ] Labels visible at all times (not placeholder-only).
- [ ] Inline validation, not just on submit.
- [ ] Validation messages identify the field and the fix.
- [ ] Submit button reflects state (idle, loading, disabled with reason).
- [ ] Show progress for multi-step forms.
- [ ] Don't ask for the same info twice.
- [ ] Autocomplete attributes set correctly.
- [ ] Input types appropriate (email, tel, number, date) so mobile keyboards adapt.

### States
- [ ] Empty state: meaningful, with a call to action.
- [ ] Loading state: skeleton or spinner, never a blank screen.
- [ ] Error state: explains what went wrong AND what to do.
- [ ] Success state: confirms what happened.
- [ ] Partial data state: shows what's loaded, indicates more is coming.

### Microcopy
- [ ] Action verbs on buttons ("Save changes", not "OK" or "Submit").
- [ ] Error messages in plain language, no error codes shown to users (logged for support).
- [ ] Confirmation copy makes the destructive nature clear ("Delete account permanently" not "OK").
- [ ] Help text under fields, not after errors.

### Navigation
- [ ] Current location indicated.
- [ ] Logical hierarchy.
- [ ] Breadcrumbs on deep pages.
- [ ] Back button works as expected (browser, not custom).
- [ ] Keyboard shortcuts for power users on dense screens.

### Performance perception
- [ ] First content visible <1s.
- [ ] Interactions feel instant (<100ms).
- [ ] Loading >1s gets a spinner; >3s gets progress info.
- [ ] Animations enhance, don't slow down.

### Trust signals
- [ ] Pricing transparent before commitment.
- [ ] What happens next is clear at every step.
- [ ] Destructive actions require confirmation.
- [ ] Undo available where possible.

## Steps

1. Review against the checklist.
2. Report findings: blockers, recommendations, nits.
3. STOP. Wait for me to decide what to address.

## Checkpoints

- Don't implement fixes without approval.
- Don't redesign — propose targeted changes.

## Related skills

- `accessibility-audit`
- `component-conventions`

<!-- last_reviewed: 2026-05-12 -->
