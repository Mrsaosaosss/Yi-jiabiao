from __future__ import annotations

import copy
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
import time
import webbrowser
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from data_source import (
    DashboardError,
    PLUGIN_VERSION,
    CodexSQLiteDataSource,
)


COOKIE_NAME = "codex_progress_session"
STATIC_TYPES = {
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".svg": "image/svg+xml",
}


class SnapshotState:
    def __init__(self, data_source: CodexSQLiteDataSource, interval: float = 0.8):
        self.data_source = data_source
        self.interval = interval
        self._condition = threading.Condition()
        self._snapshot: dict[str, Any] = {
            "version": 1,
            "generated_at": int(time.time() * 1000),
            "freshness_target_ms": 1000,
            "summary": {},
            "tasks": [],
            "health": {"status": "starting", "stale": True},
        }
        self._revision = 0
        self._signature = ""
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    @property
    def revision(self) -> int:
        with self._condition:
            return self._revision

    def start(self) -> None:
        self.refresh()
        self._thread = threading.Thread(target=self._run, name="snapshot-observer", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        with self._condition:
            self._condition.notify_all()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)

    def get(self) -> tuple[int, dict[str, Any]]:
        with self._condition:
            return self._revision, copy.deepcopy(self._snapshot)

    def wait_after(self, revision: int, timeout: float = 15.0) -> tuple[int, dict[str, Any]]:
        with self._condition:
            self._condition.wait_for(
                lambda: self._revision > revision or self._stop.is_set(), timeout=timeout
            )
            return self._revision, copy.deepcopy(self._snapshot)

    def refresh(self) -> None:
        try:
            snapshot = self.data_source.collect()
        except (DashboardError, sqlite3.Error, OSError) as error:
            _, previous = self.get()
            now_ms = int(time.time() * 1000)
            for task in previous.get("tasks", []):
                task["stale"] = True
            code = getattr(error, "code", "database_temporarily_unavailable")
            previous.update(
                {
                    "generated_at": now_ms,
                    "health": {
                        "status": code,
                        "message": str(error),
                        "plugin_version": PLUGIN_VERSION,
                        "stale": True,
                    },
                }
            )
            snapshot = previous

        encoded = json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        signature = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        with self._condition:
            if signature != self._signature:
                self._signature = signature
                self._snapshot = snapshot
                self._revision += 1
                self._condition.notify_all()

    def _run(self) -> None:
        while not self._stop.wait(self.interval):
            self.refresh()
class DashboardHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        state: SnapshotState,
        web_root: Path,
        token: str,
    ):
        super().__init__(address, DashboardHandler)
        self.state = state
        self.web_root = web_root.resolve()
        self.token = token
        self.client_count = 0
        self.client_lock = threading.Lock()
        self.last_client_at = time.monotonic()

    def client_opened(self) -> None:
        with self.client_lock:
            self.client_count += 1
            self.last_client_at = time.monotonic()

    def client_closed(self) -> None:
        with self.client_lock:
            self.client_count = max(0, self.client_count - 1)
            self.last_client_at = time.monotonic()

    def touch(self) -> None:
        with self.client_lock:
            self.last_client_at = time.monotonic()


