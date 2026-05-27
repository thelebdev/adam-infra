#!/usr/bin/env python3
"""claude-break-out — TOTP-gated launch of Claude Code with break-out.

Invoked by /home/sandbox/bin/claude (the claude-shim bound into the
sandbox) via ``tmux respawn-pane -k -- /usr/local/sbin/claude-break-out``.
The tmux server runs OUTSIDE the sandbox as the admin user, so by the
time this script starts the pane is already unconfined.

This script prompts for the operator's 6-digit Authelia TOTP code,
validates it against the secret in Authelia's SQLite store, and on
success ``exec``s a login bash that immediately ``exec``s Claude Code
(so quitting claude exits the pane, no bash prompt layered underneath).
``bash -l`` is used so ``.profile`` runs first and puts ``~/.local/bin``
on PATH (where ``claude`` lives).

Why no sudo here:
  bwrap on Ubuntu 24.04 ships non-setuid and creates an unprivileged user
  namespace; that namespace mandates PR_SET_NO_NEW_PRIVS=1 (blocks setuid)
  and maps host UID 0 to nobody/65534 inside the sandbox. Both make sudo
  impossible inside the jail. The shim sidesteps this by asking tmux
  (host-side, unconfined) to respawn the pane with this helper directly,
  so the privilege barrier we authenticate against is the Authelia TOTP
  alone — and that requires the admin user to be able to read the SQLite
  DB + storage key (see bootstrap/05-authelia.sh — chmod 640 + group
  membership grants exactly that).

Requires (installed by bootstrap/07-ttyd.sh + 05-authelia.sh):
  - python3-cryptography  (AES-256-GCM decryption of Authelia's secret blob)
  - /opt/infra/platform/authelia/data/db.sqlite3  (mode 640, root:<admin>)
  - /opt/infra/platform/authelia/secrets/storage  (mode 640, root:<admin>;
     the storage encryption key)

NOTE: the TOTP validation logic below duplicates platform/ttyd/break.py.
A follow-up PR should extract them into a shared module
(platform/ttyd/totp_gate.py) — kept duplicated here for now to keep this
change focused.
"""
from __future__ import annotations

import base64
import getpass
import hashlib
import hmac
import os
import sqlite3
import struct
import subprocess
import sys
import time
from pathlib import Path

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:  # pragma: no cover
    AESGCM = None  # type: ignore[assignment]

AUTHELIA_DIR = Path("/opt/infra/platform/authelia")
DB_PATH = AUTHELIA_DIR / "data" / "db.sqlite3"
KEY_PATH = AUTHELIA_DIR / "secrets" / "storage"
ENV_PATH = Path("/opt/infra/.env")
TOTP_WINDOW_SECONDS = 30
TOTP_SKEW_WINDOWS = (-1, 0, 1)


def die(msg: str) -> None:
    print(f"claude-break-out: {msg}", file=sys.stderr)
    sys.exit(1)


def authelia_decrypt(blob: bytes) -> bytes:
    if AESGCM is None:
        die("python3-cryptography is not installed "
            "(run: sudo apt install python3-cryptography)")
    try:
        key_str = KEY_PATH.read_text().strip()
    except OSError as exc:
        die(f"cannot read storage key at {KEY_PATH}: {exc}")
    key = hashlib.sha256(key_str.encode()).digest()
    if len(blob) < 12 + 16:
        die("encrypted secret is too short to be valid AES-GCM ciphertext")
    nonce, ct = blob[:12], blob[12:]
    try:
        return AESGCM(key).decrypt(nonce, ct, None)
    except Exception as exc:  # noqa: BLE001
        die(f"could not decrypt TOTP secret: {exc} "
            "(storage key may have changed since enrolment)")


def get_totp_secret(username: str) -> str:
    if not DB_PATH.exists():
        die(f"Authelia DB not found at {DB_PATH}")
    conn = sqlite3.connect(str(DB_PATH))
    try:
        row = conn.execute(
            "SELECT secret FROM totp_configurations WHERE username = ?",
            (username,)).fetchone()
    except sqlite3.OperationalError as exc:
        die(f"Authelia DB query failed ({exc}); is the schema as expected?")
    finally:
        conn.close()
    if not row or row[0] is None:
        die(f"no TOTP enrolled for Authelia user '{username}'")
    return authelia_decrypt(row[0]).decode().strip()


def compute_totp(secret_b32: str, t: int,
                 step: int = TOTP_WINDOW_SECONDS, digits: int = 6) -> str:
    counter = max(t // step, 0)
    counter_bytes = struct.pack(">Q", counter)
    secret = base64.b32decode(secret_b32.upper())
    h = hmac.new(secret, counter_bytes, hashlib.sha1).digest()
    offset = h[-1] & 0x0f
    code = ((h[offset] & 0x7f) << 24 |
            h[offset + 1] << 16 |
            h[offset + 2] << 8 |
            h[offset + 3]) % (10 ** digits)
    return str(code).zfill(digits)


def validate_totp(secret_b32: str, supplied: str) -> bool:
    if not supplied.isdigit() or len(supplied) != 6:
        return False
    now = int(time.time())
    expected = {compute_totp(secret_b32, now + w * TOTP_WINDOW_SECONDS)
                for w in TOTP_SKEW_WINDOWS}
    return any(hmac.compare_digest(supplied, exp) for exp in expected)


def exec_claude_via_login_bash() -> None:
    """Replace this process with a login bash that immediately execs claude.

    We're already outside the sandbox by the time this runs — the
    claude-shim used ``tmux respawn-pane`` to escape, then tmux spawned
    this script as a host-side child of the tmux server. ``bash -l``
    sources ``.profile`` so ``~/.local/bin`` lands on PATH where
    ``claude`` lives; ``exec claude`` means quitting claude exits the
    pane rather than leaving a bash prompt underneath."""
    os.execvp("/bin/bash", ["/bin/bash", "-l", "-c", "exec claude"])


def resolve_username() -> str:
    if len(sys.argv) >= 2 and sys.argv[1]:
        return sys.argv[1]
    if os.environ.get("TTYD_USER"):
        return os.environ["TTYD_USER"]
    if ENV_PATH.exists():
        for line in ENV_PATH.read_text().splitlines():
            if line.startswith("AUTHELIA_USER="):
                value = line.split("=", 1)[1].strip()
                if value:
                    return value
    return "admin"


def main() -> None:
    username = resolve_username()
    secret = get_totp_secret(username)
    code = getpass.getpass(f"Authelia TOTP for {username}: ").strip()
    if not validate_totp(secret, code):
        die("invalid TOTP code")

    print(f"✓ verified — launching Claude for {username} outside the sandbox")
    exec_claude_via_login_bash()


if __name__ == "__main__":
    main()
