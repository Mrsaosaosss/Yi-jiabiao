# Verification report

Verified on macOS on 2026-09-16.

- All 10 automated tests pass, including active-first and recent-request fallback ordering.
- Browser JavaScript syntax check passes.
- Native AppKit HUD builds as an arm64 application and passes ad-hoc code-signature verification.
- Plugin manifest and bundled skill both pass the Codex validators.
- The collector reads Codex databases in SQLite read-only and query-only modes; a database hash check confirms collection does not modify the source.
- Schema incompatibility fails closed with a visible health error.
- HTTP endpoints bind to `127.0.0.1`, require a random bootstrap token, and then use an HttpOnly, SameSite=Strict cookie.
- Browser dashboard and native HUD were exercised against live local data. The test source contained 262 user-visible, non-archived tasks after internal guardian and subagent threads were excluded; average snapshot collection time was about 26.5 ms.
- Browser console inspection reported no errors or warnings.
- The native HUD was checked in compact, hover-peek, and expanded states. On the built-in notched display it is anchored to the screen top, merges visually with the notch, and expands downward from that anchor.
- Live data confirmed that running tasks lead the HUD and the remaining slot is filled by the most recently requested non-running task.

## Notch island redesign

- The built-in display reports a physical notch of `179 × 32` points. The compact island is `347 × 32`: the center matches the notch and each side has an 84-point information wing.
- Native core tests cover exact physical-notch height, auxiliary-area notch width, fixed top anchoring, the 28-point hover extension, all three presentation states, state transitions, server-order preservation, file-count formatting, and transparent-corner hit testing.
- The HUD now uses a fixed transparent `900 × 360` panel. Only the internal island surface animates, so the physical-notch anchor remains stable.
- The compact surface begins at `y = 0`, has no top inset or top rim, and never extends below the menu-bar band. This removes the top seam and avoids covering browser or app content at rest.
- Compact and peek surfaces are fully opaque; expanded detail uses only restrained translucency and respects Reduce Transparency.
- Screen-space pointer routing makes every pixel outside the current island shape click-through.
- Real AppKit renders of compact, peek, and expanded states were inspected for clipping, separator alignment, timer columns, file counts, and Chinese typography.

The implementation intentionally does not expose task mutation controls, command output, reasoning traces, or a network-facing listener.
