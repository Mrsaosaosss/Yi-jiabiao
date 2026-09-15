from __future__ import annotations

import http.cookiejar
import json
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PLUGIN_ROOT / "server"))
sys.path.insert(0, str(PLUGIN_ROOT / "tests"))

from runtime import DashboardRuntime  # noqa: E402
from test_data_source import create_fixture  # noqa: E402


class DashboardRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.codex_home = root / "codex"
        self.codex_home.mkdir()
        create_fixture(self.codex_home)
        self.runtime = DashboardRuntime(
            PLUGIN_ROOT,
            self.codex_home,
            runtime_file=root / "runtime.json",
            refresh_interval=60,
        ).start()

    def tearDown(self) -> None:
        self.runtime.stop()
        self.temp.cleanup()

    def test_rejects_unauthenticated_requests(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as raised:
            urllib.request.urlopen(f"{self.runtime.base_url}/api/snapshot", timeout=2)
        self.assertEqual(raised.exception.code, 401)

    def test_bootstrap_sets_cookie_and_security_headers(self) -> None:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        page = opener.open(self.runtime.bootstrap_url, timeout=2)
        self.assertEqual(page.status, 200)
        self.assertEqual(page.geturl(), f"{self.runtime.base_url}/")
        self.assertIn("default-src 'self'", page.headers["Content-Security-Policy"])
        snapshot_response = opener.open(f"{self.runtime.base_url}/api/snapshot", timeout=2)
        snapshot = json.load(snapshot_response)
        self.assertEqual(snapshot["health"]["status"], "ok")
        self.assertEqual(len(snapshot["tasks"]), 5)

    def test_event_stream_sends_snapshot(self) -> None:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        opener.open(self.runtime.bootstrap_url, timeout=2).close()
        response = opener.open(f"{self.runtime.base_url}/events", timeout=2)
        lines = []
        for _ in range(4):
            lines.append(response.readline().decode("utf-8"))
            if lines[-1] == "\n":
                break
        response.close()
        self.assertTrue(any(line.startswith("event: snapshot") for line in lines))
        self.assertTrue(any(line.startswith("data: {") for line in lines))


if __name__ == "__main__":
    unittest.main()
