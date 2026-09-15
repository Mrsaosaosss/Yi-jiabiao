from __future__ import annotations

import sys
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PLUGIN_ROOT / "server"))

import mcp_server  # noqa: E402


class MCPServerTests(unittest.TestCase):
    def test_initialize_and_tool_discovery(self) -> None:
        initialized = mcp_server.handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18"},
            }
        )
        self.assertEqual(initialized["result"]["protocolVersion"], "2025-06-18")
        listed = mcp_server.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        names = {tool["name"] for tool in listed["result"]["tools"]}
        self.assertEqual(
            names,
            {"open_progress_dashboard", "show_progress_hud", "progress_dashboard_status"},
        )

    def test_unknown_tool_is_a_tool_error(self) -> None:
        response = mcp_server.handle(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "mutate_task", "arguments": {}},
            }
        )
        self.assertTrue(response["result"]["isError"])
        self.assertEqual(response["result"]["structuredContent"]["code"], "unknown_tool")


if __name__ == "__main__":
    unittest.main()
