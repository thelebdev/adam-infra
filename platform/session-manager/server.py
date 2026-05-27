#!/usr/bin/env python3
"""session-manager — JSON API behind the platform dashboard.

A tiny HTTP service that lets the dashboard's "Terminal sessions" section
list, create, and stop the per-user, tmux-backed browser terminal sessions
that ttyd serves. Every session runs a bubblewrap-sandboxed login shell
inside the user's workspace; Claude Code launches from inside the shell
via the TOTP-gated ``claude`` shim on PATH.

It is reached only via Caddy at ``<dashboard-host>/api/*``. Caddy gates that
route with Authelia and forwards the authenticated identity as the
``Remote-User`` header (with client-supplied copies of that header stripped
first — see platform/caddy/Caddyfile.template). This service trusts that
header for the *current request's* identity and namespaces every tmux call
onto a per-user socket, so one user can never see or touch another's
sessions.

No third-party dependencies — standard library only. Runs as a systemd unit
under the same OS account as ttyd, because it needs that account's tmux
sockets and PATH (to find ``tmux``).
"""
from __future__ import annotations

import json
import os
import pwd
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote

# --- configuration (the systemd unit sets these; defaults cover dev use) ---
HOME = Path(os.environ.get("HOME", str(Path.home())))
WORKSPACE_ROOT = Path(os.environ.get("SESSION_WORKSPACE_ROOT", HOME / "workspace"))
SOCKET_DIR = Path(os.environ.get("SESSION_SOCKET_DIR", HOME / ".terminal-sessions"))
TMUX_CONF = Path(os.environ.get(
    "SESSION_TMUX_CONF", "/opt/infra/platform/ttyd/session-tmux.conf"))
INFRA_ROOT = Path(os.environ.get("INFRA_ROOT", "/opt/infra"))
LISTEN_ADDR = os.environ.get("SM_LISTEN_ADDR", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("SM_LISTEN_PORT", "7682"))

# Components that drop a `.version.json` after rendering. Read by /api/version
# to surface drift between the current git HEAD and what's actually deployed.
VERSION_COMPONENTS = ("caddy", "ttyd", "dashboard", "session-manager")

# A session name: 1–32 chars, starts alphanumeric, then alphanumeric / _ / -.
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$")
# A username: the shape platform/authelia/add-user.sh enforces.
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,30}$")
# Field separator for `tmux list-sessions -F`. A printable character is
# essential — tmux 3.x escapes non-printable bytes in formatted output (the
# byte 0x1f becomes the literal four-character sequence ``\037``), which
# breaks any single-character control-byte separator. `|` cannot appear in
# session names (NAME_RE), is rare in paths, and never escaped by tmux. The
# trailing field (path) is captured with a max-split so any stray `|` inside
# a path remains part of the path rather than producing extra columns.
SEP = "|"
TMUX_TIMEOUT = 10
MAX_BODY = 64 * 1024

# Allowed command choices and the default. Sessions are always sandboxed
# shells today; Claude Code launches from inside the shell via the
# TOTP-gated `claude` shim. The single-entry tuple is kept for the
# marker-file and label-routing code that still reads/writes a command
# label per session.
CMD_ALLOWLIST = ("shell",)
CMD_DEFAULT = "shell"
SAFE_SHELLS = {"/bin/bash", "/usr/bin/bash", "/bin/zsh", "/usr/bin/zsh",
               "/bin/sh", "/usr/bin/sh"}


def log(level: str, msg: str, **fields: Any) -> None:
    """Emit one structured JSON log line to stdout (systemd captures it)."""
    record: dict[str, Any] = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "level": level,
        "service": "session-manager",
        "msg": msg,
    }
    record.update(fields)
    print(json.dumps(record), flush=True)


