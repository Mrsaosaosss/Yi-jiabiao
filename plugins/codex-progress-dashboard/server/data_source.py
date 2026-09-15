from __future__ import annotations

import json
import os
import re
import sqlite3
import time
from collections import defaultdict
from contextlib import closing
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote


PLUGIN_VERSION = "0.1.0"
RECENT_COMPLETED_MS = 24 * 60 * 60 * 1000
ACTIVE_STALE_MS = 12 * 60 * 60 * 1000


class DashboardError(RuntimeError):
    code = "dashboard_error"


class MissingCodexData(DashboardError):
    code = "missing_codex_data"


class SchemaIncompatible(DashboardError):
    code = "schema_incompatible"


def _numbered_database(codex_home: Path, prefix: str) -> Path:
    matches: list[tuple[int, Path]] = []
    pattern = re.compile(rf"^{re.escape(prefix)}_(\d+)\.sqlite$")
    for candidate in codex_home.glob(f"{prefix}_*.sqlite"):
        match = pattern.match(candidate.name)
        if match and candidate.is_file():
            matches.append((int(match.group(1)), candidate))
    if not matches:
        raise MissingCodexData(f"No {prefix} database was found in {codex_home}")
    return max(matches, key=lambda item: item[0])[1]


def discover_codex_home(explicit: str | os.PathLike[str] | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    configured = os.environ.get("CODEX_HOME")
    if configured:
        return Path(configured).expanduser().resolve()
    return (Path.home() / ".codex").resolve()


def _read_only_connection(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise MissingCodexData(f"Required Codex database is missing: {path.name}")
    connection = sqlite3.connect(
        f"{path.resolve().as_uri()}?mode=ro",
        uri=True,
        timeout=0.15,
        check_same_thread=False,
    )
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    connection.execute("PRAGMA busy_timeout = 150")
    return connection


def _columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {str(row[1]) for row in connection.execute(f"PRAGMA table_info({table})")}


def _require_columns(
    connection: sqlite3.Connection, table: str, required: Iterable[str]
) -> None:
    actual = _columns(connection, table)
    missing = set(required) - actual
    if missing:
        names = ", ".join(sorted(missing))
        raise SchemaIncompatible(f"{table} is missing required columns: {names}")


def _milliseconds(value: Any) -> int | None:
    if value is None:
        return None
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    if number < 10_000_000_000:
        return number * 1000
    return number


def _text(value: Any, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    compact = " ".join(value.split())
    if len(compact) <= limit:
        return compact
    return compact[: max(0, limit - 1)].rstrip() + "…"


def _safe_json(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, str):
        return {}
    try:
        value = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {}
    return value if isinstance(value, dict) else {}


def _path_hint(cwd: str) -> str:
    path = Path(cwd)
    parts = [part for part in path.parts if part not in (path.anchor, "/")]
    if not parts:
        return cwd or "—"
    return "/".join(parts[-2:])


def _project_name(cwd: str) -> str:
    name = Path(cwd).name
    return name or cwd or "Unknown project"


def _waiting_item(item: dict[str, Any]) -> bool:
    flags = item.get("activeFlags")
    if isinstance(flags, list):
        lowered = {str(flag).lower() for flag in flags}
        if "waitingonapproval" in lowered or "waitingonuserinput" in lowered:
            return True
    for key in ("status", "approvalStatus", "state"):
        value = str(item.get(key, "")).lower().replace("_", "")
        if value in {
            "waitingonapproval",
            "waitingonuserinput",
            "requiresapproval",
            "requiresaction",
        }:
            return True
    return False


def _active_action(item_type: str, item: dict[str, Any]) -> str:
    status = str(item.get("status", "")).lower().replace("_", "")
    if status not in {"inprogress", "running", "started", "pending"}:
        return ""
    if item_type == "commandExecution":
        actions = item.get("commandActions")
        if isinstance(actions, list) and actions:
            first = actions[0] if isinstance(actions[0], dict) else {}
            label = first.get("name") or first.get("type") or first.get("command")
            return _text(f"Running {label}" if label else "Running a command", 160)
        return "Running a command"
    if item_type == "mcpToolCall":
        label = item.get("tool") or item.get("name")
        return _text(f"Using {label}" if label else "Using a tool", 160)
    return ""


def _plan_step(item: dict[str, Any]) -> str:
    plan = item.get("plan")
    if isinstance(plan, list):
        for entry in plan:
            if not isinstance(entry, dict):
                continue
            status = str(entry.get("status", "")).lower().replace("_", "")
            if status == "inprogress":
                return _text(entry.get("step") or entry.get("text"), 180)
    return _text(item.get("text"), 180)


class CodexSQLiteDataSource:
    """Versioned, read-only adapter for Codex's local SQLite projections."""

    adapter_version = "state-5-history-1"

    def __init__(self, codex_home: str | os.PathLike[str] | None = None):
        self.codex_home = discover_codex_home(codex_home)

    def database_paths(self) -> tuple[Path, Path]:
        return (
            _numbered_database(self.codex_home, "state"),
            _numbered_database(self.codex_home, "thread_history"),
        )

    def _validate(
        self, state: sqlite3.Connection, history: sqlite3.Connection
    ) -> None:
        _require_columns(
            state,
            "threads",
            {
                "id",
                "rollout_path",
                "created_at_ms",
                "updated_at_ms",
                "cwd",
                "title",
                "preview",
                "first_user_message",
                "name",
                "archived",
                "recency_at_ms",
                "source",
                "thread_source",
            },
        )
        _require_columns(
            history,
            "thread_turns",
            {
                "thread_id",
                "turn_id",
                "rollout_ordinal",
                "status",
                "started_at",
                "completed_at",
                "duration_ms",
            },
        )
        _require_columns(
            history,
            "thread_items",
            {
                "thread_id",
                "turn_id",
                "item_type",
                "item_json",
                "created_at_ms",
                "rollout_ordinal",
            },
        )

    def collect(self, now_ms: int | None = None) -> dict[str, Any]:
        generated_at = now_ms if now_ms is not None else int(time.time() * 1000)
        state_path, history_path = self.database_paths()
        with closing(_read_only_connection(state_path)) as state, closing(
            _read_only_connection(history_path)
        ) as history:
            self._validate(state, history)
            thread_rows = state.execute(
                """
                SELECT id, rollout_path, cwd, created_at_ms, updated_at_ms,
                       title, preview, first_user_message, name
                FROM threads
                WHERE archived = 0
                  AND (preview <> '' OR title <> '' OR name IS NOT NULL)
                  AND COALESCE(thread_source, 'user') NOT IN ('subagent', 'guardian_review')
                ORDER BY recency_at_ms DESC, id DESC
                LIMIT 1000
                """
            ).fetchall()
            turn_rows = history.execute(
                """
                WITH ranked AS (
                    SELECT thread_id, turn_id, rollout_ordinal, status,
                           started_at, completed_at, duration_ms, error_json,
                           ROW_NUMBER() OVER (
                               PARTITION BY thread_id
                               ORDER BY rollout_ordinal DESC, turn_id DESC
                           ) AS rank
                    FROM thread_turns
                )
                SELECT thread_id, turn_id, rollout_ordinal, status,
                       started_at, completed_at, duration_ms, error_json
                FROM ranked
                WHERE rank = 1
                """
            ).fetchall()
            item_rows = history.execute(
                """
                WITH latest AS (
                    SELECT thread_id, turn_id
                    FROM (
                        SELECT thread_id, turn_id,
                               ROW_NUMBER() OVER (
                                   PARTITION BY thread_id
                                   ORDER BY rollout_ordinal DESC, turn_id DESC
                               ) AS rank
                        FROM thread_turns
                    )
                    WHERE rank = 1
                )
                SELECT i.thread_id, i.turn_id, i.item_type, i.created_at_ms,
                       i.rollout_ordinal,
                       CASE
                           WHEN i.item_type IN ('commandExecution', 'mcpToolCall')
                           THEN json_remove(
                               i.item_json,
                               '$.aggregatedOutput', '$.output', '$.result'
                           )
                           ELSE i.item_json
                       END AS item_json
                FROM thread_items AS i
                INNER JOIN latest
                  ON latest.thread_id = i.thread_id
                 AND latest.turn_id = i.turn_id
                WHERE i.item_type IN (
                    'agentMessage', 'fileChange', 'commandExecution',
                    'mcpToolCall', 'plan'
                )
                ORDER BY i.thread_id, i.rollout_ordinal, i.created_at_ms
                """
            ).fetchall()

        turns = {str(row["thread_id"]): dict(row) for row in turn_rows}
        items: dict[str, list[dict[str, Any]]] = defaultdict(list)
        malformed_items = 0
        for row in item_rows:
            decoded = _safe_json(row["item_json"])
            if not decoded:
                malformed_items += 1
            items[str(row["thread_id"])].append(
                {
                    "type": str(row["item_type"]),
                    "created_at_ms": _milliseconds(row["created_at_ms"]) or 0,
                    "ordinal": int(row["rollout_ordinal"]),
                    "value": decoded,
                }
            )

        tasks = [
            self._normalize_task(dict(row), turns.get(str(row["id"])), items[str(row["id"])], generated_at)
            for row in thread_rows
        ]
        priority = {
            "waiting": 0,
            "running": 1,
            "failed": 2,
            "completed": 3,
            "interrupted": 4,
            "idle": 5,
        }
        tasks.sort(key=lambda task: (priority[task["status"]], -task["updated_at"]))
        summary = {key: 0 for key in priority}
        for task in tasks:
            summary[task["status"]] += 1
        return {
            "version": 1,
            "generated_at": generated_at,
            "freshness_target_ms": 1000,
            "summary": summary,
            "tasks": tasks,
            "health": {
                "status": "ok",
                "adapter": self.adapter_version,
                "plugin_version": PLUGIN_VERSION,
                "malformed_items": malformed_items,
                "stale": False,
            },
        }

    def _normalize_task(
        self,
        thread: dict[str, Any],
        turn: dict[str, Any] | None,
        items: list[dict[str, Any]],
        now_ms: int,
    ) -> dict[str, Any]:
        title = (
            _text(thread.get("name"), 100)
            or _text(thread.get("title"), 100)
            or _text(thread.get("preview"), 100)
            or _text(thread.get("first_user_message"), 100)
            or "Untitled task"
        )
        cwd = str(thread.get("cwd") or "")
        created_at = _milliseconds(thread.get("created_at_ms")) or 0
        updated_at = _milliseconds(thread.get("updated_at_ms")) or created_at
        latest_item_at = max((item["created_at_ms"] for item in items), default=0)
        updated_at = max(updated_at, latest_item_at)

        status = "idle"
        turn_status = str(turn.get("status") if turn else "")
        started_at = _milliseconds(turn.get("started_at") if turn else None)
        completed_at = _milliseconds(turn.get("completed_at") if turn else None)
        activity_at = max(updated_at, started_at or 0, latest_item_at)
        waiting = any(_waiting_item(item["value"]) for item in items)
        if waiting and turn_status == "inProgress":
            status = "waiting"
        elif turn_status == "failed":
            status = "failed"
        elif turn_status == "inProgress" and now_ms - activity_at <= ACTIVE_STALE_MS:
            status = "running"
        elif turn_status == "interrupted":
            status = "interrupted"
        elif turn_status == "completed" and now_ms - max(completed_at or 0, updated_at) <= RECENT_COMPLETED_MS:
            status = "completed"

        commentary = ""
        plan_step = ""
        active_action = ""
        changed_paths: set[str] = set()
        for item in items:
            item_type = item["type"]
            value = item["value"]
            if item_type == "agentMessage" and value.get("phase") == "commentary":
                candidate = _text(value.get("text"), 240)
                if candidate:
                    commentary = candidate
            elif item_type == "plan":
                candidate = _plan_step(value)
                if candidate:
                    plan_step = candidate
            elif item_type in {"commandExecution", "mcpToolCall"}:
                candidate = _active_action(item_type, value)
                if candidate:
                    active_action = candidate
            elif item_type == "fileChange":
                changes = value.get("changes")
                if isinstance(changes, list):
                    for change in changes:
                        if isinstance(change, dict) and isinstance(change.get("path"), str):
                            changed_paths.add(change["path"])

        current_step = plan_step or active_action or commentary
        if not current_step:
            current_step = {
                "waiting": "Waiting for confirmation",
                "running": "Codex is working",
                "failed": "The latest run failed",
                "completed": "Task completed",
                "interrupted": "Task interrupted",
                "idle": "No active run",
            }[status]

        duration = 0
        if turn:
            stored_duration = turn.get("duration_ms")
            if stored_duration is not None:
                try:
                    duration = max(0, int(stored_duration))
                except (TypeError, ValueError):
                    duration = 0
            elif started_at:
                end = now_ms if status in {"running", "waiting"} else completed_at or updated_at
                duration = max(0, end - started_at)

        task_id = str(thread["id"])
        return {
            "id": task_id,
            "title": title,
            "project": _project_name(cwd),
            "path_hint": _path_hint(cwd),
            "status": status,
            "current_step": current_step,
            "latest_progress": commentary,
            "turn_started_at": started_at,
            "duration_ms": duration,
            "changed_file_count": len(changed_paths),
            "updated_at": updated_at,
            "created_at": created_at,
            "stale": False,
            "deep_link": f"codex://threads/{quote(task_id, safe='-_')}",
        }
