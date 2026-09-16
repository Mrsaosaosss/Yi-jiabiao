# Codex Notch Island HUD Redesign

**Date:** 2026-09-16  
**Status:** Approved in chat; pending written-spec review  
**Plugin:** `codex-progress-dashboard`

## 1. Purpose

Replace the current floating notch panel with a native macOS island that appears to grow directly out of the MacBook notch. The redesign preserves the existing read-only observer, task ordering, browser dashboard, and deep links while improving the HUD's geometry, interaction model, and visual hierarchy.

The implementation is informed by `ericjypark/codex-island` but will be an original AppKit implementation. Any reused MIT-licensed code or materially adapted algorithm will retain attribution.

## 2. Scope

### In scope

- A fixed transparent top-level panel containing a smaller animated island surface.
- Compact, peek, and expanded presentation states.
- Physical-notch measurement that works when macOS display scaling changes the safe-area values.
- Pointer pass-through outside the visible island.
- Three-task expanded view using the existing rule: running or waiting tasks first, then the most recently requested tasks.
- Native reduced-motion and reduced-transparency behavior.
- Non-notch and external-display fallback.
- Automated tests for pure geometry, state transitions, hit testing, and task presentation.

### Out of scope

- Changes to the Python observer, SSE protocol, database access, browser dashboard, task mutation, or task ordering contract.
- Notifications, sounds, remote monitoring, analytics history, or new preferences.
- A SwiftUI rewrite. The current Objective-C/AppKit toolchain remains the supported implementation path for this iteration.
- Pixel-for-pixel reproduction of Codex Island.

## 3. Chosen architecture

The current `main.m` combines data transport, presentation selection, drawing, interaction, and window placement. The redesign separates the native HUD into focused Objective-C/AppKit units while retaining `DashboardModel` as the observer client.

- **`HUDGeometry`** computes notch metrics, panel frame, and visible island frames from screen measurements and presentation state. It contains no AppKit window lifecycle behavior.
- **`HUDPresentationModel`** maps the live dashboard snapshot to compact, peek, and expanded display values. It consumes the existing already-sorted `tasks` array and never reimplements server-side ordering.
- **`HUDIslandView`** draws the black island, status indicators, labels, separators, and task rows. It exposes the exact visible shape for hit testing.
- **`HUDInteractionController`** owns hover, click, pointer tracking, delayed collapse, and reduced-motion-aware state transitions.
- **`HUDWindowController`** owns the fixed transparent panel, screen selection, click-through behavior, space/full-screen behavior, and menu-bar fallback.
- **`DashboardModel`** continues to own runtime discovery, SSE connection, duration updates, dashboard opening, task deep links, and login startup.

The build script will compile all Objective-C sources in `macos/Sources` into the existing application bundle. No third-party runtime dependency is added.

## 4. Window and notch geometry

### 4.1 Fixed transparent panel

On a notched display, the application uses one borderless non-activating panel with a fixed logical size of `900 × 360` points. The panel is horizontally centered on the selected display and its top edge is pinned to `screen.frame.maxY`.

Only the island inside the panel changes size. Keeping the window fixed prevents window-frame jumps and lets the island morph smoothly around the physical notch.

The panel remains transparent outside the island. It ignores mouse events when the pointer is outside the current visible island path and accepts events only when the pointer enters that path.

### 4.2 Notch measurement

The notch height is derived from both menu-bar geometry and safe-area geometry:

1. `menuBarDelta = screen.frame.maxY - screen.visibleFrame.maxY - 1`
2. `safeTop = screen.safeAreaInsets.top`
3. `notchHeight = max(menuBarDelta, safeTop)`, clamped to a practical range for the selected display

This avoids treating `safeAreaInsets.top == 0` as proof that no notch exists when the display is configured to scale below the camera housing.

When both auxiliary top areas are available, physical notch width is:

`screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`

The compact island is never narrower than physical notch width plus 76 points on each side, subject to display width. This gives enough room for status/count on the left and the lead timer on the right while keeping the camera area visually centered.

### 4.3 Display choice and fallback

The controller prefers the built-in screen when it exposes notch geometry. It re-evaluates screen selection on display configuration changes.

If no notched screen is available, the island is placed at the top center of the active screen below the menu bar. A menu-bar item remains available as the reliable fallback and entry point. On a supported built-in notched screen, the menu-bar status item does not duplicate the live count; it provides only fallback actions when needed.

## 5. Presentation states

### 5.1 Compact

Compact is the resting state. The software island joins the physical notch with a flat top and continuous rounded lower corners.

- Left: overall status dot and `Codex <active-count>`.
- Right: elapsed time for the first displayed task.
- No task title or secondary text.
- Neutral coloring when no task is active, green/blue when running, amber when waiting, red when failed, and gray when disconnected.

### 5.2 Peek

Moving the pointer into the compact island expands it horizontally without meaningfully increasing its height.

- Left: active-count summary.
- Center/right: first task title and latest current-step text.
- Far right: elapsed time.
- Content is a single concise line and truncates safely.

