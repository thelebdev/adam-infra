# ADR-0001: Authelia + Caddy + ttyd for operator access

**Status:** Accepted (delivered; documented in `docs/ROADMAP.md` under "Recently delivered" → "Better secure-access mechanism").
**Date:** delivered prior to 2026-05-25 per ROADMAP cadence; this ADR is a backfill of the load-bearing decision.
**Deciders:** Chris (operator), overall-infra-architect.

## Context

The original platform exposed dashboards behind Caddy with basic auth and required SSH for terminal access. Two operational frictions pushed against that:

- Basic auth has no second factor; a leaked password is a compromised dashboard.
- Reaching the box from a phone or unfamiliar device required an SSH client, which is friction in moments where the operator needs a terminal *now*.

## Decision

Adopt **Authelia + Caddy `forward_auth` + ttyd** as the operator-access architecture:

- **Authelia** at `auth.<PRIMARY_DOMAIN>` as the SSO portal. Password plus mandatory TOTP. Single source of truth for user identity.
- **Caddy** gates every public subdomain via `forward_auth` to Authelia. No subdomain is exposed without going through it. ACME via Let's Encrypt for TLS.
- **ttyd** at `sessions.<PRIMARY_DOMAIN>` serves browser terminal sessions. Each session is backed by a tmux session that survives refresh, logout, or dropped connection. The `session` helper enforces per-user tmux sockets keyed off `$TTYD_USER` (from `ttyd -H Remote-User`) and confines new sessions to `WORKSPACE_ROOT`. Each browser tab is `?arg=<name>` for independent sessions.

## Consequences

- Every dashboard (Dozzle, Glances, ntopng, Grafana on the full profile) sits behind one SSO. Login once, every tool open until session expiry (1 hour absolute, 30 min idle).
- The box is reachable from any device with a browser. No SSH client needed for routine work.
- Single point of access is also a single point of failure: if Authelia is down, every gated surface is down. Authelia is now a tier-0 service and must be monitored, backed up, and DR-rehearsed alongside Caddy.
- A new-operator onboarding step (TOTP enrollment) is required and gated through `platform/authelia/add-user.sh`.
- The Caddy `forward_auth` identity-header spoof family (e.g., CVE-2026-30851) becomes a class of risk Infra must explicitly defend against — hardened in `platform/caddy/` to strip inbound identity headers before forwarding, so an upstream client cannot forge them.

## Alternatives considered

- **Stay on basic auth + SSH-only terminals.** Rejected: no second factor on the HTTP surface; SSH-only is high friction on phones and tablets, which the operator regularly uses.
- **Wider alternatives (mesh VPN, Tailscale, Cloudflare Tunnel).** Not formally evaluated at decision time. Acceptable to revisit if Authelia operational cost ever exceeds its value; until then, on-box self-hosted SSO is the design intent (no third-party identity dependency).
