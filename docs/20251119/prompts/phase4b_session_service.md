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

If API submodules (`Service`, `Models`, etc.) don’t exist yet, create minimal stubs in `lib/tinkex/api/service.ex` etc. or call `Tinkex.API.post/4` directly for session/model creation.

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
   - Maintains active sessions (session_id, heartbeat interval, config).
   - Public API: `start_session(config)` -> `{:ok, session_id}`; `stop_session(session_id)`.
   - Sends heartbeat via `Tinkex.API.post("/api/v1/session/heartbeat", ...)` on interval (e.g., 10s).
   - Handles expired sessions (if heartbeat fails with user error, remove entry).
2. **ServiceClient**
   - `start_link(opts)` accepts `config: Tinkex.Config.t()` (or builds one).
   - On init: request SessionManager to start session, store session_id, start heartbeat reference.
   - Public APIs:
     - `create_lora_training_client/2` -> start TrainingClient via `Tinkex.ClientSupervisor`.
     - `create_sampling_client/2` -> start SamplingClient via supervisor.
     - `create_rest_client/1` (thin wrapper returning config/session info or future RestClient module stub).
   - Manage `model_seq_id` & `sampling_client_id` counters.
   - Document blocking behavior (calls GenServer so caller waits until subsystem ready).

---

## 3. Tests

1. `SessionManager` tests:
   - Start session (mock HTTP with Bypass), heartbeat triggered (use `Process.sleep` with short interval or send :heartbeat message).
   - Failure case: heartbeat returns 401/4xx -> session removed.
2. `ServiceClient` tests:
   - start_link with config uses SessionManager (mock endpoints).
   - `create_lora_training_client/2` spawns child via `DynamicSupervisor`, returns pid.
   - `create_sampling_client/2` similar.
   - Multi-config: two clients with different configs don’t interfere (stubs acceptable).

Use Bypass or Mox to simulate API responses.

---

## 4. Constraints & Guidance

- No direct `Application.get_env` inside call paths; pass config explicitly.
- Heartbeat interval configurable? Accept `opts[:heartbeat_interval_ms]` (default 10_000).
- `SessionManager` should be supervised (already started in Phase 4A). Use ETS or map state for sessions.
- `ServiceClient` must trap exits? Optional, but handle `terminate/2` to stop session.
- Use `DynamicSupervisor.start_child/2` with `Tinkex.ClientSupervisor` for child clients.
- Document `@doc` for `ServiceClient` APIs (how to await tasks later).

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
