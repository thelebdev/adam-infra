#!/usr/bin/env python3
"""Unit tests for platform/session-manager/server.py.

Pure-function tests — no VPS, no Docker, no network, no real tmux (the tmux
calls are faked). Run via tests/infra/run-tests.sh or:

    python3 -m unittest tests.infra.test_session_manager
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from email.message import Message
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "platform" / "session-manager"))
import server  # noqa: E402


def fake_run(returncode: int = 0, stdout: str = "", stderr: str = ""):
    """A drop-in for server._run that never shells out."""
    def runner(cmd: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(cmd, returncode, stdout, stderr)
    return runner


class WorkspaceTestCase(unittest.TestCase):
    """Base case that points server.WORKSPACE_ROOT at a throwaway tree."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._orig_ws = server.WORKSPACE_ROOT
        server.WORKSPACE_ROOT = self.root

    def tearDown(self) -> None:
        server.WORKSPACE_ROOT = self._orig_ws
        self._tmp.cleanup()


class ConfineDirTests(WorkspaceTestCase):
    def setUp(self) -> None:
        super().setUp()
        (self.root / "proj-a").mkdir()
        (self.root / "proj-b" / "sub").mkdir(parents=True)

    def test_root_itself(self) -> None:
        self.assertEqual(server.confine_dir(""),
                         Path(os.path.realpath(self.root)))

    def test_existing_subdir(self) -> None:
        self.assertEqual(server.confine_dir("proj-a"),
                         Path(os.path.realpath(self.root / "proj-a")))

    def test_nested_subdir(self) -> None:
        self.assertEqual(server.confine_dir("proj-b/sub"),
                         Path(os.path.realpath(self.root / "proj-b" / "sub")))

    def test_new_directory_allowed(self) -> None:
        # A not-yet-created project directory still resolves inside the root.
        self.assertEqual(server.confine_dir("brand-new"),
                         Path(os.path.realpath(self.root / "brand-new")))

    def test_dotdot_escape_rejected(self) -> None:
        with self.assertRaises(server.ApiError):
            server.confine_dir("../escape")

    def test_absolute_path_rejected(self) -> None:
        with self.assertRaises(server.ApiError):
            server.confine_dir("/etc")

    def test_nested_dotdot_escape_rejected(self) -> None:
        with self.assertRaises(server.ApiError):
            server.confine_dir("proj-a/../../escape")

    def test_symlink_escape_rejected(self) -> None:
        (self.root / "evil").symlink_to("/etc")
        with self.assertRaises(server.ApiError):
            server.confine_dir("evil")


class WorkspaceDirsTests(WorkspaceTestCase):
    def test_lists_two_levels_and_skips_hidden(self) -> None:
        (self.root / "alpha").mkdir()
        (self.root / "beta" / "inner").mkdir(parents=True)
        (self.root / ".hidden").mkdir()
        dirs = server.workspace_dirs()
        self.assertIn("alpha", dirs)
        self.assertIn("beta", dirs)
        self.assertIn("beta/inner", dirs)
        self.assertNotIn(".hidden", dirs)


class NameRegexTests(unittest.TestCase):
    def test_valid_names(self) -> None:
        for name in ("api", "x", "a-b_c", "1proj", "A" * 32):
            self.assertRegex(name, server.NAME_RE)

    def test_invalid_names(self) -> None:
        for name in ("", "-bad", "a.b", "a b", "a/b", "x" * 33, "../x"):
            self.assertNotRegex(name, server.NAME_RE)


