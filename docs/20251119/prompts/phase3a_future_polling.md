# Phase 3A: Futures Infrastructure - Agent Prompt

> **Target:** Implement the Future types, TryAgainResponse handling, QueueState telemetry, and the polling scaffold that Phase 3B/3C build upon.  
> **Timebox:** Week 2 - Day 4 (morning)  
> **Location:** `S:\tinkex` (pure Elixir library)  
> **Prerequisites:** Phase 2B complete (HTTP client, telemetry, retry logic).  
> **Next:** Phase 3B (Polling Engine), Phase 3C (Metrics Reduction & Await helpers).

---

## 1. Required Reading (load into your workspace before coding)

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/03_async_model.md` | Async/future design, queue-state semantics | Entire file (esp. lines covering TryAgainResponse, QueueState, telemetry) |
| `docs/20251119/port_research/02_client_architecture.md` | How clients enqueue futures and consume them | QueueStateObserver, Training/Sampling client notes |
| `docs/20251119/port_research/05_error_handling.md` | Retry semantics, error categories | x-should-retry table & retry logic |
| `lib/tinkex/api/api.ex` | HTTP client implementation | Current retry logic, telemetry |
| `lib/tinkex/config.ex` | Multi-tenant config | Ensures polling takes config from opts |
| `test/tinkex/api/api_test.exs` | Finch/Bypass patterns | Use as template for polling tests |

**Load these refs** in the new context; each prompt is standalone.

---

## 2. Scope for Phase 3A

### 2.1 Modules & Files

```
lib/tinkex/types/try_again_response.ex        # new
lib/tinkex/types/queue_state.ex               # new (atom parser)
lib/tinkex/future.ex                          # new (module skeleton)
test/tinkex/types/try_again_response_test.exs # new
test/tinkex/types/queue_state_test.exs        # new
```

### 2.2 Deliverables

1. **Type Definitions**
   - `Tinkex.Types.QueueState` with parser returning `:active | :paused_rate_limit | :paused_capacity | :unknown`.
   - `Tinkex.Types.TryAgainResponse` with `type`, `queue_state`, `retry_after_ms`.
2. **Future Skeleton**
   - `Tinkex.Future.poll/2` signature and struct for internal state (no loop yet—that lands in 3B).
   - QueueState telemetry helper (emits `[:tinkex, :queue, :state_change]`).
   - `@behaviour Tinkex.QueueStateObserver` declaration (optional callbacks).
3. **Tests**
   - Parser tests for QueueState.
   - JSON decoding tests for TryAgainResponse (case-insensitive when mapping from API maps).

No polling loop or metrics reduction yet—just plumbing.

---

## 3. Constraints & Guidance

1. **No Application.get_env** at call sites. Use `opts[:config]`.
2. **Lowercase RequestErrorCategory** already confirmed; match style (case-insensitive parser).
3. **Queue state telemetry**
   - Emit telemetry event with `%{queue_state: atom}` metadata.
   - Add a doc snippet describing how TrainingClient/SamplingClient can implement the observer behaviour.
4. **TryAgainResponse**
   - Accepts JSON maps from API; normalize keys to atom fields.
   - Provide `from_map/1` helper returning `%TryAgainResponse{}` or `{:error, reason}`.

---

## 4. Acceptance Criteria

- [ ] `Tinkex.Types.QueueState.parse/1` covers all documented states + unknown.
- [ ] `Tinkex.Types.TryAgainResponse.from_map/1` handles map/string keys (from Jason).
- [ ] `Tinkex.Future` module compiles with public `poll/2` (even if returning `{:error, :not_impl}` for now) and telemetry helper.
- [ ] Tests green via `mix test test/tinkex/types/queue_state_test.exs test/tinkex/types/try_again_response_test.exs`.
- [ ] Dialyzer clean (`mix dialyzer`).

---

## 5. Execution Checklist

1. Read required documents/source.
2. Create new modules/tests.
3. Run targeted tests.
4. Run full suite (`mix test`) + Dialyzer.
5. Provide summary referencing files + line numbers.

**Reminder:** This environment is standalone; include all context in your implementation notes. Refer back to Phase 2 docs as needed. Each Phase 3 prompt assumes no prior state. Provide precise instructions/results to the user. Good luck!***
