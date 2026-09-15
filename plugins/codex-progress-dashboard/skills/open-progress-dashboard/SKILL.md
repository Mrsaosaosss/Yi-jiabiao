---
name: open-progress-dashboard
description: Open or diagnose the private local dashboard and macOS notch HUD that monitor all Codex task progress. Use when the user asks to view, show, monitor, or troubleshoot the Codex progress dashboard or HUD. Do not use for changing, interrupting, or messaging tasks.
---

# Codex Progress Dashboard

Use the bundled `codex-progress-dashboard` MCP tools. Keep the workflow read-only.

- For a full task view, call `open_progress_dashboard`.
- For the Mac notch companion, call `show_progress_hud`.
- For connection, schema, or startup problems, call `progress_dashboard_status` before suggesting manual troubleshooting.

Tell the user when a browser or macOS app was opened. If a tool returns a local URL without opening it, provide that URL as a clickable link. Never infer permission to approve, interrupt, archive, rename, or send messages to tasks.
