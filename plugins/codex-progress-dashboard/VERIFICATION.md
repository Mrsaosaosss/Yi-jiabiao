# Verification report

Verified on macOS on 2026-09-15.

- All 9 automated tests pass.
- Browser JavaScript syntax check passes.
- Native AppKit HUD builds as an arm64 application and passes ad-hoc code-signature verification.
- Plugin manifest and bundled skill both pass the Codex validators.
- The collector reads Codex databases in SQLite read-only and query-only modes; a database hash check confirms collection does not modify the source.
- Schema incompatibility fails closed with a visible health error.
- HTTP endpoints bind to `127.0.0.1`, require a random bootstrap token, and then use an HttpOnly, SameSite=Strict cookie.
- Browser dashboard and native HUD were exercised against live local data. The test source contained 262 user-visible, non-archived tasks after internal guardian and subagent threads were excluded; average snapshot collection time was about 26.5 ms.
- Browser console inspection reported no errors or warnings.
- The native HUD was checked in both collapsed and expanded states, including the full-dashboard link and login-start toggle.

The implementation intentionally does not expose task mutation controls, command output, reasoning traces, or a network-facing listener.
