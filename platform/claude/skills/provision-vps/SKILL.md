---
name: provision-vps
description: Initial hardening of a new Ubuntu VPS — SSH keys (one per server, documented), firewall, fail2ban, unattended upgrades, basic monitoring. Use when setting up a new server.
---

# Provision a new Ubuntu VPS

## Self-update on invocation

1. WebSearch for "Ubuntu server hardening best practices 2026".
2. WebSearch for current SSH key algorithm recommendations.
3. Propose updates. Apply with my approval.

## Steps

### 1. SSH key generation and documentation
1. Generate a NEW SSH key specifically for this server. Never reuse keys across servers.
2. Algorithm: ed25519 (current best practice as of last review; verify).
3. Naming: `~/.ssh/<server-purpose>_<server-name>_ed25519` (e.g., `~/.ssh/operator_hetzner_lebanon_ed25519`).
4. Add to `~/.ssh/config`:
   ```
   Host <short-alias>
     HostName <ip-or-hostname>
     User <user>
     IdentityFile ~/.ssh/<key-name>
     IdentitiesOnly yes
   ```
5. Document in the `servers-inventory` GitHub repo (see `vps-document` skill):
   - Server name, provider, region, specs.
   - SSH key name and which local machine holds it.
   - Public IP, hostname.

### 2. Initial server hardening
1. Connect as root via password (provider's initial setup). After this step, password auth is disabled.
2. Update everything: `apt update && apt upgrade -y`.
3. Set hostname meaningfully.
4. Set timezone.
5. Create a non-root sudo user. Copy the SSH public key to its `authorized_keys`.
6. SSH config (`/etc/ssh/sshd_config.d/99-hardening.conf`):
   - `PermitRootLogin no`
   - `PasswordAuthentication no`
   - `PubkeyAuthentication yes`
   - `KbdInteractiveAuthentication no`
   - `Port 22` (or non-default — ask)
   - Restart sshd. Verify you can still log in from a separate terminal before closing the root session.
7. Firewall (ufw):
   - Default deny incoming, allow outgoing.
   - Allow 22 (or chosen SSH port).
   - Allow 80, 443.
   - Enable.
8. fail2ban: install and enable, default jail for sshd.
9. Unattended security upgrades: install and enable. Configure email alerts (if mail relay configured) or just log.
10. Install: `htop`, `ncdu`, `tmux`, `curl`, `wget`, `jq`, `vim`, `git`.

### 3. Docker
1. Install Docker via official repo (not Ubuntu's outdated package).
2. Add non-root user to `docker` group.
3. Enable docker service.
4. Verify with `docker run hello-world`.

### 4. Caddy (if web-facing)
1. Run `caddy-reverse-proxy` skill.

### 5. Documentation
1. Run `vps-document` skill to write this server into `servers-inventory`.

## Checkpoints

- STOP after SSH key setup. Confirm I have the key locally and can SSH in before disabling password auth.
- STOP before opening ports other than 22/80/443.
- ASK before disabling root login if the provider's emergency console requires it.

## Related skills

- `vps-document`
- `caddy-reverse-proxy`
- `vps-backup-strategy`
- `monitor-vps`

<!-- last_reviewed: 2026-05-12 -->
