# Interface

What Infra exposes to the rest of Adam-the-being, and to the broader set of applications it hosts.

This file is intentionally rough. Infra is a substantial repo, but the contract it offers to *consumers* (applications, other tissues) is still developing. Most of the surface today is for the operator running setup, not for other software systems calling into Infra. The hardening trigger is the first real cross-tissue or non-Brain application integration.

## Operator-facing surfaces

### Bootstrap CLI

- `./bootstrap/bootstrap.sh` — the orchestrator. Idempotent, structured logs to `/var/log/infra/`.
- `./bootstrap/99-verify.sh` — green-light check after a bootstrap or DR rebuild.
- `./bootstrap/NN-<component>.sh` (`00`–`12`) — per-step scripts, each independently re-runnable.

### Browser-native operator workflows (Authelia-gated)

- `https://auth.<PRIMARY_DOMAIN>` — Authelia SSO portal (password + TOTP).
- `https://sessions.<PRIMARY_DOMAIN>?arg=<name>` — ttyd + tmux browser terminal sessions, per-user, persistent across refresh/disconnect.
- `https://<PRIMARY_DOMAIN>` and `https://dashboard.<PRIMARY_DOMAIN>` — platform dashboard indexing every tool.
- Observability dashboards (Dozzle, Glances, ntopng, Grafana on the full profile).

### Operator-local extension points

- `platform/caddy/Caddyfile.d/*.caddy` — drop a `.caddy` fragment per application vhost (the import directory is tracked via `.gitkeep`; contents are gitignored).
- `platform/authelia/add-user.sh` — onboard a new Authelia user (password + TOTP enrollment).
- `applications/registry.yml` — declare an application tenant.
- `~/.claude/` deployment via `bootstrap/12-claude-skills.sh` — mirrors a curated skill / command / hook library and starter templates into each operator's home.

## Application-facing contract (the platform/application boundary)

The architect skill states the boundary as sacred: platform changes affect every application, so application-specific concerns must not leak into platform code. Today, applications integrate with the platform via:

- **Caddy**: a fragment in `platform/caddy/Caddyfile.d/` declaring their public hostnames and Authelia policy (`one_factor` / `two_factor` / `bypass`).
- **Observability**: container labels for Loki + Promtail log capture; standard Prometheus endpoints for metrics scraping.
- **Backup (planned)**: registered volumes in `platform/backup/registry.yml` once backup orchestration lands.

This contract is intentionally minimal — application authors should not need to know Caddy or Authelia internals, only to declare what they need. It will harden when the second non-Brain application onboards.

## What's NOT exposed

- A formal API for cross-tissue communication. Today, "cross-tissue" means "cross-application on the same host"; there is no inter-tissue bus, no shared message broker, no contract beyond "Caddy + container labels".
- A surface for Brain (or any other tissue) to drive Infra automation. Infra is operated by the human operator (with apprentice-steward AI assistance), not by other tissues.

## Hardening trigger

The application-facing contract is revised the first time an application other than Brain (or a second instance of one) actually onboards. The cross-tissue contract is revised the first time a real cross-tissue integration is needed, not before.
