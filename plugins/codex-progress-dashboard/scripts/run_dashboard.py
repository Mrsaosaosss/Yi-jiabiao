#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
import webbrowser
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
SERVER_ROOT = PLUGIN_ROOT / "server"
sys.path.insert(0, str(SERVER_ROOT))

from runtime import DashboardRuntime  # noqa: E402


def runtime_file() -> Path:
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "CodexProgressDashboard"
        / "runtime.json"
    )


def existing_runtime() -> dict[str, object] | None:
    try:
        value = json.loads(runtime_file().read_text(encoding="utf-8"))
        pid = int(value["pid"])
        os.kill(pid, 0)
        return value
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the local Codex progress dashboard.")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--idle-timeout", type=int, default=600)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    active = existing_runtime()
    if active:
        url = str(active.get("bootstrapURL", ""))
        if url and not args.no_browser:
            webbrowser.open(url, new=2)
        print(url)
        return 0

    runtime = DashboardRuntime(PLUGIN_ROOT).start()
    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    if not args.no_browser:
        runtime.open_browser()
    print(runtime.bootstrap_url, flush=True)
    try:
        while not stopping:
            time.sleep(1)
            server = runtime.server
            if (
                args.idle_timeout > 0
                and server is not None
                and server.client_count == 0
                and time.monotonic() - server.last_client_at > args.idle_timeout
            ):
                break
    finally:
        runtime.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
