# Phase 4B: Session Manager & Service Client - Agent Prompt

> **Target:** Implement `Tinkex.SessionManager` (heartbeat + session lifecycle) and `Tinkex.ServiceClient` (GenServer entry point that spawns Training/Sampling clients via DynamicSupervisor).  
> **Timebox:** Week 3 - Day 2  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 4A runtime foundations (Application, SamplingRegistry, RateLimiter) complete.  
> **Next:** Phase 4C (TrainingClient + SamplingClient).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | SessionManager, ServiceClient design, sequencing | Sections on Session lifecycle & client creation |
| `docs/20251119/port_research/03_async_model.md` | Futures + polling info (ServiceClient passes config) | Overview of futures |
| `docs/20251119/port_research/04_http_layer.md` | API endpoints, config threading | `/api/v1/create_session`, etc. |
| `docs/20251119/port_research/07_porting_strategy.md` | Supervisor layout, config usage | Pre-implementation checklist |
| `lib/tinkex/api/api.ex` | HTTP client (will need `Service`, `Models` modules if missing) | Ensure we can call endpoints |
| `lib/tinkex/config.ex` | Config struct for multi-tenancy | start_link flows |

The repo already includes `Tinkex.API.Session`, `Tinkex.API.Service`, `Tinkex.API.Training`, `Tinkex.API.Sampling`, and `Tinkex.API.Weights`; reuse them. Only add new helpers (e.g., `Models`) if an endpoint truly lacks a wrapper.

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/session_manager.ex        # new GenServer
lib/tinkex/service_client.ex         # new GenServer + public API
lib/tinkex/api/service.ex            # optional helper for /create_session, /heartbeat (if needed)
lib/tinkex/api/models.ex             # optional helper for create_model, save_weights
test/tinkex/session_manager_test.exs
test/tinkex/service_client_test.exs
```

### 2.2 Deliverables

1. **SessionManager**
   - Maintains active sessions (session_id, heartbeat interval, config), supporting multiple concurrent sessions (potentially with different configs).
   - Public API: `start_session(config)` -> `{:ok, session_id}`; `stop_session(session_id)`.
   - Use the existing API submodule: create sessions via `Tinkex.API.Session.create/2` (or `create_typed/2` if present), and send heartbeats via `Tinkex.API.Session.heartbeat/2` (path `"/api/v1/heartbeat"`) on interval (e.g., 10s).
   - Handles heartbeat failures using `Tinkex.Error` categories: on user errors (4xx excluding 408/429, or category `:user`), treat the session as expired and remove it; on transient/server/unknown errors, keep the session, log, and retry on the next interval.
   - SessionManager should be supervised under `Tinkex.Application` (add it to the children if Phase 4A did not already do so).
2. **ServiceClient**
   - `start_link(opts)` accepts `config: Tinkex.Config.t()` (or builds one).
   - On init: request SessionManager (globally registered `Tinkex.SessionManager`) to start session, store session_id; SessionManager owns heartbeats.
   - Public APIs:
     - `create_lora_training_client/2` -> start TrainingClient via `Tinkex.ClientSupervisor`.
     - `create_sampling_client/2` -> start SamplingClient via supervisor.
     - `create_rest_client/1` (thin wrapper returning config/session info or future RestClient module stub).
   - Manage `model_seq_id` & `sampling_client_id` counters.
   - On shutdown (`terminate/2` or equivalent), call `SessionManager.stop_session(session_id)` to cleanly end the session.
   - Document blocking behavior (calls GenServer so caller waits until subsystem ready).

---

## 3. Tests

1. `SessionManager` tests:
   - Start session (mock HTTP with Bypass), heartbeat triggered (use `Process.sleep` with short interval or send :heartbeat message).
   - Failure case: heartbeat returns 401/4xx user error -> session removed; server/transient errors remain and are retried on next tick.
   - Ensure `Tinkex.API.Session.heartbeat/2` is used (path `"/api/v1/heartbeat"`), not a hardcoded alternate path.
2. `ServiceClient` tests:
   - start_link with config uses SessionManager (mock endpoints).
   - `create_lora_training_client/2` spawns child via `DynamicSupervisor`, returns pid.
   - `create_sampling_client/2` similar.
   - Multi-config: two clients with different configs don’t interfere (stubs acceptable).
   - It is acceptable in 4B to stub TrainingClient/SamplingClient modules or use Mox until Phase 4C provides real implementations; the focus here is SessionManager interaction and child start calls.

Use Bypass or Mox to simulate API responses.

---

## 4. Constraints & Guidance

- No direct `Application.get_env` inside call paths; pass config explicitly.
- Heartbeat interval configurable? Accept `opts[:heartbeat_interval_ms]` (default 10_000).
- `SessionManager` must be supervised under `Tinkex.Application` (if not already wired in Phase 4A, add it here). Use ETS or map state for sessions.
- `ServiceClient` must trap exits? Optional, but handle `terminate/2` to stop session.
- Use `DynamicSupervisor.start_child/2` with `Tinkex.ClientSupervisor` for child clients.
- Document `@doc` for `ServiceClient` APIs (how to await tasks later).
- ServiceClient should not run its own heartbeat; it relies on the globally registered SessionManager that started the session.

---

## 5. Acceptance Criteria

- [ ] `Tinkex.SessionManager` manages session lifecycle, heartbeats, handles failure.
- [ ] `Tinkex.ServiceClient` starts session, exposes client creation APIs, tracks counters.
- [ ] Tests for both modules pass (`mix test test/tinkex/session_manager_test.exs test/tinkex/service_client_test.exs`).
- [ ] Full `mix test` + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load docs/source listed above (new context).
2. Implement SessionManager + ServiceClient (and API helpers if needed).
3. Add comprehensive tests with Bypass/Mox.
4. Run targeted tests, `mix test`, and `mix dialyzer`.
5. Summarize changes referencing precise file paths in final response.

**Reminder:** Each Phase 4 prompt is standalone—include all necessary context/instructions. Good luck!***
