---
name: component-conventions
description: Component design conventions — naming, prop API, composition patterns, file structure. Use when creating frontend components.
---

# Component conventions

## Self-update on invocation

1. WebSearch for "React component patterns 2026" or framework-equivalent.
2. Propose updates. Apply with my approval.

## Naming

- PascalCase for component files and exports: `OrderSummary.tsx`.
- One component per file, named the same as the file.
- Subcomponents in the same file if tightly coupled, separate files if reusable.

## File structure

```
components/
  OrderSummary/
    OrderSummary.tsx         # the component
    OrderSummary.test.tsx    # unit tests
    OrderSummary.stories.tsx # storybook if used
    index.ts                 # re-export
```

For very simple components, a flat structure is fine:
```
components/
  Button.tsx
  Card.tsx
```

## Prop API

- Required props first, optional props after.
- Boolean props: positive phrasing (`isOpen`, not `isClosed`).
- Event handlers: `onX` for events the user triggers (`onClick`, `onSubmit`).
- Children: prefer over render props for simple cases.
- Composition > configuration: `<Card><Card.Header /><Card.Body /></Card>` beats `<Card header={...} body={...} />` for anything non-trivial.

## Styling

- Use the project's tokens (see `design-tokens` skill).
- Tailwind utility classes for one-off styling.
- `cva` (class-variance-authority) or current equivalent for variant management.
- Avoid inline styles unless dynamic.

## State

- State as local as possible.
- Lift only when shared.
- No global state unless truly global (theme, auth, current user).
- Server state via TanStack Query (or current best practice — verify).

## Accessibility (always, not optional)

- Semantic HTML elements (`<button>` for buttons, not `<div onClick>`).
- ARIA only when HTML semantics aren't enough.
- Keyboard navigation works.
- Focus visible.
- Labels associated with inputs.

## Tests

- Render tests: confirms it renders without crashing with default props.
- Interaction tests: simulate user actions, assert outcomes.
- Edge cases: empty data, loading, error.

## Checkpoints

- ASK before introducing a new state management library.
- ASK before adding global state.

## Related skills

- `design-tokens`
- `accessibility-audit`
- `responsive-design`

<!-- last_reviewed: 2026-05-12 -->
