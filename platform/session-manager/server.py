#!/usr/bin/env python3
"""Claude session-manager — JSON API behind the platform dashboard.

A tiny HTTP service that lets the dashboard's "Claude sessions" section list,
create, and stop the per-user, tmux-backed Claude Code sessions that ttyd
serves in the browser.

It is reached only via Caddy at ``<dashboard-host>/api/*``. Caddy gates that
route with Authelia and forwards the authenticated identity as the
``Remote-User`` header (with client-supplied copies of that header stripped
first — see platform/caddy/Caddyfile.template). This service trusts that
header for the *current request's* identity and namespaces every tmux call
onto a per-user socket, so one user can never see or touch another's
sessions.

No third-party dependencies — standard library only. Runs as a systemd unit
under the same OS account as ttyd, because it needs that account's tmux
sockets and PATH (to find ``tmux`` and ``claude``).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote

# --- configuration (the systemd unit sets these; defaults cover dev use) ---
HOME = Path(os.environ.get("HOME", str(Path.home())))
WORKSPACE_ROOT = Path(os.environ.get("CLAUDE_WORKSPACE_ROOT", HOME / "workspace"))
SOCKET_DIR = Path(os.environ.get("CLAUDE_SOCKET_DIR", HOME / ".claude-sessions"))
TMUX_CONF = Path(os.environ.get(
    "CLAUDE_TMUX_CONF", "/opt/infra/platform/ttyd/claude-tmux.conf"))
LISTEN_ADDR = os.environ.get("SM_LISTEN_ADDR", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("SM_LISTEN_PORT", "7682"))

# A session name: 1–32 chars, starts alphanumeric, then alphanumeric / _ / -.
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$")
# A username: the shape platform/authelia/add-user.sh enforces.
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,30}$")
# Field separator for `tmux list-sessions -F` — a control byte that cannot
# occur in a session name or a filesystem path.
SEP = "\x1f"
TMUX_TIMEOUT = 10
MAX_BODY = 64 * 1024


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
        parts = line.split(SEP)
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
        })
    sessions.sort(key=lambda s: s["name"])
    return sessions


def create_session(user: str, name: str, req_dir: str) -> None:
    """Create a detached session running `claude` in a confined directory."""
    if not NAME_RE.match(name):
        raise ApiError(400, "invalid session name "
                            "(letters, digits, _ and -, max 32)")
    target = confine_dir(req_dir)
    try:
        target.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ApiError(500, f"cannot create {target}") from exc
    res = _run(_tmux_base(user) + ["new-session", "-d", "-s", name,
                                   "-c", str(target), "claude"])
    if res.returncode != 0:
        stderr = res.stderr.strip()
        if "duplicate" in stderr.lower():
            raise ApiError(409, f"session '{name}' already exists")
        raise ApiError(500, stderr or "failed to create session")


def kill_session(user: str, name: str) -> None:
    """Stop a session (and the Claude process inside it)."""
    if not NAME_RE.match(name):
        raise ApiError(400, "invalid session name")
    res = _run(_tmux_base(user) + ["kill-session", "-t", f"={name}"])
    if res.returncode != 0:
        stderr = res.stderr.strip()
        if "can't find" in stderr.lower() or "no such" in stderr.lower():
            raise ApiError(404, f"no session '{name}'")
        raise ApiError(500, stderr or "failed to stop session")


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
                create_session(user, name, str(body.get("dir", "")).strip())
                log("info", "session created", user=user, session=name)
                self._send_json(201, {"ok": True, "name": name})
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
        sockets=str(SOCKET_DIR))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
