# Heartbeat fix specification

This consolidates the gap analysis into a concrete set of requirements to bring Elixir heartbeat behavior in line with the Python SDK and the actual API.

## Current state (observed)
- Tests: All heartbeat unit/integration tests stub `POST /api/v1/heartbeat` via Bypass; never exercise a real server. Wrong path passes locally.
- Runtime masking: `SessionManager.send_heartbeat/3` treats 4xx (including 404) as “drop session silently.” A 404 from `/api/v1/heartbeat` removes the session with no log.
- Purpose (Python): `InternalClientHolder._session_heartbeat` posts `/api/v1/session_heartbeat` every 10s; warns after 2 minutes of consecutive failures to keep sessions alive.
- Elixir path: `Tinkex.API.Session.heartbeat/2` posts `/api/v1/heartbeat` (404 on real API), so liveness is broken against production.
- Code/test locations: `lib/tinkex/api/session.ex`, `lib/tinkex/session_manager.ex`; tests in `test/tinkex/session_manager_test.exs`, `test/tinkex/api/session_test.exs`, integration tests all stub `/api/v1/heartbeat`.

## Requirements
1) **Endpoint alignment**
   - Change heartbeat POST path to `/api/v1/session_heartbeat` in `Tinkex.API.Session.heartbeat/2`.

2) **Logging/visibility**
   - Add a warning or diagnostic after sustained heartbeat failures (e.g., 2 minutes of consecutive failures), similar to Python’s `InternalClientHolder._session_heartbeat` behavior. Do not silently drop without visibility.
   - Decide drop-vs-retain semantics on 4xx: either drop but log, or keep retrying with a warning threshold; must be explicit.

3) **Tests**
   - Update all Bypass stubs and integration tests to `/api/v1/session_heartbeat`.
   - Add a regression test that would fail if the path is reverted (e.g., assert the requested path equals `/api/v1/session_heartbeat`).
   - Optional: add a smoke/probe test (opt-in) that asserts `/api/v1/session_heartbeat` returns 200 and `/api/v1/heartbeat` returns 404 against a real env (using a guard or tag to skip in CI without creds).

4) **Diagnostics/probe**
   - Keep or add a small script (like `foo.exs`) to manually verify both endpoints against a real server; document how to run it.

5) **Docs/communication**
   - Update README/CHANGELOG to note the corrected heartbeat path and behavior change.
   - Document the warning behavior and failure handling.

## Out of scope (for now)
- Adding retries to heartbeat beyond logging; Python uses `max_retries=0`, so keep parity unless product asks otherwise.

## Acceptance criteria
- Heartbeat requests hit `/api/v1/session_heartbeat` in Elixir.
- Sustained failures surface via logs/warnings; not silently dropped without visibility.
- Test suite stubs the correct path and would fail if the wrong path is used.
- Manual probe can demonstrate 200 on `/api/v1/session_heartbeat` and 404 on `/api/v1/heartbeat` when run against a real server.