class ApiError(Exception):
    """An error with an HTTP status — turned into a JSON response."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


# --- workspace confinement -------------------------------------------------

def confine_dir(req: str) -> Path:
    """Resolve a directory request to an absolute path strictly inside the
    workspace root. Raises ApiError(400) if it escapes — via an absolute
    path, a ``..`` climb, or a symlink that leads out. The path need not
    exist yet."""
    root = Path(os.path.realpath(WORKSPACE_ROOT))
    req = (req or "").strip()
    if not req:
        return root
    candidate = Path(req) if req.startswith("/") else root / req
    resolved = Path(os.path.realpath(candidate))
    if resolved != root and root not in resolved.parents:
        raise ApiError(400, "directory is outside the workspace")
    return resolved


def workspace_dirs(limit: int = 200) -> list[str]:
    """Workspace-relative directory paths, up to two levels deep, for the
    'new session' directory picker. Hidden directories are skipped."""
    root = Path(os.path.realpath(WORKSPACE_ROOT))
    if not root.is_dir():
        return []
    found: list[str] = []
    try:
        level1 = sorted(p for p in root.iterdir()
                        if p.is_dir() and not p.name.startswith("."))
    except OSError:
        return []
    for top in level1:
        found.append(top.name)
        try:
            for sub in sorted(p for p in top.iterdir()
                              if p.is_dir() and not p.name.startswith(".")):
                found.append(f"{top.name}/{sub.name}")
        except OSError:
            pass
        if len(found) >= limit:
            break
    return found[:limit]


# --- commands --------------------------------------------------------------

def resolve_shell() -> str:
    """The OS shell to run for a 'shell' session — the running account's
    /etc/passwd shell if it's a familiar one, otherwise /bin/bash. The
    service runs as a single OS account, so this is the same for everyone."""
    try:
        shell = pwd.getpwuid(os.geteuid()).pw_shell
    except KeyError:
        shell = ""
    return shell if shell in SAFE_SHELLS else "/bin/bash"


def cmd_argv(label: str, target: Path | None = None) -> list[str]:
    """Resolve a command label to the argv tmux should spawn. Raises
    ApiError(400) for an unknown label — the allowlist is the boundary.

    `target` is accepted for API compatibility but unused — tmux's
    ``new-session -c <dir>`` (set by the caller) handles the initial cwd,
    so the argv just needs to be a login shell. Claude Code, if needed,
    is started inside the shell by the operator running ``claude``.
    """
    del target  # see docstring — tmux -c handles cwd
    if label == "shell":
        return [resolve_shell(), "-l"]
    raise ApiError(400, f"unknown command '{label}'")


def _git_head_short() -> str:
    """Current short HEAD of the infra repo, or 'unknown' if git fails."""
    try:
        res = subprocess.run(
            ["git", "-C", str(INFRA_ROOT), "rev-parse", "--short=10", "HEAD"],
            capture_output=True, text=True, timeout=2, check=False)
        sha = res.stdout.strip()
        return sha or "unknown"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return "unknown"


def read_version() -> dict[str, Any]:
    """Aggregate per-component .version.json stamps with the current git HEAD.

    `drift` is True if any rendered component's sha doesn't match HEAD — i.e.,
    a commit landed in the repo but the corresponding render step didn't
    actually re-run. The `dirty` suffix added by write_version_json is stripped
    before comparison so an uncommitted local edit doesn't trigger false drift.
    """
    head = _git_head_short()
    components: dict[str, Any] = {}
    drifted: list[str] = []
    for comp in VERSION_COMPONENTS:
        path = INFRA_ROOT / "platform" / comp / ".version.json"
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            components[comp] = None
            drifted.append(comp)
            continue
        components[comp] = data
        comp_sha = str(data.get("git_sha", "")).split("-", 1)[0]
        if head != "unknown" and comp_sha and comp_sha != head:
            drifted.append(comp)
    return {
        "git_sha": head,
        "components": components,
        "drift": bool(drifted),
        "drifted_components": drifted,
    }


def claude_installed() -> bool:
    """True if `claude` is on PATH for the service account.

    Sessions no longer pick `claude` as a launch command (every session is
    a sandboxed shell, and claude is invoked from inside the shell via the
    TOTP-gated shim). This is still exposed via /api/version so the
    dashboard can surface whether the `claude` binary is present on the
    host — relevant to operators planning to use the in-shell launcher."""
    for p in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(p) / "claude"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return True
    return False


# --- marker files ----------------------------------------------------------
# One file per session at SOCKET_DIR/<user>/<name>.cmd holding the label
# ("shell" or "claude"). tmux itself doesn't expose what's running cleanly,
# and the dashboard needs to render that — the marker is the source of truth.

def _user_marker_dir(user: str) -> Path:
    return SOCKET_DIR / user


def _marker_path(user: str, name: str) -> Path:
    return _user_marker_dir(user) / f"{name}.cmd"


def write_marker(user: str, name: str, label: str) -> None:
    d = _user_marker_dir(user)
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    _marker_path(user, name).write_text(label + "\n")


def read_marker(user: str, name: str) -> str:
    try:
        value = _marker_path(user, name).read_text().strip()
    except OSError:
        return CMD_DEFAULT
    return value if value in CMD_ALLOWLIST else CMD_DEFAULT


def clear_marker(user: str, name: str) -> None:
    try:
        _marker_path(user, name).unlink()
    except OSError:
        pass


# --- tmux -----------------------------------------------------------------

def _tmux_base(user: str) -> list[str]:
    """The `tmux` command prefix for one user's private session socket."""
    base = ["tmux"]
    if TMUX_CONF.is_file():
        base += ["-f", str(TMUX_CONF)]
    base += ["-S", str(SOCKET_DIR / f"{user}.sock")]
    return base


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    """Run a command with no shell, a timeout, and explicit error mapping."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=TMUX_TIMEOUT, check=False)
    except FileNotFoundError as exc:
        raise ApiError(500, "tmux is not installed") from exc
    except subprocess.TimeoutExpired as exc:
        raise ApiError(504, "tmux timed out") from exc


def list_sessions(user: str) -> list[dict[str, Any]]:
    """Every session on the user's socket. An absent tmux server (no sessions
    started yet) is normal and yields an empty list, not an error."""
    fmt = SEP.join(["#{session_name}", "#{session_windows}",
                    "#{session_attached}", "#{session_created}",
                    "#{session_activity}", "#{pane_current_path}"])
    res = _run(_tmux_base(user) + ["list-sessions", "-F", fmt])
    if res.returncode != 0:
        return []
    now = int(time.time())
    sessions: list[dict[str, Any]] = []
    for line in res.stdout.splitlines():
        # Path is the last field — use a max-split so any `|` inside a path
        # stays with the path rather than producing extra columns.
        parts = line.split(SEP, 5)
        if len(parts) != 6:
            continue
        name, windows, attached, created, activity, path = parts
        activity_i = int(activity) if activity.isdigit() else now
        sessions.append({
            "name": name,
            "windows": int(windows) if windows.isdigit() else 0,
            "attached": attached == "1",
            "created": int(created) if created.isdigit() else 0,
            "activity": activity_i,
            "idle_seconds": max(0, now - activity_i),
            "dir": path,
            "cmd": read_marker(user, name),
        })
    sessions.sort(key=lambda s: s["name"])
    return sessions


def create_session(user: str, name: str, req_dir: str,
                   cmd: str = CMD_DEFAULT) -> None:
    """Create a detached session running `cmd` in a confined directory.
    Writes a marker file so list/resume agree on what's running."""
    if not NAME_RE.match(name):
        raise ApiError(400, "invalid session name "
                            "(letters, digits, _ and -, max 32)")
    if cmd not in CMD_ALLOWLIST:
        raise ApiError(400, f"invalid command '{cmd}' "
                            f"(allowed: {', '.join(CMD_ALLOWLIST)})")
    target = confine_dir(req_dir)
    try:
        target.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ApiError(500, f"cannot create {target}") from exc
    write_marker(user, name, cmd)
    argv = cmd_argv(cmd, target)
    res = _run(_tmux_base(user) + ["new-session", "-d", "-s", name,
                                   "-c", str(target), "--", *argv])
    if res.returncode != 0:
        clear_marker(user, name)
        stderr = res.stderr.strip()
        if "duplicate" in stderr.lower():
            raise ApiError(409, f"session '{name}' already exists")
        raise ApiError(500, stderr or "failed to create session")


