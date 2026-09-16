from __future__ import annotations

import json
import hashlib
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PLUGIN_ROOT / "server"))

from data_source import CodexSQLiteDataSource, SchemaIncompatible  # noqa: E402


NOW_MS = 1_800_000_000_000


def create_fixture(root: Path) -> None:
    state = sqlite3.connect(root / "state_5.sqlite")
    state.execute(
        """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            first_user_message TEXT NOT NULL,
            name TEXT,
            archived INTEGER NOT NULL,
            recency_at_ms INTEGER NOT NULL,
            source TEXT NOT NULL,
            thread_source TEXT
        )
        """
    )
    for task_id, title, age_ms in (
        ("waiting-task", "Needs approval", 1_000),
        ("running-task", "Running task", 2_000),
        ("failed-task", "Failed task", 3_000),
        ("completed-task", "Completed task", 4_000),
        ("idle-task", "Old task", 200_000_000),
    ):
        timestamp = NOW_MS - age_ms
        state.execute(
            "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                task_id,
                f"/tmp/{task_id}.jsonl",
                timestamp - 10_000,
                timestamp,
                f"/Users/example/Projects/{task_id}",
                title,
                title,
                title,
                None,
                0,
                timestamp,
                "vscode",
                "user",
            ),
        )
    state.execute(
        "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            "internal-guardian",
            "/tmp/internal.jsonl",
            NOW_MS - 1_000,
            NOW_MS - 1_000,
            "/tmp/internal",
            "Internal guardian",
            "Internal guardian",
            "Internal guardian",
            None,
            0,
            NOW_MS - 1_000,
            '{"subagent":{"other":"guardian"}}',
            "guardian_review",
        ),
    )
    state.commit()
    state.close()

    history = sqlite3.connect(root / "thread_history_1.sqlite")
    history.executescript(
        """
        CREATE TABLE thread_turns (
            thread_id TEXT NOT NULL,
            turn_id TEXT NOT NULL,
            rollout_ordinal INTEGER NOT NULL,
            status TEXT NOT NULL,
            error_json TEXT,
            started_at INTEGER,
            completed_at INTEGER,
            duration_ms INTEGER,
            PRIMARY KEY (thread_id, turn_id)
        );
        CREATE TABLE thread_items (
            thread_id TEXT NOT NULL,
            turn_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            rollout_ordinal INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL,
            item_json TEXT NOT NULL,
            item_type TEXT NOT NULL,
            PRIMARY KEY (thread_id, turn_id, item_id)
        );
        """
    )
    turns = (
        ("waiting-task", "turn-w", 1, "inProgress", NOW_MS // 1000 - 12, None, None),
        ("running-task", "turn-r", 1, "inProgress", NOW_MS // 1000 - 20, None, None),
        ("failed-task", "turn-f", 1, "failed", NOW_MS // 1000 - 30, NOW_MS // 1000 - 3, 27_000),
        ("completed-task", "turn-c", 1, "completed", NOW_MS // 1000 - 40, NOW_MS // 1000 - 4, 36_000),
        ("idle-task", "turn-i", 1, "completed", NOW_MS // 1000 - 300_000, NOW_MS // 1000 - 200_000, 100_000_000),
    )
    history.executemany(
        "INSERT INTO thread_turns VALUES (?, ?, ?, ?, NULL, ?, ?, ?)", turns
    )

    def item(task: str, turn: str, index: int, kind: str, value: dict[str, object]) -> None:
        history.execute(
            "INSERT INTO thread_items VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                task,
                turn,
                f"item-{task}-{index}",
                index,
                NOW_MS - (10 - index) * 100,
                json.dumps(value),
                kind,
            ),
        )

    item("waiting-task", "turn-w", 1, "mcpToolCall", {"status": "waiting_on_approval"})
    item("waiting-task", "turn-w", 2, "agentMessage", {"phase": "commentary", "text": "Ready for approval"})
    item("running-task", "turn-r", 1, "agentMessage", {"phase": "commentary", "text": "Implementing the observer"})
    item("running-task", "turn-r", 2, "reasoning", {"text": "private reasoning"})
    item("running-task", "turn-r", 3, "plan", {"plan": [{"step": "Build live stream", "status": "inProgress"}]})
    item("running-task", "turn-r", 4, "fileChange", {"changes": [{"path": "/tmp/a.py"}, {"path": "/tmp/a.py"}, {"path": "/tmp/b.py"}]})
    history.commit()
    history.close()


class CodexSQLiteDataSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        create_fixture(self.root)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_normalizes_and_orders_tasks(self) -> None:
        snapshot = CodexSQLiteDataSource(self.root).collect(now_ms=NOW_MS)
        self.assertEqual(
            [task["status"] for task in snapshot["tasks"]],
            ["waiting", "running", "failed", "completed", "idle"],
        )
        self.assertEqual(snapshot["summary"]["running"], 1)
        self.assertEqual(snapshot["summary"]["completed"], 1)
        self.assertNotIn("internal-guardian", {task["id"] for task in snapshot["tasks"]})

    def test_current_step_progress_duration_and_file_count(self) -> None:
        snapshot = CodexSQLiteDataSource(self.root).collect(now_ms=NOW_MS)
        task = next(task for task in snapshot["tasks"] if task["id"] == "running-task")
        self.assertEqual(task["current_step"], "Build live stream")
        self.assertEqual(task["latest_progress"], "Implementing the observer")
        self.assertNotIn("private reasoning", json.dumps(task))
        self.assertEqual(task["duration_ms"], 20_000)
        self.assertEqual(task["changed_file_count"], 2)
        self.assertEqual(task["path_hint"], "Projects/running-task")
        self.assertEqual(task["deep_link"], "codex://threads/running-task")

    def test_active_tasks_lead_and_recent_requests_fill_remaining_slots(self) -> None:
        state = sqlite3.connect(self.root / "state_5.sqlite")
        state.execute(
            "UPDATE threads SET recency_at_ms = ? WHERE id = ?",
            (NOW_MS + 5_000, "idle-task"),
        )
        state.commit()
        state.close()

        snapshot = CodexSQLiteDataSource(self.root).collect(now_ms=NOW_MS)

        self.assertEqual(
            [task["id"] for task in snapshot["tasks"][:3]],
            ["waiting-task", "running-task", "idle-task"],
        )
        idle = next(task for task in snapshot["tasks"] if task["id"] == "idle-task")
        self.assertEqual(idle["recency_at"], NOW_MS + 5_000)

    def test_missing_required_column_fails_closed(self) -> None:
        broken = sqlite3.connect(self.root / "state_6.sqlite")
        broken.execute("CREATE TABLE threads (id TEXT PRIMARY KEY)")
        broken.commit()
        broken.close()
        with self.assertRaises(SchemaIncompatible):
            CodexSQLiteDataSource(self.root).collect(now_ms=NOW_MS)

    def test_collection_does_not_modify_codex_databases(self) -> None:
        paths = [self.root / "state_5.sqlite", self.root / "thread_history_1.sqlite"]
        before = [hashlib.sha256(path.read_bytes()).digest() for path in paths]
        CodexSQLiteDataSource(self.root).collect(now_ms=NOW_MS)
        after = [hashlib.sha256(path.read_bytes()).digest() for path in paths]
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
