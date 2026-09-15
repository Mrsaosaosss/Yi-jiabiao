# Codex Progress Dashboard Design

**Date:** 2026-09-15  
**Status:** Approved in chat; pending written-spec review  
**Plugin name:** `codex-progress-dashboard`

## 1. Purpose

Build a small personal Codex plugin for macOS that provides a continuously visible view of every local Codex task. The product has two synchronized surfaces:

1. A browser dashboard for the complete task list and filters.
2. A compact, Dynamic-Island-style HUD attached to the MacBook notch, with a menu-bar fallback.

The first release is read-only. It must never modify Codex task data, stop a task, answer an approval request, or send a message to a task. Selecting a task opens that task in Codex.

## 2. Goals and non-goals

### Goals

- Show all non-archived local Codex tasks, independent of project.
- Update visible progress within approximately one second of a local state change.
- Show task status, current step, latest progress, active duration, changed-file count, project, and last update time.
- Surface tasks that need the user's attention before ordinary active or completed tasks.
- Keep all processing and data on the local machine.
- Provide a lightweight installation with no OpenAI API key and no third-party runtime packages.
- Continue to function when the Mac has no notch or is using an external display.

### Non-goals for the first release

- Sending prompts, approvals, interruptions, or other mutations to Codex tasks.
- Monitoring Codex tasks running only on another computer or in an inaccessible cloud environment.
- Synchronizing task data between machines.
- Storing a separate long-term analytics history.
- Replacing the Codex task detail view.

## 3. Chosen approach

The plugin will use a local read-only observer backed by Codex's local state and thread-history SQLite databases. It will inspect the databases in read-only mode and will never run migrations or issue write statements. A compatibility adapter isolates all Codex schema knowledge from the rest of the application.

This approach is chosen because a separately launched Codex App Server cannot reliably subscribe to every task already owned by the desktop app. The official App Server event model remains the preferred future data source when a shared desktop subscription becomes available. The observer's normalized interface is intentionally source-agnostic so an App Server adapter can replace or supplement the SQLite adapter later.

The observer will use a sub-second internal refresh interval, coalesce duplicate snapshots, and publish changed snapshots to local clients over Server-Sent Events (SSE). The user-facing freshness target is one second rather than a claim of zero-latency delivery.

## 4. System architecture

### 4.1 Plugin package

The personal plugin contains:

- A valid `.codex-plugin/plugin.json` manifest.
- An MCP server declaration used by Codex to start and inspect the dashboard.
- A skill that teaches Codex when and how to open the dashboard.
- A Python standard-library local observer and HTTP/SSE server.
- A Swift/AppKit macOS HUD application and its source.
- Scripts for building, launching, stopping, and validating the local components.
- User-facing installation and troubleshooting documentation.

The plugin exposes a small MCP tool surface:

- `open_progress_dashboard`: ensure the observer is running and return/open the browser dashboard URL.
- `show_progress_hud`: ensure the observer is running and launch or focus the notch HUD.
- `progress_dashboard_status`: return health, connection, schema-compatibility, and client-count information.

No MCP tool mutates Codex task state.

### 4.2 Observer service

The observer is a single local Python process using only the standard library. It owns:

- Read-only SQLite connections.
- Codex schema/version detection.
- Snapshot normalization and metric calculation.
- A loopback-only HTTP server.
- SSE client fan-out.
- Static browser assets.
- A small runtime descriptor for HUD discovery.

The service listens only on `127.0.0.1` using an available ephemeral port. It creates a random per-run capability token. The token is accepted only by a bootstrap URL, which sets a user-only, `HttpOnly`, `SameSite=Strict` session cookie and redirects to a clean URL; the page and stream then require that cookie. It sends a restrictive Content Security Policy, disables cross-origin access, and exposes no write endpoints.

### 4.3 Browser dashboard

The dashboard is a framework-free HTML/CSS/JavaScript single page served by the observer. It maintains one SSE connection and updates only changed task rows. If the stream disconnects, it reconnects with bounded exponential backoff and marks the current snapshot as stale until a fresh snapshot arrives.

### 4.4 macOS notch HUD

The HUD is a small Swift/AppKit menu-bar application. On a built-in display with a notch, it places a non-activating panel immediately below the notch. On unsupported or external displays, it presents the same compact content from a normal menu-bar status item.

The collapsed HUD shows:

