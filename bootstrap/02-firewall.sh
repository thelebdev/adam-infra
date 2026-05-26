#!/usr/bin/env bash
# 03 - firewall: UFW default-deny inbound, public SSH allowed (rate-limited),
# fail2ban guards brute-force. Public HTTP/HTTPS opt-in via ALLOW_PUBLIC_WEB.
#
# Note: this baseline exposes SSH to the public internet. Security relies on
# key-only auth (set in 01-user-and-ssh.sh) + fail2ban. A stronger access
# mechanism (mesh VPN, zero-trust proxy, bastion) is on the roadmap; see
# docs/ROADMAP.md.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"
require_root
load_env

ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing

# Public SSH, rate-limited by UFW (drops connections from an IP exceeding
# 6 attempts in 30s). fail2ban adds longer-lived bans on top.
ufw limit 22/tcp comment 'ssh (rate-limited)'

# Public HTTP/HTTPS: required for Caddy reverse proxy in front of dashboards
# (02-caddy.sh) and for any application that genuinely serves the internet.
if [ "${ALLOW_PUBLIC_WEB:-true}" = "true" ]; then
  ufw allow 80/tcp comment 'http'
  ufw allow 443/tcp comment 'https'
  log INFO "public web ports opened (ALLOW_PUBLIC_WEB=true)"
fi

ufw --force enable
ensure_service fail2ban
log INFO "ufw active: default-deny inbound, ssh rate-limited, fail2ban guarding"
