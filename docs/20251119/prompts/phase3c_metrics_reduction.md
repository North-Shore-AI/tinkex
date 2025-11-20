# Phase 3C: Metrics Reduction & Await Helpers - Agent Prompt

> **Target:** Implement `Tinkex.MetricsReduction`, the combined-future helpers (`await_many`, `combine_forward_backward_results`), and `Tinkex.Future.await/2`. Finalize queue-state observer wiring + documentation.  
> **Timebox:** Week 2 - Day 5  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 3A (types) + 3B (poll loop).  
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
| `lib/tinkex/types/forward_backward_output.ex` (or equivalent) | Where metrics live | ensure struct updates safe |
| Existing tests under `test/tinkex/types/*` | Patterns for new tests | e.g., queue state tests |

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/metrics_reduction.ex             # new module
lib/tinkex/future.ex                        # add await helpers
lib/tinkex/future/combiner.ex               # optional helper module (new)
lib/tinkex/queue_state_observer.ex          # ensure docs + hooks from 3B referenced
lib/tinkex/types/forward_backward_output.ex # ensure combine fn lives here or TrainingClient helper
test/tinkex/metrics_reduction_test.exs      # new
test/tinkex/future/await_test.exs           # new
```

### 2.2 Features

1. **Metrics Reduction (`Tinkex.MetricsReduction`)**
   - Implement suffix-based reducers (`:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`) matching Python `REDUCE_MAP`.
   - Weighted mean uses number of `loss_fn_outputs` per chunk as weight.
   - `:unique` retains first value under original key, subsequent values as `key_2`, etc. (match Python semantics).
   - Provide `reduce(results)` returning `%{metric_name => value}`.
2. **ForwardBackward combiner**
   - Utility function `combine_forward_backward_results(results)` producing a single `%ForwardBackwardOutput{}`:
     - `loss_fn_outputs`: flatten.
     - `metrics`: use `Tinkex.MetricsReduction.reduce/1`.
   - Place in `Tinkex.Future.Combiner` or `Tinkex.Types.ForwardBackwardOutput` helper module (document location).
3. **Await Helpers**
   - `Tinkex.Future.await(task, timeout \\ :infinity)` wraps `Task.await/2`, converts exits/timeouts into `%Tinkex.Error{type: :api_timeout}`.
   - `Tinkex.Future.await_many(tasks, timeout \\ :infinity)` uses `Task.await_many/2`, returns list of results maintaining order.
   - Optionally expose `Tinkex.Future.combine(tasks, fun)` returning Task that waits + applies fun.

---

## 3. Tests

1. **metrics_reduction_test.exs**
   - Weighted mean with varying output counts (match Python example: 3 chunks).
   - `:sum`, `:min`, `:max`, `:slack`, `:unique` cases.
   - Unknown suffix falls back to mean.
2. **future/await_test.exs**
   - `Future.await/2` success path.
   - Timeout path returns `{:error, %Tinkex.Error{type: :api_timeout}}`.
   - `await_many/2` preserves order and surfaces first error.

Use pure data (no Bypass needed).

---

## 4. Constraints

- Align metrics map key handling with Python: only metrics present in first chunk considered, ignore keys missing in later chunks.
- Keep modules documented with doctests where useful.
- `MetricsReduction.reduce/1` must accept list of maps with keys `:metrics` and `:loss_fn_outputs`.
- Do not mutate input structs; return new ones.

---

## 5. Acceptance Criteria

- [ ] `Tinkex.MetricsReduction.reduce/1` passes targeted tests covering all reducers.
- [ ] `combine_forward_backward_results/1` uses reduction module and is shared (TrainingClient can call it in Phase 4).
- [ ] `Tinkex.Future.await/2` and `await_many/2` handle timeouts/errors gracefully.
- [ ] Tests under `test/tinkex/metrics_reduction_test.exs` and `test/tinkex/future/await_test.exs` pass.
- [ ] `mix test` (full suite) + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Read required docs/source in this fresh context.
2. Implement metrics module + helpers + await functions.
3. Write comprehensive unit tests.
4. Run targeted tests, then full suite, then dialyzer.
5. Summarize changes referencing files/lines.

**Reminder:** Each Phase 3 prompt runs independently—repeat any necessary setup steps. Provide clear instructions/output in your final message. Good luck!