The pointer leaving the visible island schedules a short collapse delay so small cursor movements across the camera cutout do not cause flicker.

### 5.3 Expanded

Clicking compact or peek opens the expanded state. The island grows downward while its top remains pinned to the notch.

- Header: `Codex 任务`, live/disconnected indicator, and active count.
- Exactly up to three rows from `DashboardModel.priorityTasks`.
- Each row shows status dot, title, current step, elapsed time, and changed-file count.
- Rows use spacing and separators rather than nested cards.
- Clicking a row opens the existing `codex://threads/<id>` deep link.
- Footer actions retain `查看全部`, login-startup toggle, and `退出`.

Clicking outside the island or pressing Escape collapses it. Hover alone does not collapse an explicitly opened expanded state.

## 6. State machine

The interaction state is one of `compact`, `peek`, or `expanded`.

- `compact → peek`: pointer enters the visible compact island.
- `peek → compact`: pointer exits and remains outside through the collapse delay.
- `compact/peek → expanded`: primary click inside the island.
- `expanded → compact`: outside click, Escape, or an explicit close action.
- Any state remains visually stable when a snapshot update arrives.

State changes first animate the island shape. Content appears after a short staged delay so text does not clip during the morph. With Reduce Motion enabled, geometry and content change without spring animation or staged delay.

## 7. Shape and visual treatment

- The island top edge is flat and contiguous with the display edge/camera housing.
- Bottom corners use a continuous, squircle-like curve rather than a standard rounded rectangle.
- Fill is near-black and mostly opaque. A subtle one-pixel rim and restrained shadow separate it from dark wallpaper.
- Expanded content may use a small amount of material translucency unless Reduce Transparency is enabled.
- Typography uses system fonts and monospaced digits for timers.
- The palette is limited to white, cool gray, black, and status accents.
- The HUD does not draw a window border, detached pill, duplicate menu-bar badge, or decorative glow.

## 8. Data flow and ordering

The observer remains the single source of truth:

`Codex databases → Python read-only observer → SSE snapshot → DashboardModel → HUDPresentationModel → HUDIslandView`

The server continues to sort tasks with running/waiting first, followed by the most recently requested tasks. The HUD takes the first three items exactly as delivered. It must not filter out completed or idle tasks when those tasks are needed to fill the three visible positions.

Duration remains locally live-updated once per second for running or waiting tasks. Changed-file count is read from the normalized snapshot and displayed only in expanded rows.

## 9. Error and lifecycle behavior

- On SSE disconnect, the last snapshot stays visible with a disconnected indicator and the existing reconnect behavior continues.
- If the observer runtime descriptor is unavailable, the HUD retains its current service-start fallback.
- If notch geometry cannot be trusted, the application uses the non-notch top-center/menu-bar fallback instead of guessing.
- Full-screen handling preserves the existing behavior: hide the resting island when another application occupies the full display and restore it when appropriate.
- Screen changes recompute geometry without restarting the observer or losing the snapshot.

## 10. Testing and verification

### Automated

- Geometry tests for physical-notch width, menu-bar-derived height, safe-area fallback, scaled-below-notch mode, non-notch displays, and panel anchoring.
- State-machine tests for hover, delayed exit, click expansion, outside click, Escape, and snapshot updates.
- Hit-testing tests proving transparent regions do not capture input.
- Presentation tests proving the first three already-sorted tasks are used and file counts appear only in expanded rows.
- Existing Python observer and browser tests remain unchanged and must continue to pass.

### Manual

- Verify compact, peek, and expanded states on the built-in notched display.
- Confirm there is no gap between physical notch and software island.
- Confirm the desktop and menu bar remain clickable outside the visible island.
- Confirm task rows open the correct Codex task.
- Confirm active-first/recent-fill ordering against live local tasks.
- Confirm dark wallpaper, light wallpaper, Reduce Motion, Reduce Transparency, display scaling, external display, and full-screen behavior.
- Build an arm64 application, verify ad-hoc signing, run the plugin validator, reinstall through the personal marketplace, and visually inspect the installed build.

## 11. Acceptance criteria

1. On the built-in MacBook display, the compact surface visually joins the physical notch with no vertical gap.
2. Hover produces a stable horizontal peek; clicking produces a downward expanded view; both preserve the top anchor.
3. Transparent panel regions never block ordinary desktop or menu-bar input.
4. Expanded view shows up to three tasks using running/waiting first and recent-request fill, including elapsed time and changed-file count.
5. Task selection, observer connectivity, browser dashboard, and deep links retain their current behavior.
6. Non-notch/external displays have a usable fallback.
7. Reduce Motion and Reduce Transparency are respected.
8. All automated tests, native build checks, signing verification, and plugin validation pass.

## 12. Attribution

The design references the public MIT-licensed `ericjypark/codex-island` project for its fixed transparent panel strategy, notch measurement considerations, and shape-first animation sequencing. The implementation will remain purpose-built for this plugin. If code is directly adapted rather than independently reimplemented, the repository's MIT license and copyright notice will be included with the affected source.
