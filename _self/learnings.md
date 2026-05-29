# Learnings

The running journal of what surprised the builder, what didn't work, what we'd do differently. Each entry is dated, informal, and audit-style — observations, not formal docs. These are the gold for Infra v2 — when this implementation is regenerated, the next AI inherits this file alongside `identity.md` and `intent.md`.

## 2026-05-27 — The bwrap shell-sandbox experiment was removed (~24h after it landed)

**What we tried.** Browser shell sessions ran inside a `bubblewrap` (`bwrap`) jail: rootfs read-only, homes tmpfs, only `~/workspace` writable. A `sudo break` command (sudo password + Authelia TOTP) escaped the jail via `tmux respawn-pane` (commit `6049d24`, "TOTP-only escape via tmux respawn; minimal-mount confinement").

**Why we removed it.** This is a single-admin box. The operator already has full SSH access. A browser-only sandbox added significant complexity (the bwrap mount discipline, the TOTP escape plumbing) and bought no real security: anyone who got the operator's session inside the box could `sudo break` out, and anyone who already had SSH didn't need the browser. The boundary was costing more than it protected. Reverted in commit `aeb6982` ("remove bwrap sandbox + TOTP break-out mechanism") with a follow-up `bd6732d` removing residual config.

**Generalization.** Defense-in-depth has a real cost. On a single-admin box, the right layer is **at the perimeter** (Authelia + TOTP at entry, TLS in transit, a `PreToolUse` git-private-info hook). Layers behind the perimeter that don't change the threat model are complexity tax.

**For v2.** If Infra ever serves multiple non-admin users (Authelia non-admin accounts that should *not* have full host access), the calculus flips and per-user OS-level isolation becomes the right design. Until then: perimeter, not jail.

## 2026-05-25 — The dashboard `/api/*` Authelia gate took three PRs and remains the open ROADMAP item

**What surprised us.** Putting `forward_auth` in front of `/api/*` inside the dashboard's Caddy site block looked trivial. It wasn't. Caddy reorders directives by priority, so `handle /api/*` (higher priority than `route`) preempted `forward_auth` and the API kept returning 401 "missing or ambiguous identity" with a valid SSO cookie present.

**What didn't work.**

- PR #6 wrapped the `authelia_gate` snippet in `route { }` — still routed wrong.
- PR #7 fixed an unrelated tmux 3.x escape-byte parsing bug masking the symptom — surfaced the real ordering issue.
- PR #8 moved `route { }` to wrap the entire site block. After merge, the on-disk template had 9 `route {` occurrences but the rendered Caddyfile only had 2; either `06-caddy.sh` did not re-render, or Caddy did not reload the new file.

**What this taught us.** Caddyfile templates rendered by bootstrap scripts decouple "code change" from "running config." When debugging a routing change, always verify (1) `06-caddy.sh` actually re-rendered, (2) the rendered Caddyfile on disk matches the template's intent, and (3) the *live* Caddy admin API (`127.0.0.1:2019/config/...`) reflects the new directive order. Don't declare a fix shipped from a template-file diff alone.

**For v2.** If the render pipeline grows more complex, ship a "what's running vs. what's on disk" diff tool and run it before declaring any Caddy change merged.

## 2026-05-27 — Reverse the Claude skills sync direction

**What changed.** Originally the `infra` repo was the source of truth for `platform/claude/skills/`, deployed to each operator's `~/.claude/`. We flipped it (commit `41e1348`, "reverse sync direction — ~/.claude/ is source of truth"): `~/.claude/` is now the source, and the sync script mirrors it back into `platform/claude/` for publication.

**Why.** The operator iterates on skills in `~/.claude/` directly (because that's where Claude Code looks). Treating the repo as the source meant every iteration started with a copy-into-repo step before commit. Treating `~/.claude/` as the source means the operator just commits; the repo is the publishable artifact, not the iteration surface.

**For v2.** When a tool's iteration surface and its distribution surface are different, the source of truth is the iteration surface. Don't make the operator copy into the distribution before they can save.

## Trajectory — Infra started as a bootstrap repo and is broader now

The earliest commits frame Infra as "take a bare Ubuntu VPS to fully provisioned in 10 minutes." That core is intact and is still the supreme test. But the active commit stream is no longer purely bootstrap: Claude skills + commands + hooks distributed per operator (`12-claude-skills.sh`), a `PreToolUse` hook that scans `git commit` / `git push` for private info, an `applications/registry.yml` + `Caddyfile.d/` import mechanism for application tenants, an upcoming security posture monitor and adversarial Security QA runbook. Infra is becoming an *operator-acceleration system* whose 10-minute bootstrap is one capability of several. The durable layer should reflect that broader trajectory in `intent.md`; the manifest's "vehicle on the software lane" framing captures the broader scope, the README's "platform layer" framing captures the specific delivery. Both are correct, layered.
