---
name: caddy-reverse-proxy
description: Standard Caddy reverse proxy setup with automatic TLS, HSTS, security headers, and access logs. Use when exposing services on a VPS to the internet.
---

# Caddy reverse proxy

## Self-update on invocation

1. WebSearch for "Caddy v2 best practices 2026".
2. Verify current recommended Caddy modules and security header defaults.
3. Propose updates. Apply with my approval.

## Steps

1. Install Caddy from the official repo (not Ubuntu's outdated package).
2. Config lives at `/etc/caddy/Caddyfile`.
3. Default template:
   ```caddyfile
   {
     email <my-admin-email>
     # Use staging for testing if needed: acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
   }

   <domain> {
     reverse_proxy localhost:<port>
     encode zstd gzip

     header {
       Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
       X-Content-Type-Options "nosniff"
       X-Frame-Options "DENY"
       Referrer-Policy "strict-origin-when-cross-origin"
       Permissions-Policy "geolocation=(), microphone=(), camera=()"
       -Server
     }

     log {
       output file /var/log/caddy/<domain>.log {
         roll_size 100MB
         roll_keep 5
       }
       format json
     }
   }
   ```
4. For each new service:
   - Add a new site block to the Caddyfile.
   - Verify DNS A record points to the server.
   - Reload: `caddy reload --config /etc/caddy/Caddyfile`.
   - Verify TLS cert was issued: `curl -I https://<domain>`.
5. Auth (when needed):
   - Basic auth for internal admin panels: `basicauth { user <bcrypt-hash> }`.
   - Better: forward auth to an OIDC proxy if user count grows.
6. Rate limits (caddy-rate-limit plugin or external).
7. Document each site in `vps-document`.

## Checkpoints

- ASK before exposing any service without auth.
- ASK before adding a custom on-demand TLS config (security implications).
- NEVER hardcode credentials in the Caddyfile.

## Related skills

- `vps-document`
- `provision-vps`

<!-- last_reviewed: 2026-05-12 -->