class TmuxTests(WorkspaceTestCase):
    def setUp(self) -> None:
        super().setUp()
        self._orig_run = server._run
        self._orig_sockets = server.SOCKET_DIR
        # Steer marker writes to the throwaway workspace, not the dev home.
        server.SOCKET_DIR = self.root / ".sockets"
        server.SOCKET_DIR.mkdir(parents=True, exist_ok=True)
        self._orig_claude = server.claude_installed
        server.claude_installed = lambda: True

    def tearDown(self) -> None:
        server._run = self._orig_run
        server.SOCKET_DIR = self._orig_sockets
        server.claude_installed = self._orig_claude
        super().tearDown()

    def test_socket_path_is_per_user(self) -> None:
        alice = " ".join(server._tmux_base("alice"))
        bob = " ".join(server._tmux_base("bob"))
        self.assertIn("alice.sock", alice)
        self.assertIn("bob.sock", bob)
        self.assertNotEqual(alice, bob)

    def test_list_empty_when_no_server(self) -> None:
        server._run = fake_run(returncode=1, stderr="no server running")
        self.assertEqual(server.list_sessions("alice"), [])

    def test_list_parses_a_session_with_cmd(self) -> None:
        # Markers from older versions (when "claude" was a valid session
        # command) should fall back to CMD_DEFAULT now that the allowlist
        # only contains "shell" — list_sessions must surface a value the
        # frontend can render.
        server.write_marker("alice", "api", "claude")
        line = server.SEP.join(["api", "2", "1", "100", "200", "/ws/api"])
        server._run = fake_run(stdout=line + "\n")
        out = server.list_sessions("alice")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["name"], "api")
        self.assertEqual(out[0]["windows"], 2)
        self.assertTrue(out[0]["attached"])
        self.assertEqual(out[0]["dir"], "/ws/api")
        self.assertEqual(out[0]["cmd"], server.CMD_DEFAULT)

    def test_list_defaults_cmd_when_marker_missing(self) -> None:
        line = server.SEP.join(["orphan", "1", "0", "100", "200", "/ws/x"])
        server._run = fake_run(stdout=line + "\n")
        out = server.list_sessions("alice")
        self.assertEqual(out[0]["cmd"], server.CMD_DEFAULT)

    def test_create_rejects_bad_name(self) -> None:
        server._run = fake_run()
        with self.assertRaises(server.ApiError) as ctx:
            server.create_session("alice", "bad name", "")
        self.assertEqual(ctx.exception.status, 400)

    def test_create_rejects_bad_cmd(self) -> None:
        server._run = fake_run()
        with self.assertRaises(server.ApiError) as ctx:
            server.create_session("alice", "api", "", cmd="rm")
        self.assertEqual(ctx.exception.status, 400)

    def test_create_rejects_claude_now_that_its_removed(self) -> None:
        # "claude" used to be a valid session command (with a separate
        # is-claude-installed gate). It's been removed from CMD_ALLOWLIST
        # entirely — sessions are always sandboxed shells; claude launches
        # from inside via the TOTP-gated shim. cmd="claude" must be
        # rejected as an unknown command, regardless of whether the
        # binary is installed on the host.
        server.claude_installed = lambda: True
        server._run = fake_run()
        with self.assertRaises(server.ApiError) as ctx:
            server.create_session("alice", "api", "", cmd="claude")
        self.assertEqual(ctx.exception.status, 400)

    def test_create_writes_marker(self) -> None:
        server._run = fake_run()
        server.create_session("alice", "api", "", cmd="shell")
        self.assertEqual(server.read_marker("alice", "api"), "shell")

    def test_create_reports_duplicate(self) -> None:
        server._run = fake_run(returncode=1, stderr="duplicate session: api")
        with self.assertRaises(server.ApiError) as ctx:
            server.create_session("alice", "api", "")
        self.assertEqual(ctx.exception.status, 409)

    def test_create_rejects_escaping_directory(self) -> None:
        server._run = fake_run()
        with self.assertRaises(server.ApiError) as ctx:
            server.create_session("alice", "api", "../../etc")
        self.assertEqual(ctx.exception.status, 400)

    def test_kill_reports_unknown_session(self) -> None:
        server._run = fake_run(returncode=1, stderr="can't find session: x")
        with self.assertRaises(server.ApiError) as ctx:
            server.kill_session("alice", "x")
        self.assertEqual(ctx.exception.status, 404)

    def test_kill_clears_marker(self) -> None:
        server.write_marker("alice", "api", "claude")
        server._run = fake_run(returncode=0)
        server.kill_session("alice", "api")
        self.assertFalse(server._marker_path("alice", "api").exists())


