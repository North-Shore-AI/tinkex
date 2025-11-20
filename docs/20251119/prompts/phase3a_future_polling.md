# Phase 3A: Futures Infrastructure - Agent Prompt

> **Target:** Extract and refactor the Future types, TryAgainResponse handling, QueueState telemetry, and the polling scaffold that Phase 3B/3C build upon.
> **Timebox:** Week 2 - Day 4 (morning)
> **Location:** `S:\tinkex` (pure Elixir library)
> **Prerequisites:** Phase 2B complete (HTTP client, telemetry, retry logic).
> **Repo State:** Assume the repository already contains `Tinkex.Types.TryAgainResponse` and `FutureRetrieveResponse` in `lib/tinkex/types/future_responses.ex`.
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
| `lib/tinkex/types/future_responses.ex` | **Existing** TryAgainResponse, FutureRetrieveResponse | Code to be refactored |
| `test/tinkex/api/api_test.exs` | Finch/Bypass patterns | Use as template for polling tests |

**Load these refs** in the new context; each prompt is standalone.

---

## 2. Scope for Phase 3A

### 2.1 Modules & Files

```
lib/tinkex/types/try_again_response.ex        # EXTRACT from future_responses.ex
lib/tinkex/types/queue_state.ex               # new (atom parser, extracted from TryAgainResponse)
lib/tinkex/future.ex                          # new (module skeleton)
test/tinkex/types/try_again_response_test.exs # new
test/tinkex/types/queue_state_test.exs        # new
```

### 2.2 Deliverables

1. **Type Definitions (Refactor)**
   - **Extract** `Tinkex.Types.QueueState` module from existing `parse_queue_state/1` logic in `TryAgainResponse`.
     - Parser returns `:active | :paused_rate_limit | :paused_capacity | :unknown`.
     - **Breaking change:** Unknown strings now map to `:unknown` (previously mapped to `:active`). Add test that explicitly documents this change.
     - After extracting `QueueState.parse/1`, remove or deprecate `TryAgainResponse.parse_queue_state/1` to avoid duplicated parsing logic.
   - **Extract** `Tinkex.Types.TryAgainResponse` from `future_responses.ex` into its own file.
     - Keep existing public API, but add `from_map/1` helper.
     - `from_map/1` should return `%TryAgainResponse{}` directly (raise or log on malformed input). Malformed means missing required fields like `queue_state` or `type`, or wrong value types. Add at least one bad-input test case.
     - This keeps it consistent with `FutureRetrieveResponse.from_json/1` which returns only union structs.
     - Update to use new `QueueState.parse/1`.
   - **Update** `Tinkex.Types.FutureRetrieveResponse.from_json/1` to call `TryAgainResponse.from_map/1` for `"type" => "try_again"` variants and continue to return only union structs.

2. **Future Skeleton**
   - `Tinkex.Future.poll/2` signature returning `Task.t({:ok, result} | {:error, Tinkex.Error.t()})`.
     - **Even in this stub**, return a Task: `Task.async(fn -> {:error, :not_implemented} end)`.
   - Internal state struct for tracking poll state (including previous queue state for transition detection).
   - **Queue-state telemetry helper:** Implement as a private function in `Tinkex.Future` (e.g. `maybe_emit_queue_state_change(prev_state, new_state, opts)`).
     - Emits `[:tinkex, :queue, :state_change]` with `%{queue_state: atom}` in metadata.
     - **Important:** Only emit events when the queue state actually transitions from one atom to another, not on every poll.
   - **Clarification:** `Tinkex.Future` does *not* implement `Tinkex.QueueStateObserver`. It only emits telemetry. TrainingClient/SamplingClient will implement the behaviour in Phase 4.

3. **Tests**
   - Parser tests for `QueueState.parse/1` including explicit test for unknown → `:unknown`.
   - JSON decoding tests for `TryAgainResponse.from_map/1` covering:
     - Both atom and string keys (`:queue_state` / `"queue_state"`).
     - **Case-insensitive queue_state values** (e.g. `"PAUSED_RATE_LIMIT"`, `"Paused_Rate_Limit"`).
   - Test that `FutureRetrieveResponse.from_json/1` correctly delegates to `TryAgainResponse.from_map/1`.

No polling loop or metrics reduction yet—just plumbing.

---

## 3. Constraints & Guidance

1. **No Application.get_env** at call sites. Use `opts[:config]`.
2. **Lowercase RequestErrorCategory** already confirmed; match style (case-insensitive parser for values).
3. **Queue state telemetry**
   - Emit telemetry event with `%{queue_state: atom}` in metadata (not measurements).
   - Only emit when state actually changes (deduplicate consecutive identical states).
   - Add a doc snippet describing how TrainingClient/SamplingClient can implement the observer behaviour.
4. **TryAgainResponse**
   - Accepts JSON maps from API; normalize keys to atom fields.
   - `from_map/1` returns `%TryAgainResponse{}` directly (not `{:ok, ...} | {:error, ...}`).
   - Handles both string and atom keys (from Jason decoding).
   - Values like `queue_state` should be parsed case-insensitively.
5. **Refactoring**
   - This phase refactors existing code, not greenfield. Ensure `future_responses.ex` still exports `FuturePendingResponse`, `FutureCompletedResponse`, `FutureFailedResponse`.
   - Update any imports/aliases in existing code that referenced the moved modules.

---

## 4. Acceptance Criteria

- [ ] `Tinkex.Types.QueueState.parse/1` covers all documented states + unknown strings → `:unknown`.
- [ ] `Tinkex.Types.TryAgainResponse.from_map/1` handles atom/string keys and case-insensitive values, returns `%TryAgainResponse{}` directly.
- [ ] `Tinkex.Types.FutureRetrieveResponse.from_json/1` delegates to `TryAgainResponse.from_map/1` for try_again types.
- [ ] `Tinkex.Future` module compiles with public `poll/2` returning `Task.t()` (stub implementation).
- [ ] Private telemetry helper in `Tinkex.Future` only emits on state transitions.
- [ ] Tests green via `mix test test/tinkex/types/queue_state_test.exs test/tinkex/types/try_again_response_test.exs`.
- [ ] Dialyzer clean (`mix dialyzer`).
- [ ] Existing tests still pass after refactoring.

---

## 5. Execution Checklist

1. Read required documents/source, especially existing `future_responses.ex`.
2. Extract `QueueState` module with updated unknown → `:unknown` behaviour.
3. Extract `TryAgainResponse` module, add `from_map/1` returning struct directly, update to use `QueueState.parse/1`.
4. Update `FutureRetrieveResponse.from_json/1` to delegate.
5. Create `Tinkex.Future` skeleton with proper Task return type and private telemetry helper.
6. Write comprehensive tests covering the behaviour change and case-insensitive values.
7. Run targeted tests.
8. Run full suite (`mix test`) + Dialyzer to catch any broken imports.
9. Provide summary referencing files + line numbers.

**Reminder:** This environment is standalone; include all context in your implementation notes. This phase involves refactoring existing code—be careful to maintain backwards compatibility where possible and document breaking changes. Good luck!
