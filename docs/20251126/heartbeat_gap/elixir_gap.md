# Elixir heartbeat gap vs Python

- **Path mismatch**: Elixir posts to `/api/v1/heartbeat`; real API (and Python) use `/api/v1/session_heartbeat`.
- **Behavior masking**: `SessionManager.send_heartbeat/3` drops session on 4xx silently; no warning on sustained failure. A 404 immediately removes the session from tracking.
- **Tests hide the bug**: All heartbeat tests stub `/api/v1/heartbeat` via Bypass; integration tests do the same. No test hits a live server path.
- **No warning threshold**: Unlike Python’s 2-minute warning, Elixir logs nothing on repeated failure; sessions simply vanish from the manager.
- **Consequence**: Sessions are not kept alive against the real service; the server may reclaim/expire sessions while clients think everything is fine.
