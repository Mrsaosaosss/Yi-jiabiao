#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path
from typing import Any

from runtime import DashboardRuntime


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
SERVER_NAME = "codex-progress-dashboard"
SERVER_VERSION = "0.1.0"
_runtime: DashboardRuntime | None = None
_runtime_lock = threading.Lock()


TOOLS = [
    {
        "name": "open_progress_dashboard",
        "description": "Open the private local browser dashboard for all Codex task progress.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "open_browser": {
                    "type": "boolean",
                    "description": "Open the dashboard in the default browser. Defaults to true.",
                    "default": True,
                }
            },
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
    },
    {
        "name": "show_progress_hud",
        "description": "Launch or focus the read-only macOS notch HUD for Codex task progress.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
    },
    {
        "name": "progress_dashboard_status",
        "description": "Check observer health, compatibility, connection count, and local URL.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
    },
]


def runtime_file() -> Path:
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "CodexProgressDashboard"
        / "runtime.json"
    )


def external_runtime() -> dict[str, Any] | None:
    try:
        value = json.loads(runtime_file().read_text(encoding="utf-8"))
        pid = int(value["pid"])
        os.kill(pid, 0)
        if not isinstance(value.get("bootstrapURL"), str):
            return None
        return value
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


def ensure_runtime() -> tuple[DashboardRuntime | None, dict[str, Any]]:
    global _runtime
    with _runtime_lock:
        if _runtime is not None:
            return _runtime, {
                "pid": os.getpid(),
                "baseURL": _runtime.base_url,
                "bootstrapURL": _runtime.bootstrap_url,
                "pluginRoot": str(PLUGIN_ROOT),
            }
        existing = external_runtime()
        if existing is not None:
            return None, existing
        if _runtime is None:
            _runtime = DashboardRuntime(PLUGIN_ROOT).start()
        return _runtime, {
            "pid": os.getpid(),
            "baseURL": _runtime.base_url,
            "bootstrapURL": _runtime.bootstrap_url,
            "pluginRoot": str(PLUGIN_ROOT),
        }


def tool_result(value: dict[str, Any], is_error: bool = False) -> dict[str, Any]:
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(value, ensure_ascii=False, separators=(",", ":")),
            }
        ],
        "structuredContent": value,
        "isError": is_error,
    }


def call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "open_progress_dashboard":
        _owned_runtime, info = ensure_runtime()
        should_open = arguments.get("open_browser", True)
        opened = webbrowser.open(str(info["bootstrapURL"]), new=2) if should_open else False
        return tool_result(
            {
                "ok": True,
                "opened": opened,
                "url": info["bootstrapURL"],
                "message": "The local Codex progress dashboard is ready.",
            }
        )
    if name == "show_progress_hud":
        _owned_runtime, info = ensure_runtime()
        app = PLUGIN_ROOT / "macos" / "build" / "CodexProgressHUD.app"
        if not app.is_dir():
            return tool_result(
                {
                    "ok": False,
                    "code": "hud_not_built",
                    "message": "The macOS HUD has not been built. Run scripts/build_hud.sh.",
                    "dashboard_url": info["bootstrapURL"],
                },
                is_error=True,
            )
        try:
            subprocess.Popen(
                ["open", "-a", str(app)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as error:
            return tool_result(
                {"ok": False, "code": "hud_launch_failed", "message": str(error)},
                is_error=True,
            )
        return tool_result(
            {
                "ok": True,
                "message": "The Codex progress HUD is open.",
                "dashboard_url": info["bootstrapURL"],
            }
        )
    if name == "progress_dashboard_status":
        if _runtime is None and external_runtime() is None:
            return tool_result(
                {
                    "ok": True,
                    "running": False,
                    "message": "The observer has not been started in this plugin session.",
                }
            )
        if _runtime is not None:
            health = _runtime.health()
            health["ok"] = health.get("status") == "ok"
            return tool_result(health, is_error=not health["ok"])
        info = external_runtime() or {}
        return tool_result(
            {
                "ok": True,
                "running": True,
                "managed_by": "external_local_process",
                "base_url": info.get("baseURL"),
                "message": "The local observer is running in another process.",
            }
        )
    return tool_result(
        {"ok": False, "code": "unknown_tool", "message": f"Unknown tool: {name}"},
        is_error=True,
    )


def handle(message: dict[str, Any]) -> dict[str, Any] | None:
    request_id = message.get("id")
    method = message.get("method")
    if method == "initialize":
        requested = message.get("params", {}).get("protocolVersion")
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": requested or "2025-06-18",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                "instructions": "Read-only local Codex task progress dashboard and macOS HUD.",
            },
        }
    if method in {"notifications/initialized", "initialized", "notifications/cancelled"}:
        return None
    if method == "ping":
        return {"jsonrpc": "2.0", "id": request_id, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = message.get("params") or {}
        try:
            result = call_tool(str(params.get("name", "")), params.get("arguments") or {})
            return {"jsonrpc": "2.0", "id": request_id, "result": result}
        except Exception as error:  # Keep protocol errors on stdout and diagnostics content-free.
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": tool_result(
                    {"ok": False, "code": "internal_error", "message": str(error)},
                    is_error=True,
                ),
            }
    if request_id is None:
        return None
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def main() -> int:
    try:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
                response = handle(message)
            except (json.JSONDecodeError, TypeError, ValueError) as error:
                response = {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": f"Parse error: {error}"},
                }
            if response is not None:
                sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
                sys.stdout.flush()
    finally:
        if _runtime is not None:
            _runtime.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
