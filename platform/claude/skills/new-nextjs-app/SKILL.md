---
name: new-nextjs-app
description: Bootstraps a new Next.js application with current best practices. Use when starting a new web app, frontend, or full-stack project in JavaScript/TypeScript. Triggers on phrases like "new Next.js", "new web app", "new frontend", "new React app".
---

# Bootstrap a new Next.js application

## When to use

Starting any new web-frontend or full-stack JS/TS project.

## Self-update on invocation

1. WebSearch for "Next.js best practices 2026", "Next.js app router patterns 2026".
2. WebSearch for current package manager recommendations (pnpm/bun/npm).
3. WebSearch for current state of server components, server actions, partial prerendering.
4. Propose updates to this skill. Apply with my approval.

## Steps

1. Confirm project name, purpose, and whether it's static, SSR, or hybrid.
2. Run `create-next-app` with current recommended flags (TypeScript, App Router, Tailwind, ESLint).
3. Verify Node version target matches current LTS.
4. Project layout:
   ```
   src/
     app/                  # app router
     components/           # shared components
     lib/                  # utilities, clients
     server/               # server-side only code
     hooks/
   public/
   tests/
     unit/
     e2e/                  # Playwright by default unless reason otherwise
   ```
5. Run `design-tokens` skill to set up the design system foundation.
6. Run `component-conventions` skill to document component patterns.
7. Add `.env.example` documenting every required env var.
8. Add `Dockerfile` only if not deploying to Vercel/Cloudflare. Ask which deploy target.
9. Add Playwright for E2E tests, or current best-practice equivalent.
10. Add Vitest for unit tests, or current best-practice equivalent.
11. Configure CSP, security headers in `next.config.js`.
12. Initial commit using conventional commit format.

## Checkpoints

- ASK which deploy target (Vercel, Cloudflare Pages, self-hosted, Hetzner).
- ASK before adding state management library (most apps don't need one).
- ASK before adding component library (shadcn/ui is current default; verify via WebSearch).

## Related skills

- `design-tokens` — design system foundation
- `component-conventions` — component patterns
- `responsive-design` — mobile-first patterns
- `accessibility-audit` — when shipping any UI
- `before-commit` — before every commit

<!-- last_reviewed: 2026-05-12 -->
