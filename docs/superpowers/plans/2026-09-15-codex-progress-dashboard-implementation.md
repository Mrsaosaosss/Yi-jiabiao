# Codex Progress Dashboard Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-15-codex-progress-dashboard-design.md`  
**Source plugin:** `plugins/codex-progress-dashboard`  
**Installed plugin:** `~/plugins/codex-progress-dashboard`

## Phase 1: Scaffold and contracts

1. Scaffold a validation-ready plugin with skills, scripts, assets, and MCP configuration.
2. Replace scaffold metadata with the approved product metadata.
3. Define the normalized task/health snapshot contract and fixture databases.
4. Add failing tests for schema detection, status precedence, progress privacy, duration, and file counts.

## Phase 2: Read-only observer

1. Implement Codex-home and database discovery without creating missing databases.
2. Open SQLite through immutable read-only URI connections suitable for live WAL-backed reads.
3. Implement schema validation and a versioned data-source adapter.
4. Normalize tasks, latest turns, commentary, active actions, and file-change items.
5. Add snapshot hashing, stale-state handling, and bounded retry behavior.
6. Pass adapter and service-model tests against fixtures, then run a content-safe smoke test against real local metadata.

## Phase 3: Local dashboard service

1. Implement a loopback-only HTTP server with a random port and capability bootstrap.
2. Exchange the bootstrap capability for a strict local session cookie and redirect to a clean URL.
3. Serve JSON health/snapshot endpoints and an authenticated SSE stream; expose no mutation endpoints.
4. Add framework-free responsive dashboard assets with filters, ordering, deep links, reconnect, stale state, dark mode, and reduced motion.
5. Add security-header, authorization, SSE, and static-asset tests.

## Phase 4: Plugin invocation

1. Implement a standard-library MCP stdio server with dashboard-open, HUD-show, and health tools.
2. Add a concise automatically discoverable skill for opening or diagnosing the dashboard.
3. Add launcher/build scripts and user documentation.
4. Validate the skill and plugin manifest.

## Phase 5: macOS HUD

1. Implement the Swift/AppKit status-bar application and observer client.
2. Implement notch detection, collapsed and expanded states, priority selection, full-screen behavior, and menu-bar fallback.
3. Add dashboard and Codex task deep links.
4. Add login-startup preference with explicit opt-in.
5. Build an application bundle, ad-hoc sign it, and run non-interactive smoke checks.

## Phase 6: Integration, installation, and verification

1. Run all automated tests and static validation.
2. Exercise the observer against current Codex tasks and verify read-only access.
3. Copy the verified source bundle to the personal plugin directory.
4. Create or update the personal marketplace entry using the plugin-creator helper.
5. Install the plugin through Codex, verify it is listed, and record any new-task activation requirement.
6. Commit source, tests, documentation, and generated application artifacts needed for local use.
