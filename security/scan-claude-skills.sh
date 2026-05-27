#!/usr/bin/env bash
# Secret + PII scanner for platform/claude/.
#
# This directory is published as part of the repo (PolyForm-NC; world-readable
# on GitHub). The scanner refuses to let personal identifiers or credentials
# slip in via a careless skill update. Run it locally before staging, and run
# it in CI on every push.
#
# Exit codes:
#   0 — clean
#   1 — one or more findings (printed to stderr)
#
# What it checks under platform/claude/:
#   - API keys (Anthropic, OpenAI, Stripe, AWS, GitHub, Slack)
#   - Private keys (RSA / EC / OpenSSH / DSA)
#   - Email addresses (excluding @example.com, @your-domain, @localhost)
#   - Public-looking IPv4 addresses (excluding RFC1918, loopback, docs ranges)
#   - Operator-specific identifiers configurable via .scan-deny.txt
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
TARGET="${REPO_ROOT}/platform/claude"
DENY_FILE="${HERE}/scan-claude-skills.deny"

[ -d "${TARGET}" ] || { echo "scanner: target ${TARGET} does not exist" >&2; exit 1; }

rc=0
report() {
  rc=1
  printf '\n[FINDING] %s\n' "$1" >&2
  shift
  printf '%s\n' "$@" >&2
}

# 1. API keys / tokens.
out="$(grep -rEn --binary-files=without-match \
  '(sk-[a-zA-Z0-9_-]{20,}|sk_live_[a-zA-Z0-9]{20,}|sk_test_[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{20,}|gho_[a-zA-Z0-9]{20,}|xox[bp]-[a-zA-Z0-9-]{10,})' \
  "${TARGET}" 2>/dev/null)" || true
[ -n "${out}" ] && report "API key / token pattern matched" "${out}"

# 2. Private keys. Require the `-----` boundary so doc-style mentions of the
# string "BEGIN PRIVATE KEY" (e.g., a secret-scan skill that names patterns
# to look for) don't false-positive.
out="$(grep -rEn --binary-files=without-match \
  -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  "${TARGET}" 2>/dev/null)" || true
[ -n "${out}" ] && report "private key block matched" "${out}"

# 3. Email addresses (excluding obvious placeholders).
out="$(grep -rEn --binary-files=without-match \
  '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
  "${TARGET}" 2>/dev/null \
  | grep -viE '@(example\.com|example\.org|your-domain|localhost|noreply\.[a-z.]+)$' \
  | grep -viE '@(example\.com|example\.org|your-domain|localhost)' )" || true
[ -n "${out}" ] && report "email address matched (non-placeholder)" "${out}"

# 4. Public-looking IPv4 addresses.
ip_findings=""
while IFS= read -r line; do
  file="${line%%:*}"; rest="${line#*:}"
  lineno="${rest%%:*}"; content="${rest#*:}"
  for ip in $(printf '%s' "${content}" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' || true); do
    case "${ip}" in
      10.*|127.*|0.*|255.*) continue ;;
      192.168.*) continue ;;
      192.0.2.*|198.51.100.*|203.0.113.*) continue ;;
      169.254.*) continue ;;
    esac
    case "${ip}" in
      172.16.*|172.17.*|172.18.*|172.19.*|172.2[0-9].*|172.3[01].*) continue ;;
    esac
    ip_findings+="${file}:${lineno}: ${ip} (in: ${content})"$'\n'
  done
done < <(grep -rEn --binary-files=without-match '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "${TARGET}" 2>/dev/null || true)
[ -n "${ip_findings}" ] && report "public-looking IPv4 address(es)" "${ip_findings}"

# 5. Operator-specific deny list (one regex per line, # for comments).
# This file is gitignored intentionally so each operator can list their own
# identifiers without leaking the list itself into the public repo.
if [ -f "${DENY_FILE}" ]; then
  while IFS= read -r pattern; do
    case "${pattern}" in ''|\#*) continue ;; esac
    out="$(grep -rEni --binary-files=without-match "${pattern}" "${TARGET}" 2>/dev/null)" || true
    [ -n "${out}" ] && report "operator deny pattern matched: ${pattern}" "${out}"
  done < "${DENY_FILE}"
fi

if [ "${rc}" -eq 0 ]; then
  echo "scan-claude-skills: clean (target=${TARGET#${REPO_ROOT}/})"
else
  echo "scan-claude-skills: FINDINGS present (target=${TARGET#${REPO_ROOT}/})" >&2
fi
exit "${rc}"
