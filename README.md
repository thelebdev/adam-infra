# infra

The platform layer. Takes a bare Ubuntu 24.04 VPS to a fully provisioned,
hardened, observable server capable of hosting any application stack.

This repo is forkable. It bootstraps **your** VPS with **your** domain and
**your** secrets. Nothing here is tied to a specific provider or product.

---

## Quickstart — launch on a fresh VPS

Land on a new Ubuntu 24.04 VPS and you're operational in ~10 minutes. The
steps below are the whole procedure.

**Before you start, you need:**

- A VPS (Ubuntu 24.04) with an admin (non-root) user that has SSH key access
  and `sudo`.
- A domain you control, with DNS A records pointing at the server's public
  IP: the apex `<domain>` itself, plus `auth.<domain>`, `sessions.<domain>`,
  `dashboard.<domain>`, `dozzle.<domain>`, `glances.<domain>`,
  `ntopng.<domain>`, and `grafana.<domain>` on the full profile. A wildcard
  `*.<domain>` covers the subdomains; the apex still needs its own A record.
  *(Optional — skip if you'll only reach dashboards via SSH tunnel.)*
- (Optional) An Anthropic API key for non-interactive Claude Code auth.

**Steps:**

```bash
# 1. Get the repo onto the server at /opt/infra.
rsync -a --exclude .git ./ <admin>@<server>:/tmp/infra-stage/
ssh <admin>@<server> 'sudo mv /tmp/infra-stage /opt/infra'

# 2. SSH in and create .env from the template (see "Environment" below).
ssh <admin>@<server>
sudo -i
cd /opt/infra
cp .env.example .env
chmod 600 .env
vi .env

# 3. Run the orchestrator. Idempotent, structured logs in /var/log/infra/.
./bootstrap/bootstrap.sh

# 4. Verify.
./bootstrap/99-verify.sh
```

After the firewall step, SSH is rate-limited by UFW (six attempts per
30 seconds drops connections from your IP). If your laptop trips this,
you'll have to wait it out or use the provider web console.

---

## Environment variables (`.env`)

Copy [`.env.example`](.env.example) → `.env` and fill it on the server.
`.env` is gitignored — keep real values in your own secret store (password
manager, vault, secrets manager, private spreadsheet, whatever fits).

**Required to bootstrap:**

| Variable | What it is |
|---|---|
| `SERVER_ADMIN_USER` | The non-root admin user (e.g. `admin`). **Must not be `root`.** |
| `OBSERVABILITY_PROFILE` | `lightweight` (~1 GiB RAM) or `full` (≥ 2 GiB RAM). |

**Required if exposing dashboards publicly via Caddy:**

| Variable | What it is |
|---|---|
| `PRIMARY_DOMAIN` | Domain Caddy serves dashboards under (e.g. `example.com` → `dozzle.example.com`). |
| `CADDY_ACME_EMAIL` | Email for Let's Encrypt cert registration. |

**SSO (Authelia):**

| Variable | What it is |
|---|---|
| `AUTHELIA_USER` | Defaults to `admin`. The login username for the SSO portal. |
| `AUTHELIA_PASSWORD` | Auto-generated 32-char hex if blank. Copy out to your secret store — you'll type it at the login screen. |

**Optional / generated:**

| Variable | What it is |
|---|---|
| `ANTHROPIC_API_KEY` | Lets `09-claude-code.sh` wire non-interactive auth. If blank, run `claude login` once over SSH. |
| `ALLOW_PUBLIC_WEB` | Default `true` so Caddy can serve 80/443. Set `false` for fully internal boxes. |
| `GRAFANA_ADMIN_PASSWORD` | **Full profile only.** Auto-generated if blank. |
| `BACKUP_STORAGE_*` / `BACKUP_ENCRYPTION_PASSPHRASE` | S3-compatible backup target (restic) — wired in when backup orchestration lands. |
| `ALERT_EMAIL`, `SMTP_*` | Alert delivery — wired in when alerting lands. |

---

## What you get after launch

The hardened base always installs; the optional layers below are chosen at
bootstrap (it prompts once, per component, and remembers the answers in
`.env`). The bootstrap installs:

- **Public SSH** (key-only, UFW rate-limited, fail2ban).
- **Authelia SSO** with password + TOTP, gating every public subdomain.
- **Caddy reverse proxy** with automatic TLS, consulting Authelia on every
  request via `forward_auth`.
- **Docker + Compose v2** with log rotation.
- **ttyd web terminal** serving per-user browser sessions at
  `sessions.<PRIMARY_DOMAIN>` — every session is a plain login shell
  started in the workspace directory you choose. No SSH client needed.
  Persistent via tmux: a refresh or dropped connection never kills a
  session. (No in-session sandbox — this is a single-admin box, the
  operator has SSH anyway, and a browser-only sandbox would cost a lot
  of complexity for no real security gain. Authelia gates entry; TLS
  gates transport.)
- **Platform dashboard** at `<PRIMARY_DOMAIN>` and
  `dashboard.<PRIMARY_DOMAIN>` — a landing page indexing every tool above,
  with a live "Terminal sessions" panel for list / start / stop.
- **Observability stack** (profile-selectable, dashboards bound to
  `127.0.0.1` internally, reached through Caddy).
- **Claude Code** on the host for the admin user — optional. Run
  `claude` from a browser terminal session, or directly over SSH on the
  host. Same binary either way.

### Login flow (browser, any device)

1. Open any of the URLs below.
2. Caddy bounces you to `https://auth.<PRIMARY_DOMAIN>`.
3. Enter username + password + 6-digit TOTP code (from your authenticator
   app — 1Password, Authy, Aegis, etc.).
4. Caddy bounces you back to the URL you wanted.

The session cookie is valid for 1 hour (30 min inactivity), so once you've
logged in, every dashboard and the Claude terminal are open until expiry.

### URLs

| What | URL |
|---|---|
| **SSO login portal** | `https://auth.<PRIMARY_DOMAIN>` |
| **Platform dashboard** (tool index) | `https://<PRIMARY_DOMAIN>` · `https://dashboard.<PRIMARY_DOMAIN>` |
| **Terminal sessions (browser)** | `https://sessions.<PRIMARY_DOMAIN>` |
| **Dozzle** (container logs) | `https://dozzle.<PRIMARY_DOMAIN>` |
| **Glances** (host metrics) | `https://glances.<PRIMARY_DOMAIN>` |
| **ntopng** (traffic/DPI) | `https://ntopng.<PRIMARY_DOMAIN>` |
| **Grafana** *(full profile)* | `https://grafana.<PRIMARY_DOMAIN>` — login with `GRAFANA_ADMIN_PASSWORD` |

The subdomain labels above (`auth`, `sessions`, …) are defaults — `bootstrap.sh`
can set a custom label per component (the `SUBDOMAIN_*` flags).

Without `PRIMARY_DOMAIN`, dashboards are localhost-only and Authelia/Caddy
are skipped. SSH-tunnel to view:

```bash
ssh -L 8080:localhost:8080 <server>      # then open http://localhost:8080
```

### TOTP enrollment

On the first run of `bootstrap.sh`, `05-authelia.sh` prints a QR code to
your terminal **once**. Scan it into your authenticator app. The
`otpauth://` URI is also saved at `/opt/infra/.authelia-enrollment`
(root-readable, mode `0600`) — back it up to your password manager so you
can re-enroll a new device later.

### Adding more users

The bootstrap seeds one operator account. Add more Authelia users from an
SSH session on the server:

```bash
sudo /opt/infra/platform/authelia/add-user.sh <username>
```

It sets the password, enrolls a TOTP device, and prints the QR.

### Server access (terminal)

- **SSH:** `ssh <admin>@<server>` with the admin user's key. Unchanged by
  Authelia (which gates only the HTTP layer).
- **Browser:** `https://sessions.<PRIMARY_DOMAIN>` → Authelia login → menu
  to open or start a sandboxed shell session. Inside the shell, `claude`
  (TOTP-gated) launches Claude Code unconfined. No SSH client required.
- **Sessions over SSH:** the `session` helper (or the dashboard's API) is
  also reachable from a plain SSH session — same tmux sockets, same
  per-user namespacing.

### What `99-verify.sh` asserts is green

UFW active and SSH rate-limited · fail2ban active · Docker active · Authelia
container + health endpoint · Caddy container · ttyd-sessions service ·
dashboard page rendered · session-manager API healthy · Claude Code
installed (when selected) · no dashboard bound to `0.0.0.0` · all
observability containers running.

---

## 10-minute disaster recovery

If the server died right now and only this repo existed, the platform layer
is operational again in 10 minutes (provision ~2 min + `.env` ~2 min +
`bootstrap.sh` ~5 min + verify ~30 sec) — the Quickstart above is the whole
procedure.

---

## What's next

See [`docs/ROADMAP.md`](docs/ROADMAP.md). Top remaining items: backup
orchestration (restic to S3-compatible storage) and alertmanager + SMTP
routing.

---

## Troubleshooting

Real things that have bitten operators on the first run. Each entry is
symptom → cause → fix.

### Locked out of `sudo` right after bootstrap

**Symptom:** `sudo` from the admin user rejects every guess; `sudo: a password
is required` with no path forward.

**Cause:** if the admin user was created with `useradd -m` and never had a
password set, the account has none. `01-user-and-ssh.sh` then disables root
SSH (`PermitRootLogin no`), so there is no remote root path to set the admin
password and no admin-side credential to satisfy `sudo`.

**Fix:** open the provider's serial / VNC console (Hetzner: Cloud Console;
Contabo: VNC button on the VPS detail page; equivalent for your provider),
log in as `root` with the provider's initial password, run
`passwd <SERVER_ADMIN_USER>`, save the new password to your secret store,
exit. SSH back in as the admin user — `sudo` now works.

**Prevent:** set the admin user's password **before** running bootstrap, or
configure a `NOPASSWD` sudoers rule (single-admin boxes only).

### `09-claude-code.sh` fails with `EACCES: permission denied, mkdir '/home/<admin>/.local/state'`

**Symptom:** Bootstrap halts mid-orchestrator with `Installation failed` /
`EACCES` from the Claude installer.

**Cause:** An earlier step (notably `07-ttyd.sh` placing files in
`~/.local/bin`) runs as root and creates `/home/<admin>/.local/` owned by
root. Step 09 then runs `claude install` as the admin user, which can't
`mkdir` inside the root-owned dir.

**Fix:** `sudo chown -R <admin>:<admin> /home/<admin>/.local /home/<admin>/.cache /home/<admin>/.claude /home/<admin>/.claude.json`,
then `sudo bash /opt/infra/bootstrap/bootstrap.sh` to resume (idempotent).

### Admin user not in `docker` group after bootstrap

**Symptom:** `docker ps` as the admin user returns
`permission denied while trying to connect to the docker API`.

**Cause:** `01-user-and-ssh.sh` tries `usermod -aG docker <admin> || true`,
but the `docker` group doesn't exist yet — it's created by `04-docker.sh`.
The conditional silently no-ops.

**Fix:** `sudo usermod -aG docker <admin>`, then log out and back in (or
`newgrp docker` in the existing session).

### Grafana shows its own login screen after Authelia (full profile)

**Symptom:** SSO succeeds, but `grafana.<domain>` lands on the Grafana login
form asking for `admin` / password.

**Cause:** Caddy forwards `Remote-User`, `Remote-Groups`, etc. from Authelia,
but Grafana isn't configured to trust them out of the box, so it falls back
to its own auth.

**Fix:** add to the `grafana` service `environment:` block in
`platform/observability/docker-compose.full.yml`:

```yaml
GF_AUTH_PROXY_ENABLED: "true"
GF_AUTH_PROXY_HEADER_NAME: "Remote-User"
GF_AUTH_PROXY_HEADER_PROPERTY: "username"
GF_AUTH_PROXY_AUTO_SIGN_UP: "true"
GF_AUTH_PROXY_HEADERS: "Email:Remote-Email Name:Remote-Name Groups:Remote-Groups"
GF_AUTH_PROXY_WHITELIST: "127.0.0.1,172.16.0.0/12,::1"
GF_AUTH_DISABLE_LOGIN_FORM: "true"
```

Then `sudo docker compose --project-name infra-observability --env-file /opt/infra/.env -f /opt/infra/platform/observability/docker-compose.full.yml up -d --force-recreate grafana`.

### `admin` + the password in `.env` doesn't log into Grafana

**Symptom:** the `GRAFANA_ADMIN_PASSWORD` value from `.env` is rejected at
the Grafana login form, even though it's the value the env was generated
with.

**Cause:** `GF_SECURITY_ADMIN_PASSWORD` is only honored on the **first** init
of the `grafana_data` volume. Subsequent changes to `.env` don't propagate
into Grafana's stored DB.

**Fix:** `sudo docker exec grafana grafana-cli admin reset-admin-password "$(sudo grep '^GRAFANA_ADMIN_PASSWORD=' /opt/infra/.env | cut -d= -f2-)"`.
Now `.env` and the stored password match.

### Bootstrap completes, but a subdomain serves a Caddy default cert (not Let's Encrypt)

**Symptom:** `https://<sub>.<domain>` shows a browser cert warning; `curl -v`
shows the default self-signed Caddy cert.

**Cause:** the ACME HTTP-01 challenge needs the subdomain's A record to
resolve to **this** server. If DNS still points elsewhere (cutover in
progress, record missing, propagation delay), Caddy retries silently and
never gets a real cert.

**Fix:**
```bash
for sub in auth dashboard sessions grafana; do
  printf "%-30s -> " "$sub.<domain>"; dig +short @8.8.8.8 "$sub.<domain>" A
done
```
Every line should show this server's IP. Once DNS is correct,
`sudo systemctl restart caddy` or just wait (Caddy retries with backoff).

**Pre-flight:** run that `dig` check **before** bootstrap. Each failed ACME
attempt counts against Let's Encrypt's per-hostname rate limit (5/hour).

### Cutover collision — re-using a `PRIMARY_DOMAIN` already live on another server

**Symptom:** Bootstrap finishes cleanly, but `https://auth.<domain>` still
serves the OLD server. ACME cert issuance loops silently on the new box.

**Cause:** the DNS A records still point at the old server. Bootstrap
doesn't detect this — it brings Caddy up, Caddy can't prove control of the
hostname, ACME loops in the background.

**Sequence:**
1. Lower TTLs on the affected subdomain records to ~60s (do this ≥ 24h before
   cutover if your registrar caches aggressively).
2. Bootstrap the new box with `PRIMARY_DOMAIN=<domain>` set. Caddy comes up
   listening on 80/443.
3. Flip the DNS A records (`auth`, `dashboard`, `sessions`, `grafana`, plus
   the apex if you use it) to the new server's IP.
4. Within minutes (after propagation) Caddy issues fresh certs.
5. Plan separately what happens to any application state or non-platform
   apps on the old box — they don't migrate themselves.

A migration runbook for stateful platform components (Authelia user DB, TOTP
enrollment) lives in `docs/DISASTER_RECOVERY.md` (operator-local).

---

## Repo layout

- [`bootstrap/`](bootstrap/) — ordered scripts (`00`–`10`, `99-verify`) + `bootstrap.sh` orchestrator.
- [`platform/`](platform/) — platform service definitions (Authelia SSO, Caddy reverse proxy, ttyd web terminal, observability).
- [`security/`](security/) — hardening configs (SSH, firewall, fail2ban, audit rules).
- [`applications/`](applications/) — registry of application tenants.
- [`docs/`](docs/) — [CHANGELOG](docs/CHANGELOG.md) (shipped) and [ROADMAP](docs/ROADMAP.md) (planned). The full operational handbook (architecture, runbooks, disaster recovery, secrets policy) is operator-local — kept per-fork, not committed here.
- [`tests/`](tests/) — integration tests for the platform itself.

## What does not live here

Application code or application-specific infrastructure. Each application
lives in its own repo and integrates with the platform via documented
contracts (Caddyfile fragments, container labels, a backup-volume registry).

## For Claude agents working in this repo

Read [`.claude/skills/overall-infra-architect/SKILL.md`](.claude/skills/overall-infra-architect/SKILL.md)
first — the Platform Infrastructure Architect persona, operating principles,
and the boundary between platform and application work.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md). Free to use, modify, fork,
and share for any **noncommercial** purpose — personal projects, study, and
research, plus use by nonprofits, schools, and government, are all explicitly
covered. **Commercial use is not granted** by this license: you may not
monetize the software or use it in a revenue-generating operation. Contact the
maintainer for commercial terms.
