# Phase 4A: Runtime Foundations - Agent Prompt

> **Target:** Implement the Phase 4 foundational runtime pieces: `Tinkex.Application`, ETS table setup, `Tinkex.SamplingRegistry`, and `Tinkex.RateLimiter`.  
> **Timebox:** Week 3 - Day 1  
> **Location:** `S:\tinkex` (pure Elixir library)  
> **Prerequisites:** Phases 1‑3 complete (types, HTTP layer, futures).  
> **Next:** Phase 4B (SessionManager + ServiceClient), Phase 4C (TrainingClient + SamplingClient).

---

## 1. Required Reading (load these in the fresh context)

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Supervisor tree, ETS strategy, RateLimiter spec | Sections on Application, SamplingRegistry, RateLimiter |
| `docs/20251119/port_research/04_http_layer.md` | Finch pool setup, PoolKey usage | Pool config + PoolKey references |
| `docs/20251119/port_research/07_porting_strategy.md` | Pre-implementation checklist (ETS, Config threading) | Sections on multi-tenancy, ETS tables |
| `lib/tinkex/api/api.ex` | Current HTTP client | Understand pool names, config usage |
| `lib/tinkex/config.ex` | Multi-tenant config struct | ensures defaults used |

---

## 2. Scope for Phase 4A

### 2.1 Modules/Files

```
lib/tinkex/application.ex         # replace stub with full supervisor tree
lib/tinkex/pool_key.ex           # reuse from Phase 2; ensure normalized base URL
lib/tinkex/sampling_registry.ex  # new GenServer with process monitoring + ETS cleanup
lib/tinkex/rate_limiter.ex       # new module using atomics + ETS insert_new
test/tinkex/sampling_registry_test.exs
test/tinkex/rate_limiter_test.exs
```

### 2.2 Deliverables

1. **Application Supervision Tree**
   - Create ETS tables (`:tinkex_sampling_clients`, `:tinkex_rate_limiters`, `:tinkex_tokenizers`).
   - Start Finch with per-pool configuration (default, :training, :sampling, :session, :futures, :telemetry) using `Tinkex.PoolKey`.
   - Start `Tinkex.SamplingRegistry`, `DynamicSupervisor` for clients (name `Tinkex.ClientSupervisor`).
2. **SamplingRegistry**
   - `register(pid, config)` API that inserts into ETS and monitors process.
   - On `{:DOWN, _}` remove ETS entry.
3. **RateLimiter**
   - `for_key({base_url, api_key})` returning shared atomics handle (use normalized base URL).
   - Use `:ets.insert_new/2` to avoid split-brain.
   - `should_backoff?`, `set_backoff/2`, `clear_backoff/1`, `wait_for_backoff/1`.
   - Backoff times stored as `System.monotonic_time(:millisecond)` deadlines.

---

## 3. Tests

1. `SamplingRegistry` tests:
   - Registers ETS entry; removal happens on process exit.
   - Handles multiple registrations.
2. `RateLimiter` tests:
   - `for_key/1` returns same atomics for normalized URLs.
   - Insert_new prevents duplicate creation.
   - `set_backoff` + `should_backoff?` behave as expected.

Use ExUnit + Agents/Tasks as needed.

---

## 4. Constraints & Guidance

- No `Application.get_env` inside hot paths—only at `Application.start/2`.
- Finch pools must match doc table (sizes/timeouts). Use `config :tinkex, :base_url` default fallback.
- ETS tables should be `:named_table, :public` with read concurrency.
- RateLimiter keys: `{Tinkex.PoolKey.normalize_base_url(base_url), api_key}`.
- Tests must clean up ETS entries (`setup`/`on_exit`).

---

## 5. Acceptance Criteria

- [ ] `Tinkex.Application` starts ETS tables + children (Finch + registry + dynamic supervisor).
- [ ] `Tinkex.SamplingRegistry` registers and cleans entries on process death.
- [ ] `Tinkex.RateLimiter` shares atomics per `{base_url, api_key}` and supports backoff APIs.
- [ ] Tests (`mix test test/tinkex/sampling_registry_test.exs test/tinkex/rate_limiter_test.exs`) pass deterministically.
- [ ] `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load required docs + files in this new context.
2. Implement Application, SamplingRegistry, RateLimiter.
3. Write targeted tests.
4. Run targeted tests, `mix test`, and `mix dialyzer`.
5. Summarize changes referencing file paths/lines in final response.

**Reminder:** This prompt is self-contained. Include all necessary context/instructions when you output the final result. Good luck!***
