#!/usr/bin/env python3
"""Unit tests for platform/ttyd/break.py — TOTP-gated sandbox escape.

Tests the pure-function bits (compute_totp, validate_totp, resolve_username)
without touching the live Authelia DB or attempting to escape any actual
sandbox. The encryption side is covered by an integration test on the VPS
(`sudo break` end-to-end), not here.
"""
from __future__ import annotations

import base64
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# break.py lives outside the package tree and has a name (`break`) that's a
# Python keyword, so import via importlib.
HERE = Path(__file__).resolve().parent
BREAK_PATH = HERE.parent.parent / "platform" / "ttyd" / "break.py"
spec = importlib.util.spec_from_file_location("break_module", BREAK_PATH)
break_mod = importlib.util.module_from_spec(spec)  # type: ignore[arg-type]
sys.modules["break_module"] = break_mod
spec.loader.exec_module(break_mod)  # type: ignore[union-attr]


# Known RFC 6238 / RFC 4226 test vector adapted to base32:
# The classic ASCII secret is b"12345678901234567890" → base32 "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ".
RFC_SECRET = base64.b32encode(b"12345678901234567890").decode()
# Pre-computed TOTP codes for known (secret, t) pairs.
# At t=59 (counter=1), the canonical TOTP for the RFC secret with
# SHA-1/30s/6-digit is "287082" (RFC 6238 appendix B).
RFC_T59_CODE = "287082"
RFC_T1111111109_CODE = "081804"


class ComputeTotpTests(unittest.TestCase):
    def test_rfc_vector_t59(self) -> None:
        self.assertEqual(break_mod.compute_totp(RFC_SECRET, 59), RFC_T59_CODE)

    def test_rfc_vector_t1111111109(self) -> None:
        self.assertEqual(
            break_mod.compute_totp(RFC_SECRET, 1111111109), RFC_T1111111109_CODE)

    def test_six_digit_zero_padding(self) -> None:
        for t in range(0, 600, 30):
            code = break_mod.compute_totp(RFC_SECRET, t)
            self.assertEqual(len(code), 6)
            self.assertTrue(code.isdigit())


class ValidateTotpTests(unittest.TestCase):
    def test_accepts_current_window(self) -> None:
        with mock.patch.object(break_mod.time, "time", return_value=59.0):
            self.assertTrue(break_mod.validate_totp(RFC_SECRET, RFC_T59_CODE))

    def test_accepts_one_window_late(self) -> None:
        # If the device clock is 30s ahead, the operator's code matches the
        # NEXT window — should still be accepted.
        with mock.patch.object(break_mod.time, "time", return_value=29.0):
            self.assertTrue(break_mod.validate_totp(RFC_SECRET, RFC_T59_CODE))

    def test_accepts_one_window_early(self) -> None:
        # And the symmetric case: clock 30s behind.
        with mock.patch.object(break_mod.time, "time", return_value=89.0):
            self.assertTrue(break_mod.validate_totp(RFC_SECRET, RFC_T59_CODE))

    def test_rejects_two_windows_off(self) -> None:
        # Two windows is too far — the spec accepts ±1 only.
        with mock.patch.object(break_mod.time, "time", return_value=149.0):
            self.assertFalse(break_mod.validate_totp(RFC_SECRET, RFC_T59_CODE))

    def test_rejects_wrong_code(self) -> None:
        with mock.patch.object(break_mod.time, "time", return_value=59.0):
            self.assertFalse(break_mod.validate_totp(RFC_SECRET, "000000"))

    def test_rejects_non_digit_input(self) -> None:
        with mock.patch.object(break_mod.time, "time", return_value=59.0):
            self.assertFalse(break_mod.validate_totp(RFC_SECRET, "12345a"))

    def test_rejects_wrong_length(self) -> None:
        with mock.patch.object(break_mod.time, "time", return_value=59.0):
            self.assertFalse(break_mod.validate_totp(RFC_SECRET, "1234"))
            self.assertFalse(break_mod.validate_totp(RFC_SECRET, "1234567"))


class ResolveUsernameTests(unittest.TestCase):
    """Priority order: argv > $TTYD_USER > AUTHELIA_USER in .env > 'admin'."""

    def setUp(self) -> None:
        self._orig_argv = sys.argv[:]
        self._orig_env_path = break_mod.ENV_PATH
        self._tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".env", delete=False)
        self._tmp.close()
        break_mod.ENV_PATH = Path(self._tmp.name)

    def tearDown(self) -> None:
        sys.argv[:] = self._orig_argv
        break_mod.ENV_PATH = self._orig_env_path
        os.unlink(self._tmp.name)

    @mock.patch.dict(os.environ, {}, clear=True)
    def test_falls_back_to_admin_when_nothing_set(self) -> None:
        sys.argv = ["break"]
        # Empty .env file.
        self.assertEqual(break_mod.resolve_username(), "admin")

    @mock.patch.dict(os.environ, {}, clear=True)
    def test_reads_authelia_user_from_env_file(self) -> None:
        sys.argv = ["break"]
        Path(self._tmp.name).write_text(
            "PRIMARY_DOMAIN=example.com\nAUTHELIA_USER=opsbot\n")
        self.assertEqual(break_mod.resolve_username(), "opsbot")

    @mock.patch.dict(os.environ, {"TTYD_USER": "alice"}, clear=True)
    def test_ttyd_user_beats_env_file(self) -> None:
        sys.argv = ["break"]
        Path(self._tmp.name).write_text("AUTHELIA_USER=opsbot\n")
        self.assertEqual(break_mod.resolve_username(), "alice")

    @mock.patch.dict(os.environ, {"TTYD_USER": "alice"}, clear=True)
    def test_argv_beats_everything(self) -> None:
        sys.argv = ["break", "explicit"]
        Path(self._tmp.name).write_text("AUTHELIA_USER=opsbot\n")
        self.assertEqual(break_mod.resolve_username(), "explicit")


if __name__ == "__main__":
    unittest.main(verbosity=2)
