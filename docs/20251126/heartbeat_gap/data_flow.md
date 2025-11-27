# Heartbeat data flow (Python SDK)

1) **Session creation**
   - `InternalClientHolder.__init__` calls `_create_session`, which POSTs `/api/v1/create_session` via `client.service.create_session`.
   - Returns `session_id` and starts async task `_session_heartbeat(session_id)`.

2) **Heartbeat loop** (`InternalClientHolder._session_heartbeat`)
   - Sleeps 10s, then POSTs `/api/v1/session_heartbeat` with `SessionHeartbeatRequest(session_id=...)`, `max_retries=0`, `timeout=10` using SESSION pool.
   - On success: updates `last_heartbeat_time`.
   - On exception: records `last_exception`, continues loop (no retry), no immediate log.
   - If `time_since_last_success > 120s`: logs warning including last exception and session id.

3) **Service resource** (`resources/service.py`)
   - Method `session_heartbeat` builds `SessionHeartbeatRequest`, POSTs to `/api/v1/session_heartbeat`, returns `SessionHeartbeatResponse`.

4) **Types**
   - `SessionHeartbeatRequest`: fields `session_id`, `type="session_heartbeat"`.
   - `SessionHeartbeatResponse`: field `type="session_heartbeat"`.

5) **Lifecycle hooks**
   - `InternalClientHolder` stores the heartbeat task (`self._session_heartbeat_task`) and cancels it on shutdown (`stop`/cleanup paths at lines ~237+ in `internal_client_holder.py`).
   - No explicit session drop on heartbeat failure; responsibility is to warn, not tear down.

6) **Consumers**
   - All public clients (TrainingClient, SamplingClient, RestClient) are created from the holder; they inherit the live session maintained by this heartbeat.
   - Users do not call heartbeat directly; it’s internal plumbing.

Failure semantics
- 4xx/5xx or network errors do **not** kill the loop; it keeps trying every 10s and warns after 2 minutes of continuous failure.
- Because `max_retries=0`, server-side throttling or transient failures are surfaced immediately in the log if persistent.
