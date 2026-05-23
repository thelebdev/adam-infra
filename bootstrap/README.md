# Bootstrap scripts

Ordered scripts that take a bare Ubuntu 24.04 VPS to a fully operational platform.

## Sequence

`00-prerequisites` → `01-user-and-ssh` → `02-firewall` →
`03-kernel-hardening` → `04-docker` → `05-authelia` → `06-caddy` →
`07-ttyd` → `08-observability` → `09-claude-code` → `10-dashboard` →
`11-session-manager` → `99-verify`, plus the `bootstrap.sh` orchestrator and
`lib/common.sh`.

See `docs/BOOTSTRAP.md` for the canonical order, privilege model, and
prerequisites.

## Design rules

- Every script is idempotent.
- Every script writes structured logs to `/var/log/infra/<script-name>.log`.
- Every script updates the relevant doc when it introduces a change.
- The orchestrator `bootstrap.sh` runs all numbered scripts in order;
  individual scripts can also be run in isolation.
