#!/usr/bin/env python3
"""break — exit the bubblewrap sandbox after Authelia TOTP validation.

Invoked by /home/sandbox/bin/break (the break-shim bound into the sandbox)
via ``tmux respawn-pane -k -- /usr/local/sbin/break``. The tmux server
runs OUTSIDE the sandbox as the admin user, so by the time this script
starts the pane is already unconfined and running as the admin user.

This script prompts for the operator's 6-digit Authelia TOTP code,
validates it against the secret in Authelia's SQLite store, and on
success ``exec``s a fresh login bash in the same pane.

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

# Optional import — deferred so the module is importable for unit tests on
# hosts that don't have python3-cryptography. The actual decrypt path checks
# AESGCM is None and fails with a clear message at use time.
try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:  # pragma: no cover
    AESGCM = None  # type: ignore[assignment]

AUTHELIA_DIR = Path("/opt/infra/platform/authelia")
DB_PATH = AUTHELIA_DIR / "data" / "db.sqlite3"
KEY_PATH = AUTHELIA_DIR / "secrets" / "storage"
ENV_PATH = Path("/opt/infra/.env")
# Match the current and ±1 windows (30s each) to tolerate small clock skew
# between the server and the operator's authenticator device.
TOTP_WINDOW_SECONDS = 30
TOTP_SKEW_WINDOWS = (-1, 0, 1)


def die(msg: str) -> None:
    print(f"break: {msg}", file=sys.stderr)
    sys.exit(1)


def authelia_decrypt(blob: bytes) -> bytes:
    """Decrypt one AES-256-GCM blob using the Authelia storage key.

    Authelia's scheme (see ``internal/utils/crypto.go`` in the Authelia
    source): the per-record secret string is encrypted with AES-256-GCM
    using SHA-256(storage_key) as the key. The wire format is
    ``nonce (12 bytes) || ciphertext || gcm_tag (16 bytes)``.
    """
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
    """Return the base32 TOTP secret string for an Authelia user.

    The DB column stores the base32 secret string encrypted (not the raw
    bytes). After decryption the result is the same ASCII base32 string
    that appears in the otpauth:// URI Authelia prints on enrolment."""
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
    """RFC 6238 TOTP — HMAC-SHA1, default 30s step, 6 digits.

    Matches Authelia's default TOTP parameters. If a fork ever changes the
    period/digits/algo from Authelia's defaults this needs updating too,
    but those settings are not in our normal customisation surface."""
    # Clamp non-negative; the only path that produces a negative counter is
    # the ±1 skew check fired near the unix epoch (i.e., test vectors). Real
    # operator use is always many years past epoch, so this is a no-op there.
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
    """Accept the code if it matches the current or an adjacent window."""
    if not supplied.isdigit() or len(supplied) != 6:
        return False
    now = int(time.time())
    expected = {compute_totp(secret_b32, now + w * TOTP_WINDOW_SECONDS)
                for w in TOTP_SKEW_WINDOWS}
    # Constant-time string equality on each candidate avoids early-exit
    # timing signal on the prefix bytes of the code.
    return any(hmac.compare_digest(supplied, exp) for exp in expected)


def exec_unconfined_bash() -> None:
    """Replace this process with a fresh login bash in the same pane.

    We're already outside the sandbox by the time this runs — the
    break-shim used ``tmux respawn-pane`` to escape, then tmux spawned
    this script as a host-side child of the tmux server. So we just
    ``exec`` bash in place; no tmux gymnastics required."""
    os.execvp("/bin/bash", ["/bin/bash", "-l"])


def resolve_username() -> str:
    """Pick the Authelia username to validate against. Order: explicit arg,
    TTYD_USER (set by ttyd from the verified Remote-User header and
    forwarded through the sandbox), then AUTHELIA_USER from .env, then a
    last-resort 'admin'."""
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

    print(f"✓ verified — breaking {username} out of the sandbox")
    exec_unconfined_bash()


if __name__ == "__main__":
    main()