- Overall state color.
- Number of active tasks.
- Elapsed time for the highest-priority active task.

Hovering or clicking expands it downward to show at most three priority tasks, each with status, title, current step, and elapsed time. It never steals keyboard focus. It hides its expanded panel while another application is in full-screen mode and retains a menu-bar entry for opening the full dashboard.

The HUD reads the observer's runtime descriptor, connects to the same SSE stream as the browser, and contains no Codex parsing logic.

## 5. Data sources and compatibility

### 5.1 Sources

The initial compatibility adapter reads:

- The Codex state database for task identity, title, project/current directory, archive state, and recency.
- The Codex thread-history database for turns, item types, timestamps, progress messages, command executions, and file-change records.
- SQLite WAL updates through ordinary read-only queries; the plugin does not parse or mutate WAL files directly.

Database locations are discovered under the active Codex home directory and are not hard-coded to one username. The implementation may inspect known filenames to select a supported schema generation, but it must open only existing files and must not create empty databases accidentally.

### 5.2 Compatibility boundary

All database queries and item decoding live behind a `CodexDataSource` interface. The remainder of the service consumes only normalized task snapshots.

At startup the adapter validates required tables and columns. Unsupported structures produce a clear `schema_incompatible` health state. The service then keeps serving its diagnostics page but stops task parsing. It never attempts a migration, repair, or fallback guess.

## 6. Normalized task model

Each task snapshot contains:

- `id`: stable Codex thread identifier.
- `title`: user-facing task name or safe preview fallback.
- `project`: project name or shortened working-directory fallback.
- `path_hint`: at most the last two path components by default.
- `status`: `waiting`, `failed`, `running`, `completed`, `interrupted`, or `idle`.
- `current_step`: short derived description of current work.
- `latest_progress`: latest user-visible commentary text, never private reasoning content.
- `turn_started_at`: start time of the active or most recent turn.
- `duration_ms`: live elapsed time for an active turn or fixed final duration.
- `changed_file_count`: number of distinct changed paths in the current or most recent turn.
- `updated_at`: latest meaningful update timestamp.
- `stale`: whether the snapshot is older than the freshness threshold.
- `deep_link`: `codex://threads/<thread-id>`.

### 6.1 Status rules

Status precedence is:

1. A pending approval or user-input item becomes `waiting`.
2. A failed latest turn becomes `failed`.
3. An in-progress latest turn becomes `running`.
4. An interrupted latest turn becomes `interrupted`.
5. A recently completed latest turn becomes `completed`.
6. A task with no active or recent turn becomes `idle`.

### 6.2 Current step and progress rules

`current_step` is chosen in this order:

1. The in-progress entry from the most recent plan update.
2. The active command or tool action, expressed with a short safe label.
3. The latest user-visible commentary summary.
4. A status-specific fallback such as “Waiting for confirmation.”

`latest_progress` uses the latest agent message whose phase is commentary. Raw reasoning items and hidden internal fields are never displayed.

### 6.3 Duration and file-count rules

For an active turn, duration is current time minus its start time. For a terminal turn, duration uses its stored duration or the difference between start and completion timestamps. Changed files are counted as distinct normalized paths from file-change items belonging to that turn.

## 7. User interface

### 7.1 Full dashboard

The single-page layout contains:

- A header with observer connection/freshness state.
- Summary counts for waiting, running, failed, and recently completed tasks.
- Status and project filters plus text search.
- A primary task list ordered by attention priority and recency.
- A “Recently completed” section limited to the last 24 hours by default.

Each row shows title, project, status, current step, latest progress, duration, changed-file count, and last update time. Clicking a task follows its Codex deep link. The page supports light and dark appearances, reduced motion, keyboard navigation, and narrow widths.

Default ordering is waiting, running, failed, recently completed, interrupted, then idle. Within a group, the most recently updated task appears first.

### 7.2 HUD states

- **Healthy/idle:** neutral appearance and zero active count.
- **Running:** blue accent with live elapsed time.
- **Waiting:** amber accent and highest display priority.
- **Failed:** red accent, below active running tasks but above completed or idle tasks.
- **Disconnected/stale:** muted appearance with an explicit connection indicator.

Animations are subtle and disabled when Reduce Motion is enabled. The application does not play sounds or send macOS notifications in the first release.

## 8. Privacy and security

