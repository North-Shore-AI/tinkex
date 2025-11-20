# Phase 3B: Polling Engine & Queue Backpressure - Agent Prompt

> **Target:** Implement `Tinkex.Future.poll/2` looping logic, TryAgainResponse backoff, queue telemetry, and integration tests.  
> **Timebox:** Week 2 - Day 4 (afternoon)  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 3A types + skeleton complete.  
> **Next:** Phase 3C (Metrics Reduction + await helpers).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/03_async_model.md` | Polling/backoff, TryAgainResponse semantics, telemetry events | Entire file |
| `docs/20251119/port_research/05_error_handling.md` | Retry logic, error categories | x-should-retry table |
| `docs/20251119/port_research/02_client_architecture.md` | QueueStateObserver hook, sampling/training integration | Queue state sections |
| `lib/tinkex/api/api.ex` | HTTP client, existing retry semantics | `post/4`, `with_retries/5` |
| `lib/tinkex/types/queue_state.ex` | Output from Phase 3A | Parser |
| `lib/tinkex/types/try_again_response.ex` | Output from Phase 3A | `from_map/1` |
| `lib/tinkex/future.ex` | Skeleton from Phase 3A | Add loop logic here |
| `test/tinkex/api/api_test.exs` | Finch/Bypass patterns | Use as template |

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/future.ex                   # flesh out poll loop
lib/tinkex/queue_state_observer.ex     # optional behaviour (new)
test/tinkex/future/poll_test.exs       # new Bypass-based suite
```

### 2.2 Features

1. **Polling Loop**
   - `Tinkex.Future.poll/2` returns `Task.t({:ok, result} | {:error, Tinkex.Error.t()})`.
   - Loop calls `/api/v1/future/retrieve` via `Tinkex.API.Futures.retrieve/3`.
   - Handles statuses: `"completed"`, `"failed"`, `"pending"`, `TryAgainResponse`.
2. **TryAgainResponse & QueueState**
   - Parse JSON response into `%TryAgainResponse{}`.
   - Emit telemetry on queue-state changes.
   - Apply backoff: paused states wait 1s (or `retry_after_ms` if present).
3. **Backoff Strategy**
   - Exponential backoff for pending/poll errors: 500ms start, cap 30s.
   - Timeout support: `opts[:timeout]` (ms). If elapsed exceeds, return {:error, timeout}.
4. **Observer Behaviour**
   - `Tinkex.QueueStateObserver` behaviour with `c:on_queue_state_change/1`.
   - Optional callback invoked when queue state transitions.

---

## 3. Tests (new `test/tinkex/future/poll_test.exs`)

Use Bypass to simulate `/api/v1/future/retrieve`.

Cover:
1. Completed result (single call).
2. Pending → completed (multiple calls, check backoff counts).
3. Failed with category `:user` → no retry.
4. Failed with category `:server` → retries.
5. TryAgainResponse with `queue_state: "paused_rate_limit"` (should sleep and log).
6. Timeout reached → {:error, %Tinkex.Error{type: :api_timeout}}.
7. Telemetry event fired (attach handler in test).

---

## 4. Constraints

- No `Process.sleep/1` in tests—use counters or `System.monotonic_time` assertions with small delays (0ms/5ms). Use Mox or Bypass to track call counts.
- Telemetry: `[:tinkex, :queue, :state_change]` metadata must include `:queue_state`.
- `poll/2` should accept `%{request_id: id}` maps (as returned by API) or plain IDs.
- Use `Keyword.fetch!(opts, :config)` for HTTP calls (no env lookups).

---

## 5. Acceptance Criteria

- [ ] `Tinkex.Future.poll/2` returns Task executing full loop with backoff, timeout, TryAgain handling.
- [ ] `Tinkex.QueueStateObserver` behaviour defined + docs guiding Training/Sampling clients.
- [ ] Telemetry emitted for queue state transitions; tests assert on event metadata.
- [ ] Bypass tests cover success, retry, TryAgain, timeout, user-error no retry.
- [ ] `mix test test/tinkex/future/poll_test.exs` passes (and is deterministic).
- [ ] `mix dialyzer` stays clean.

---

## 6. Execution Checklist

1. Load required docs/src in this context.
2. Implement behaviour + future loop + telemetry.
3. Add comprehensive tests.
4. Run targeted tests + dialyzer.
5. Summarize changes referencing file paths/lines in final response.

**Reminder:** This prompt is standalone—include all necessary context and commands in your answer. Good luck!