class VersionTests(unittest.TestCase):
    """`read_version()` aggregates per-component `.version.json` stamps and
    flags drift against the current git HEAD. The test fakes both the git
    call and the on-disk component files so the assertions don't depend on
    the test runner's git state."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._orig_infra_root = server.INFRA_ROOT
        server.INFRA_ROOT = self.root
        self._orig_git_head = server._git_head_short
        server._git_head_short = lambda: "abcd123456"
        (self.root / "platform").mkdir()

    def tearDown(self) -> None:
        server.INFRA_ROOT = self._orig_infra_root
        server._git_head_short = self._orig_git_head
        self._tmp.cleanup()

    def _stamp(self, comp: str, sha: str, ts: str = "2026-05-26T10:00:00Z") -> None:
        comp_dir = self.root / "platform" / comp
        comp_dir.mkdir(parents=True, exist_ok=True)
        (comp_dir / ".version.json").write_text(
            json.dumps({"git_sha": sha, "rendered_at": ts, "by": "test"}))

    def test_all_in_sync(self) -> None:
        for comp in server.VERSION_COMPONENTS:
            self._stamp(comp, "abcd123456")
        v = server.read_version()
        self.assertEqual(v["git_sha"], "abcd123456")
        self.assertFalse(v["drift"])
        self.assertEqual(v["drifted_components"], [])

    def test_stale_component_is_drift(self) -> None:
        for comp in server.VERSION_COMPONENTS:
            self._stamp(comp, "abcd123456")
        self._stamp("caddy", "feedbeef00")  # stale
        v = server.read_version()
        self.assertTrue(v["drift"])
        self.assertEqual(v["drifted_components"], ["caddy"])

    def test_missing_component_is_drift(self) -> None:
        for comp in server.VERSION_COMPONENTS:
            if comp != "dashboard":
                self._stamp(comp, "abcd123456")
        v = server.read_version()
        self.assertIn("dashboard", v["drifted_components"])
        self.assertIsNone(v["components"]["dashboard"])

    def test_dirty_suffix_ignored(self) -> None:
        # `-dirty` suffix is added by write_version_json when the tree has
        # uncommitted edits at render time. Stripping it on compare avoids a
        # false drift for an operator's local tweak.
        for comp in server.VERSION_COMPONENTS:
            self._stamp(comp, "abcd123456-dirty")
        v = server.read_version()
        self.assertFalse(v["drift"])


class SepTests(unittest.TestCase):
    """tmux 3.x escapes non-printable bytes in `-F` output (0x1f becomes
    the literal four-character sequence ``\\037``), so a control-byte SEP
    silently breaks the parse and `list_sessions` returns []. Keep SEP
    printable, single-character, and not allowed in session names."""

    def test_sep_is_printable_single_char(self) -> None:
        self.assertEqual(len(server.SEP), 1)
        self.assertTrue(server.SEP.isprintable())
        self.assertNotEqual(server.SEP, " ")

    def test_sep_cannot_appear_in_session_name(self) -> None:
        self.assertNotRegex(server.SEP, server.NAME_RE)


class CmdArgvTests(unittest.TestCase):
    def test_shell_argv_is_a_login_shell(self) -> None:
        # `shell` sessions launch a plain login shell. The `target` arg is
        # unused — tmux's `new-session -c <dir>` handles cwd. No bwrap
        # wrapper any more (see chore/remove-bwrap-sandbox).
        argv = server.cmd_argv("shell", Path("/home/adam/workspace/api"))
        self.assertEqual(len(argv), 2)
        self.assertIn(argv[0], server.SAFE_SHELLS)
        self.assertEqual(argv[1], "-l")

    def test_shell_argv_same_with_or_without_target(self) -> None:
        # `target` is accepted for API compatibility but does not affect argv.
        a = server.cmd_argv("shell")
        b = server.cmd_argv("shell", Path("/some/where"))
        self.assertEqual(a, b)

    def test_claude_argv_now_rejected(self) -> None:
        # "claude" is no longer a session-creation label — sessions are
        # always plain shells, claude launches from inside the shell
        # by typing it as a command. The label must be rejected like any
        # other unknown command.
        with self.assertRaises(server.ApiError) as ctx:
            server.cmd_argv("claude")
        self.assertEqual(ctx.exception.status, 400)

    def test_unknown_label_rejected(self) -> None:
        with self.assertRaises(server.ApiError) as ctx:
            server.cmd_argv("ls")
        self.assertEqual(ctx.exception.status, 400)


class IdentityTests(unittest.TestCase):
    """Handler._identity is the trust boundary for per-user isolation."""

    @staticmethod
    def _identity(*values: str) -> str:
        headers = Message()
        for value in values:
            headers["Remote-User"] = value
        fake: Any = type("FakeHandler", (), {"headers": headers})()
        return server.Handler._identity(fake)

    def test_single_valid_identity(self) -> None:
        self.assertEqual(self._identity("alice"), "alice")

    def test_missing_identity_rejected(self) -> None:
        with self.assertRaises(server.ApiError):
            self._identity()

    def test_ambiguous_identity_rejected(self) -> None:
        # A spoofed header alongside Authelia's verified one — refuse outright
        # rather than guess which identity is genuine.
        with self.assertRaises(server.ApiError):
            self._identity("attacker", "victim")

    def test_malformed_identity_rejected(self) -> None:
        with self.assertRaises(server.ApiError):
            self._identity("Bad User!")


if __name__ == "__main__":
    unittest.main(verbosity=2)