- Codex databases are opened read-only.
- The observer binds only to IPv4 loopback.
- Every run uses a cryptographically random capability token that is exchanged for a strict local session cookie and removed from the visible URL.
- No CORS permission is granted to other origins.
- Responses use a restrictive Content Security Policy and `nosniff` headers.
- No task content is logged by default.
- Paths are shortened in the default UI.
- No data is uploaded and no OpenAI API key is requested.
- Runtime files belong to the plugin, contain no task content, and use user-only permissions.

## 9. Lifecycle and settings

Asking Codex to open the dashboard starts the MCP-backed observer if needed and returns the local URL. Asking to show the HUD also launches or focuses the macOS application. Both clients share the same observer process.

The HUD offers a setting to start at login. It is disabled by default. Enabling it creates a user-scoped launch item only after the user explicitly changes that setting; disabling it removes that item. This setting does not alter Codex configuration.

The observer exits after a configurable idle period when it has no browser, HUD, or MCP clients. The default idle timeout is ten minutes. The HUD reconnects and can restart the observer through its bundled launcher when login startup is enabled.

## 10. Error handling

- **Database temporarily busy:** keep the last good snapshot, mark it stale, and retry with bounded backoff.
- **Missing Codex data:** show an empty-state explanation and the discovered Codex home path.
- **Unsupported schema:** stop parsing, show installed Codex and adapter versions, and direct the user to update the plugin.
- **Malformed item data:** skip the individual item, record a content-free diagnostic counter, and continue the task snapshot.
- **SSE disconnect:** reconnect automatically; keep stale data visible.
- **HUD cannot position at the notch:** fall back to the menu-bar presentation.
- **Codex deep link fails:** retain a copyable task identifier and show a non-blocking error.

## 11. Testing and verification

### Automated tests

- Adapter tests against temporary SQLite fixtures for each supported schema shape.
- Status-precedence tests, including waiting versus failed/running combinations.
- Current-step selection and commentary privacy tests.
- Duration and distinct-file-count tests.
- HTTP security-header and capability-token tests.
- SSE snapshot, deduplication, reconnect, and stale-state tests.
- Static UI behavior tests for filtering, ordering, and rendering.
- Swift tests for HUD state selection and fallback layout calculations.

### Integration and manual verification

- Run against a disposable fixture before reading the user's real Codex databases.
- Verify the observer opens the real databases with read-only URI flags.
- Start simultaneous Codex tasks in different projects and confirm updates appear within one second.
- Exercise running, waiting, failed, interrupted, and completed states.
- Confirm file edits are counted once per distinct path.
- Confirm raw reasoning content never appears.
- Verify light/dark mode, Reduce Motion, built-in notch placement, external display fallback, full-screen hiding, and Codex deep links.
- Validate the plugin manifest and personal marketplace entry with the plugin-creator validation tools.

## 12. Packaging and deliverables

The implementation will produce:

- A marketplace-backed personal plugin named `codex-progress-dashboard`.
- A locally built, ad-hoc-signed macOS HUD `.app` suitable for this machine.
- Source for the observer, browser UI, and HUD.
- Automated tests and a verification report.
- Installation, update, startup, privacy, and troubleshooting instructions.

The personal marketplace entry uses the standard `AVAILABLE` installation policy, `ON_INSTALL` authentication policy, and `Productivity` category. The plugin itself requires no external account authentication.

## 13. Acceptance criteria

The first release is complete when:

1. Installing the personal plugin makes its skill and MCP tools available in a new Codex task.
2. “Open the Codex progress dashboard” opens a loopback browser dashboard without requesting an API key.
3. Every non-archived local Codex task appears, regardless of project.
4. Changes to status, current step, commentary, duration, and changed-file count are visible within approximately one second.
5. The notch HUD shows the highest-priority state and expands to three tasks; non-notch displays receive the menu-bar fallback.
6. Clicking a task opens `codex://threads/<thread-id>`.
7. The observer performs no writes to Codex databases and sends no task data over the network.
8. Unsupported database schemas fail visibly and safely.
9. Automated tests and plugin validation pass.

## 14. Future extension points

- Replace or supplement SQLite observation with a shared Codex App Server event subscription when available.
- Add optional native notifications, only with explicit user opt-in.
- Add remote/cloud task monitoring through a documented authenticated interface.
- Add read-only historical charts without changing the normalized task contract.
