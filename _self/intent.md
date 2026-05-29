# Intent

Infra exists to make the operator's substrate setup repeatable, recoverable, and inspectable. The starting form was narrow — take a bare Ubuntu VPS to a fully provisioned, hardened, observable server in 10 minutes. The trajectory is broader: a vehicle on the software lane, the system that extends the operator's reach across machines and projects, so that anything the operator hosts is hosted with the same defaults, the same auth, the same observability, the same disaster-recovery story. Infra is what makes "spin up a new server for X" not be a multi-day project.

The operator relationship to Infra is *tool*, not *chief-of-staff*. Brain is the cognitive layer that proposes and decides with the operator; Infra is the substrate that runs underneath whatever the operator decides to deploy. Infra is operated by the human operator (with apprentice-steward AI assistance), not by other tissues. Where Brain is conversational and judgement-laden, Infra is declarative, deterministic, and inspectable. The operator should always be able to read a bootstrap script and know exactly what it will do.

The principles that should survive any v2:

- **Idempotent operations only.** Every script is re-runnable safely. No "run once" steps without loud documentation explaining why.
- **Fail-closed at every gate.** Authelia gates HTTP, SSH gates terminal, TLS gates transport. A misconfigured gate stops; it never opens.
- **Secrets out of the repo.** `.env.example` is canonical and empty; `.env` is gitignored. The operator's secret store is the source of truth.
- **Documentation is the product.** Every change ships docs in the same brief. A new operator (human or AI) should be productive in 2 hours using only the repo.
- **Platform/application boundary sacred.** Platform changes affect every application. Application concerns must not creep into platform code.
- **Observability before everything.** New platform services do not deploy without logging, monitoring, and alerting in place.
- **Failure rehearsal is mandatory.** The 10-minute disaster-recovery SLA is the supreme test; quarterly dry-runs against a fresh VPS keep it real.
- **Apprentice-steward register.** The architect AI proposes; the operator approves. No silent execution of infrastructure changes.

Implementations are disposable. v1 is a bash-script + systemd + Docker Compose stack. v2 may be NixOS, declarative host state, or something not yet invented. What survives v1 is not the choice of bash or Docker: it is the principles above, the 10-minute SLA, the platform/application boundary, the operator-on-any-device workflow (browser-native, not SSH-only), the secrets discipline, and the operator-acceleration trajectory beyond pure bootstrap.

When in doubt about scope, Infra should err toward operator-acceleration *for the operator*, not toward automating-the-operator-away. Infra makes Chris faster across his systems; it does not act on his behalf.
