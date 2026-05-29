# Identity

**Name:** Infra.
**Kind:** tissue.
**Version:** v1.
**Status:** active.
**Repo:** `thelebdev/adam-infra` (per the manifest in [adam-meta](../../meta/MANIFEST.md)).

## What Infra is today

Infra is a forkable platform-bootstrap repo. The README's claim is the load-bearing one: a fresh Ubuntu 24.04 VPS reaches a fully provisioned, hardened, observable, secure-by-default server in ~10 minutes via `./bootstrap/bootstrap.sh`. The bootstrap is idempotent, fail-closed at every gate (Authelia SSO + TOTP, key-only SSH, UFW rate-limited, Caddy in front of every public surface), and produces a hosting substrate that is intentionally application-agnostic. Installed today: SSH hardening (key-only, UFW, fail2ban), Authelia SSO with password + TOTP, Caddy reverse proxy with automatic TLS gated by `forward_auth`, Docker + Compose, ttyd serving per-user tmux-backed browser sessions at `sessions.<domain>`, a platform dashboard at the apex domain, a tiered observability stack, optional host-installed Claude Code, and an opt-in `~/.claude/` deployment that mirrors a curated skill/command/hook library to every operator's home. Verified end-to-end by `99-verify.sh`. Active workstreams (per `docs/ROADMAP.md`): a security posture monitor, an adversarial Security QA runbook, restic-to-S3 backup orchestration, Alertmanager + SMTP wiring, Authelia email onboarding, a one-shot seed installer.

## Infra is not "Adam's plumbing"

Infra was designed before the Adam-the-being framing existed. It is a general-purpose platform layer, forkable, intentionally not tied to a single operator's domain, provider, or product. Within the tissue/organ taxonomy of Adam-the-being, Infra is the vehicle on the software lane — the substrate Adam-the-being (and any other applications the operator builds) is hosted on. The relationship is application-on-platform: Brain will eventually run as one of many applications on top of Infra. Treating Infra as Adam's bespoke infrastructure would be a category error that broke its forkability and its design intent. The platform/application boundary is sacred — application-specific concerns must not leak into platform code, and Infra changes must not be gated on what Brain happens to need today.
