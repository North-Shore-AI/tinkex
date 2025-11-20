# Phase 3C: Metrics Reduction & Await Helpers - Agent Prompt

> **Target:** Implement `Tinkex.MetricsReduction`, the combined-future helpers (`await_many`, `combine_forward_backward_results`), and `Tinkex.Future.await/2`. Finalize queue-state observer wiring + documentation.
> **Timebox:** Week 2 - Day 5
> **Location:** `S:\tinkex`
> **Prerequisites:** Phase 3A (types) + 3B (poll loop).
> **Repo State:** Assume the repository already includes all changes from Phase 3A and 3B (QueueState, TryAgainResponse, Future poll loop with observer support).
> **Next:** Phase 4 (Client architecture integration).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/03_async_model.md` | Metrics reduction algorithm (`REDUCE_MAP`), combined futures | Sections on `chunked_fwdbwd_helpers._metrics_reduction` |
| `docs/20251119/port_research/02_client_architecture.md` | TrainingClient combiner expectations | Forward/backward chunk combining |
| `docs/20251119/port_research/05_error_handling.md` | `Tinkex.Error`/retry semantics | request_failed vs api_status |
| `lib/tinkex/api/api.ex` | Currently used by TrainingClient | Understand how results return |
| `lib/tinkex/future.ex` | Poll loop from Phase 3B | Add await helper here |
| `lib/tinkex/types/forward_backward_output.ex` | Where metrics live | Input type for reduction |
| Existing tests under `test/tinkex/types/*` | Patterns for new tests | e.g., queue state tests |

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/metrics_reduction.ex             # new module
lib/tinkex/future.ex                        # add await helpers
lib/tinkex/future/combiner.ex               # combiner helper module (new)
lib/tinkex/queue_state_observer.ex          # ensure docs + hooks from 3B referenced
test/tinkex/metrics_reduction_test.exs      # new
test/tinkex/future/await_test.exs           # new
```

### 2.2 Features

1. **Metrics Reduction (`Tinkex.MetricsReduction`)**
   - Implement suffix-based reducers (`:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`) matching Python `REDUCE_MAP`.
   - `MetricsReduction.reduce/1` accepts a **list of `%ForwardBackwardOutput{}` structs** (not generic maps).
     - Uses `result.metrics` and `result.loss_fn_outputs` directly.
   - **Python parity (critical):** Only metrics present in the **first chunk** should be reduced. Keys missing in later chunks are ignored for that key (not treated as zero). Promote this prominently—it's easy to miss.
   - Weighted mean uses number of `loss_fn_outputs` per chunk as weight.
   - `:unique` retains first value under original key, subsequent values as `key_2`, `key_3`, etc. (match Python semantics).
   - Unknown suffix → treat as mean.
   - Provide `reduce(results)` returning `%{metric_name => value}`.
   - **Edge cases:**
     - If `results` is an empty list, return `%{}`.
     - For weighted reductions, if total weight is 0, return `0.0` for that metric.

2. **ForwardBackward combiner**
   - Implement `Tinkex.Future.Combiner.combine_forward_backward_results/1`:
     ```elixir
     @spec combine_forward_backward_results([ForwardBackwardOutput.t()]) ::
             ForwardBackwardOutput.t()
     ```
   - The combined `%ForwardBackwardOutput{}` should:
     - Take `loss_fn_output_type` from the first chunk. If types disagree across chunks, log a warning and use the first chunk's value (do not raise in production).
     - Flatten `loss_fn_outputs` from all chunks.
     - Compute `metrics` via `Tinkex.MetricsReduction.reduce/1`.
   - TrainingClient in Phase 4 will depend on this exact function.

3. **Await Helpers**
   - `Tinkex.Future.await(task, timeout \\ :infinity)` wraps `Task.await/2`, converts exits/timeouts into `%Tinkex.Error{type: :api_timeout}`.
   - `Tinkex.Future.await_many(tasks, timeout \\ :infinity)`:
     - Returns a list of the underlying Task results (`{:ok, result}` or `{:error, %Tinkex.Error{}}`) in the same order as the input tasks.
     - Must not raise on Task exits/timeouts—convert to `{:error, %Tinkex.Error{type: :api_timeout}}`.
     - **Implementation note:** `Task.await_many/2` raises on failure, so either wrap it in `try/rescue` or call `Task.await/2` per task with error handling.
   - Optionally expose `Tinkex.Future.combine(tasks, fun)` returning Task that waits + applies fun.
   - **Timeout separation:** `Future.await/2` treats the task as an opaque black box. It must not attempt to compute or enforce the poll timeout itself. `poll/2`'s `opts[:timeout]` governs how long the loop runs; `await/2` only governs how long the caller is willing to wait on the Task. These are separate concerns.

---

## 3. Tests

1. **metrics_reduction_test.exs**
   - Weighted mean with varying output counts (match Python example: 3 chunks).
   - `:sum`, `:min`, `:max`, `:slack`, `:unique` cases.
   - Unknown suffix falls back to mean.
   - **Critical test:** First chunk defines metric set—later chunks with extra keys should have those extra keys ignored.
   - **Critical test:** Keys missing in later chunks are skipped for that chunk's contribution (not zero-filled).
   - **Edge case test:** Empty results list returns `%{}`.
   - **Edge case test:** Zero total weight returns `0.0`.

2. **future/await_test.exs**
   - `Future.await/2` success path.
   - Timeout path returns `{:error, %Tinkex.Error{type: :api_timeout}}`.
   - `await_many/2` preserves order and returns list of `{:ok, result} | {:error, error}`.
   - `await_many/2` converts Task exits/timeouts to errors (no raises).

3. **combiner tests** (can be in metrics_reduction_test or separate)
   - `combine_forward_backward_results/1` correctly combines multiple chunks.
   - Takes `loss_fn_output_type` from first chunk.
   - Flattens `loss_fn_outputs`.
   - Uses metrics reduction.

Use pure data (no Bypass needed).

---

## 4. Constraints

- **Python parity:** Only metrics present in the first chunk are considered; ignore keys missing in later chunks (do not treat as zero).
- Keep modules documented with doctests where useful.
- `MetricsReduction.reduce/1` accepts list of `%ForwardBackwardOutput{}` structs (not generic maps with `:metrics` keys).
- Do not mutate input structs; return new ones.
- `await/2` timeout is independent of `poll/2` timeout—do not conflate them.
- `await_many/2` must return a list (not raise), with errors at appropriate indices.

---

## 5. Acceptance Criteria

- [ ] `Tinkex.MetricsReduction.reduce/1` passes targeted tests covering all reducers.
- [ ] Reduction correctly handles first-chunk-defines-metrics-set semantics.
- [ ] Edge cases (empty list, zero weight) are handled gracefully.
- [ ] `Tinkex.Future.Combiner.combine_forward_backward_results/1` is implemented with correct spec.
- [ ] Combiner correctly handles `loss_fn_output_type`, flattens outputs, and uses reduction.
- [ ] `Tinkex.Future.await/2` and `await_many/2` handle timeouts/errors gracefully.
- [ ] `await_many/2` returns list of results without raising.
- [ ] Tests under `test/tinkex/metrics_reduction_test.exs` and `test/tinkex/future/await_test.exs` pass.
- [ ] `mix test` (full suite) + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Read required docs/source in this fresh context.
2. Implement `Tinkex.MetricsReduction` with proper first-chunk semantics and edge case handling.
3. Implement `Tinkex.Future.Combiner.combine_forward_backward_results/1` with exact spec.
4. Add await functions to `Tinkex.Future` with proper error conversion.
5. Write comprehensive unit tests, especially for edge cases around metric set definition.
6. Run targeted tests, then full suite, then dialyzer.
7. Summarize changes referencing files/lines.

**Reminder:** Each Phase 3 prompt runs independently—repeat any necessary setup steps. Assume Phase 3A and 3B are complete in the repo. Provide clear instructions/output in your final message. Good luck!
