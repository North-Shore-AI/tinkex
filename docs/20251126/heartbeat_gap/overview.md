# Heartbeat integration overview (Python SDK)

Purpose: keep a session alive server-side; warn after prolonged failures. Implemented centrally in `InternalClientHolder` and the Service resource.

Key components
- `tinker/lib/internal_client_holder.py`
  - Starts a background heartbeat task when a session is created. Period = 10s, warning threshold = 120s.
  - Uses `client.service.session_heartbeat(session_id=..., max_retries=0, timeout=10)` (no retries) on the SESSION pool.
  - On exceptions: records last exception, continues loop; logs a warning if >120s since last success.
  - Session creation (`_create_session`) returns `(session_id, session_heartbeat_task)`; holder stores both and cancels the task on cleanup.
- `tinker/resources/service.py`
  - Exposes `session_heartbeat` → POST `/api/v1/session_heartbeat` with `SessionHeartbeatRequest`/`SessionHeartbeatResponse`.
- Types
  - `types/session_heartbeat_request.py` and `session_heartbeat_response.py` (type tag `session_heartbeat`).

Behavioral notes
- Heartbeat is automatic for all public interfaces using `InternalClientHolder` (ServiceClient → Training/Sampling/Rest). Users don’t call it directly.
- Missing heartbeats can lead to server session expiration; Python warns after ~2 minutes of consecutive failures.
- No retry at the HTTP layer for heartbeat; failures are considered a signal, not a backoff/retry path.

Contrast with Elixir (current)
- `lib/tinkex/api/session.ex` posts to `/api/v1/heartbeat` (wrong path for the real API), and `SessionManager` silently drops sessions on 4xx, hiding failures.
- Tests stub `/api/v1/heartbeat`, so the wrong path passes locally.
- No warning/logging on sustained heartbeat failure beyond dropping the session entry.
