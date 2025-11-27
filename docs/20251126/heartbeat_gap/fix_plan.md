# Fix plan (do not apply yet)

1) **Correct path**: Point `Tinkex.API.Session.heartbeat/2` to `/api/v1/session_heartbeat`.
2) **Logging/alerting**: Add a warning after sustained failures (e.g., 2 minutes) instead of silent drops. Optionally keep the drop-on-4xx semantics if desired, but surface visibility.
3) **Tests**: Update Bypass stubs and integration tests to `/api/v1/session_heartbeat`; add a guard test that asserts `/api/v1/heartbeat` returns 404 against a live env (or via a probe script) to prevent regressions.
4) **Probe/diagnostic**: Keep a simple script (like `foo.exs`) to sanity-check both endpoints against a real server; wire into CI as an opt-in smoke test.
5) **Migration note**: Document the change in README and changelog; note that sessions will now stay alive as intended.
