# Codex Notch Island HUD Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-16-codex-island-hud-design.md`  
**Plugin:** `plugins/codex-progress-dashboard`

## Phase 1: Native test seams

1. Add a small native test target that compiles without launching the HUD application.
2. Add failing tests for notch height, physical notch width, fixed panel anchoring, compact/peek/expanded island frames, and state transitions.
3. Add a single script that builds and runs the native tests.

## Phase 2: Separate native responsibilities

1. Extract `DashboardModel` from the monolithic application entry point without changing its SSE, startup, deep-link, or ordering behavior.
2. Implement `HUDGeometry` as pure layout functions shared by the window controller and tests.
3. Implement `HUDPresentationModel` as the only snapshot-to-UI mapping layer.
4. Implement `HUDInteractionController` for compact, peek, expanded, delayed hover exit, click expansion, and explicit dismissal.
5. Implement `HUDIslandView` for shape, content, task-row hit testing, accessibility-aware animation, and file-count display.
6. Implement `HUDWindowController` for fixed panel placement, notched-display selection, pointer pass-through, outside-click dismissal, full-screen hiding, and menu-bar fallback.
7. Reduce `main.m` to application lifecycle wiring.

## Phase 3: Build and behavior validation

1. Update the build script to compile all native sources and the native test binary.
2. Run native tests, existing Python tests, JavaScript syntax checks, manifest validation, and signing verification.
3. Launch the workspace build against live local tasks and inspect compact, peek, and expanded states on the built-in display.
4. Verify transparent panel regions remain clickable and task rows open the existing deep links.
5. Update README and verification notes to describe the new interaction model.

## Phase 4: Personal plugin update

1. Read and validate the personal marketplace name.
2. Sync the verified workspace plugin into the personal plugin source.
3. Update the personal source cachebuster with the plugin helper.
4. Reinstall the plugin from the personal marketplace.
5. Copy the exact installed manifest version back to the workspace source and rerun validation.
6. Launch the installed HUD, confirm the installed binary and live view, and record the final verification result.