class DashboardHandler(BaseHTTPRequestHandler):
    server: DashboardHTTPServer
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *args: object) -> None:
        return

    def _security_headers(self, content_type: str) -> None:
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; "
            "base-uri 'none'; form-action 'none'",
        )

    def _authorized(self) -> bool:
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        supplied = cookie.get(COOKIE_NAME)
        return bool(supplied and hmac.compare_digest(supplied.value, self.server.token))

    def _send_bytes(self, status: HTTPStatus, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self._security_headers(content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_json(self, status: HTTPStatus, value: Any) -> None:
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._send_bytes(status, body, "application/json; charset=utf-8")

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        bootstrap_prefix = "/bootstrap/"
        if path.startswith(bootstrap_prefix):
            supplied = path[len(bootstrap_prefix) :]
            if not hmac.compare_digest(supplied, self.server.token):
                self._send_bytes(HTTPStatus.FORBIDDEN, b"Forbidden", "text/plain; charset=utf-8")
                return
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "/")
            self.send_header(
                "Set-Cookie",
                f"{COOKIE_NAME}={self.server.token}; Path=/; HttpOnly; SameSite=Strict",
            )
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if not self._authorized():
            self._send_bytes(HTTPStatus.UNAUTHORIZED, b"Unauthorized", "text/plain; charset=utf-8")
            return

        self.server.touch()
        if path == "/api/snapshot":
            _revision, snapshot = self.server.state.get()
            self._send_json(HTTPStatus.OK, snapshot)
            return
        if path == "/api/health":
            revision, snapshot = self.server.state.get()
            health = dict(snapshot.get("health", {}))
            health.update({"revision": revision, "clients": self.server.client_count})
            self._send_json(HTTPStatus.OK, health)
            return
        if path == "/events":
            self._serve_events()
            return

        relative = "index.html" if path in {"", "/"} else path.lstrip("/")
        candidate = (self.server.web_root / relative).resolve()
        try:
            candidate.relative_to(self.server.web_root)
        except ValueError:
            self._send_bytes(HTTPStatus.NOT_FOUND, b"Not found", "text/plain; charset=utf-8")
            return
        if not candidate.is_file():
            self._send_bytes(HTTPStatus.NOT_FOUND, b"Not found", "text/plain; charset=utf-8")
            return
        content_type = STATIC_TYPES.get(candidate.suffix.lower(), "application/octet-stream")
        self._send_bytes(HTTPStatus.OK, candidate.read_bytes(), content_type)

    def _serve_events(self) -> None:
        self.send_response(HTTPStatus.OK)
        self._security_headers("text/event-stream; charset=utf-8")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        self.server.client_opened()
        revision = -1
        try:
            while True:
                next_revision, snapshot = self.server.state.wait_after(revision, timeout=15)
                if next_revision != revision:
                    payload = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"))
                    message = f"id: {next_revision}\nevent: snapshot\ndata: {payload}\n\n"
                    revision = next_revision
                else:
                    message = ": heartbeat\n\n"
                self.wfile.write(message.encode("utf-8"))
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError):
            pass
        finally:
            self.close_connection = True
            self.server.client_closed()


class DashboardRuntime:
    def __init__(
        self,
        plugin_root: Path,
        codex_home: str | os.PathLike[str] | None = None,
        runtime_file: Path | None = None,
        refresh_interval: float = 0.8,
    ):
        self.plugin_root = plugin_root.resolve()
        self.data_source = CodexSQLiteDataSource(codex_home)
        self.state = SnapshotState(self.data_source, refresh_interval)
        self.token = secrets.token_urlsafe(32)
        self.server: DashboardHTTPServer | None = None
        self.thread: threading.Thread | None = None
        self.runtime_file = runtime_file or (
            Path.home()
            / "Library"
            / "Application Support"
            / "CodexProgressDashboard"
            / "runtime.json"
        )

    @property
    def base_url(self) -> str:
        if not self.server:
            raise RuntimeError("Dashboard is not running")
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    @property
    def bootstrap_url(self) -> str:
        return f"{self.base_url}/bootstrap/{self.token}"

    def start(self) -> "DashboardRuntime":
        if self.server:
            return self
        self.state.start()
        self.server = DashboardHTTPServer(
            ("127.0.0.1", 0), self.state, self.plugin_root / "web", self.token
        )
        self.thread = threading.Thread(
            target=self.server.serve_forever, name="dashboard-http", daemon=True
        )
        self.thread.start()
        self._write_runtime_file()
        return self

    def open_browser(self) -> bool:
        return webbrowser.open(self.bootstrap_url, new=2)

    def health(self) -> dict[str, Any]:
        revision, snapshot = self.state.get()
        health = dict(snapshot.get("health", {}))
        health.update(
            {
                "running": self.server is not None,
                "base_url": self.base_url if self.server else None,
                "revision": revision,
                "clients": self.server.client_count if self.server else 0,
                "codex_home": str(self.data_source.codex_home),
            }
        )
        return health

    def stop(self) -> None:
        server = self.server
        self.server = None
        if server:
            server.shutdown()
            server.server_close()
        self.state.stop()
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=2)
        self._remove_runtime_file()

    def _write_runtime_file(self) -> None:
        payload = {
            "version": 1,
            "pluginVersion": PLUGIN_VERSION,
            "pid": os.getpid(),
            "baseURL": self.base_url,
            "bootstrapURL": self.bootstrap_url,
            "pluginRoot": str(self.plugin_root),
            "startedAt": int(time.time() * 1000),
        }
        self.runtime_file.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.runtime_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        os.chmod(temporary, 0o600)
        temporary.replace(self.runtime_file)
        os.chmod(self.runtime_file, 0o600)

    def _remove_runtime_file(self) -> None:
        try:
            current = json.loads(self.runtime_file.read_text(encoding="utf-8"))
            if current.get("pid") == os.getpid():
                self.runtime_file.unlink(missing_ok=True)
        except (OSError, json.JSONDecodeError):
            pass