def kill_session(user: str, name: str) -> None:
    """Stop a session (and the process inside it)."""
    if not NAME_RE.match(name):
        raise ApiError(400, "invalid session name")
    res = _run(_tmux_base(user) + ["kill-session", "-t", f"={name}"])
    if res.returncode != 0:
        stderr = res.stderr.strip()
        if "can't find" in stderr.lower() or "no such" in stderr.lower():
            raise ApiError(404, f"no session '{name}'")
        raise ApiError(500, stderr or "failed to stop session")
    clear_marker(user, name)


# --- HTTP -----------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    # HTTP/1.0: one request per connection. The dashboard polls every few
    # seconds — a fresh localhost connection each time is free, and it sidesteps
    # any keep-alive body-draining hazard on unmatched routes.
    server_version = "session-manager/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:  # noqa: A003
        """Silence the default stderr access log; we log per request below."""

    def _identity(self) -> str:
        """The authenticated user from the Remote-User header.

        Caddy strips any client-supplied Remote-User before forward_auth and
        then sets exactly one value from Authelia's verified response. Seeing
        zero or several values means something is wrong upstream — refuse
        rather than guess which identity is genuine."""
        values = self.headers.get_all("Remote-User") or []
        unique = {v.strip() for v in values if v.strip()}
        if len(unique) != 1:
            raise ApiError(401, "missing or ambiguous identity")
        user = unique.pop()
        if not USER_RE.match(user):
            raise ApiError(401, "malformed identity")
        return user

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > MAX_BODY:
            raise ApiError(400, "missing or oversized request body")
        try:
            data = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as exc:
            raise ApiError(400, "invalid JSON") from exc
        if not isinstance(data, dict):
            raise ApiError(400, "expected a JSON object")
        return data

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _dispatch(self, method: str) -> None:
        path = self.path.split("?", 1)[0].rstrip("/")
        try:
            if path == "/api/health":
                self._send_json(200, {"status": "ok"})
                return
            if method == "GET" and path == "/api/capabilities":
                # Unauthenticated: tells the dashboard which cmd options to
                # show. No user-specific data, only server-side feature flags.
                self._send_json(200, {
                    "commands": list(CMD_ALLOWLIST),
                    "claude_installed": claude_installed(),
                })
                return
            if method == "GET" and path == "/api/version":
                # Unauthenticated: surfaces the deploy state (git HEAD + each
                # render step's last stamp). The dashboard reads this on every
                # page load to render the footer and flag config drift, so it
                # needs to work even before user-specific data resolves.
                self._send_json(200, read_version())
                return
            user = self._identity()
            if method == "GET" and path == "/api/sessions":
                self._send_json(200, {"user": user,
                                      "sessions": list_sessions(user)})
            elif method == "GET" and path == "/api/workspace":
                self._send_json(200, {"root": str(WORKSPACE_ROOT),
                                      "dirs": workspace_dirs()})
            elif method == "POST" and path == "/api/sessions":
                body = self._read_json()
                name = str(body.get("name", "")).strip()
                cmd = str(body.get("cmd", CMD_DEFAULT)).strip() or CMD_DEFAULT
                create_session(user, name,
                               str(body.get("dir", "")).strip(), cmd)
                log("info", "session created", user=user, session=name, cmd=cmd)
                self._send_json(201, {"ok": True, "name": name, "cmd": cmd})
            elif method == "DELETE" and path.startswith("/api/sessions/"):
                name = unquote(path[len("/api/sessions/"):])
                kill_session(user, name)
                log("info", "session stopped", user=user, session=name)
                self._send_json(200, {"ok": True, "name": name})
            else:
                raise ApiError(404, "not found")
        except ApiError as exc:
            self._send_json(exc.status, {"error": exc.message})
        except Exception as exc:  # noqa: BLE001 - last-resort guard
            log("error", "unhandled exception", path=path, error=repr(exc))
            self._send_json(500, {"error": "internal error"})

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")


def main() -> None:
    SOCKET_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(SOCKET_DIR, 0o700)
    WORKSPACE_ROOT.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((LISTEN_ADDR, LISTEN_PORT), Handler)
    log("info", "session-manager listening", addr=LISTEN_ADDR,
        port=LISTEN_PORT, workspace=str(WORKSPACE_ROOT),
        sockets=str(SOCKET_DIR), claude_installed=claude_installed())
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
