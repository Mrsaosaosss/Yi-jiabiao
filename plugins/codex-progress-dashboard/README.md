# Codex Progress Dashboard

A local, read-only live view of all Codex tasks, with a browser dashboard and an optional macOS notch HUD.

Requires macOS 13 or newer and a local Codex desktop installation. Internal guardian/subagent implementation threads are omitted; every user-visible, non-archived local task remains available.

## Privacy

- Reads Codex's local state and thread-history databases in SQLite read-only mode.
- Listens only on `127.0.0.1`.
- Does not require an API key or send task data over the network.
- Never changes, interrupts, approves, archives, or messages a Codex task.

## Use

After installation, start a new Codex task and ask:

- “Open my Codex progress dashboard.”
- “Show the Codex progress HUD.”
- “Check the progress dashboard health.”

The HUD menu can enable login startup. That option is off by default.

On a Mac with a display notch, the collapsed HUD is anchored to the physical notch and extends from it like a compact status island. Running and waiting tasks are shown first; any remaining slots are filled by the most recently requested Codex tasks.

The full dashboard keeps active and recently completed work at the top. Historical idle and interrupted tasks remain available in the collapsed “Other tasks” section and through search or filters.

## Troubleshooting

- Ask Codex to “Check the progress dashboard health” for observer and schema diagnostics.
- If Codex was upgraded and the dashboard reports `schema_incompatible`, update this plugin before reopening it. The observer deliberately refuses to guess at unknown database structures.
- If the HUD cannot use a notched built-in display, it falls back to the menu-bar position automatically.
- If a task link cannot open Codex, copy its task ID from the dashboard and locate it in Codex search.

## Local development

Run Python tests:

```sh
python3 -m unittest discover -s tests -v
```

Build the macOS HUD:

```sh
./scripts/build_hud.sh
```

Run the dashboard without the plugin host:

```sh
python3 scripts/run_dashboard.py
```
