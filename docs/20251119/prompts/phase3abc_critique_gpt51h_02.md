You’ve cleaned these up a *lot*—they’re much more consistent with the repo and the port docs now. I’ll walk through each phase and then call out the remaining sharp edges / ambiguities I see.

---

## Phase 3A – Futures Infrastructure

### What’s working well now

* ✅ **Explicit repo state.** You now say “assume `TryAgainResponse` and `FutureRetrieveResponse` are already in `future_responses.ex`,” which matches the actual repo.
* ✅ **Refactor vs greenfield.** The scope says “EXTRACT from `future_responses.ex`” and “refactors existing code,” which avoids the earlier duplication trap.
* ✅ **QueueState behaviour change is explicit.**

  * You intentionally change “unknown string → `:active`” into `:unknown`.
  * You call that out as a breaking change and require a test that documents it.
* ✅ **`poll/2` contract is locked early.**

  * Even the stub returns `Task.t({:ok, _} | {:error, _})` via `Task.async`, aligning with Phase 3B.
* ✅ **Telemetry semantics are clear.**

  * Emits `[:tinkex, :queue, :state_change]`.
  * `queue_state` goes in metadata.
  * Only on transitions (not every poll).
* ✅ **Future / observer separation is clarified.**

  * “Tinkex.Future does *not* implement `Tinkex.QueueStateObserver`.” That prevents the earlier “put behaviour in the wrong place” mistake.

### Remaining nits / ambiguities

1. **`TryAgainResponse.from_map/1` return type vs `FutureRetrieveResponse.from_json/1`**

   You now require:

   * `TryAgainResponse.from_map/1` → `{:ok, %TryAgainResponse{}} | {:error, reason}`.
   * `FutureRetrieveResponse.from_json/1` delegates to `from_map/1` for `"type" => "try_again"`.

   But you don’t say what `from_json/1` should do if `from_map/1` returns `{:error, reason}`. Right now its natural API is “always return a typed struct”.

   You probably want one of:

   * **Option A (simplest):** Make `from_map/1` just return `%TryAgainResponse{}` (raise on error or treat invalid input as `{:error, :invalid}` at call sites that care), and keep `FutureRetrieveResponse.from_json/1` returning only union members.
   * **Option B:** Change `FutureRetrieveResponse.from_json/1`’s contract to `t | {:error, reason}` and update any call sites accordingly (heavier change).

   As written, an agent could delegate but then just `elem(1, from_map/1)` and ignore the `{:error, …}` branch, which makes the return-type promise of `from_map/1` misleading.

   **Suggested tweak in the prompt:**

   > `TryAgainResponse.from_map/1` should return `%TryAgainResponse{}` directly (raise or log on malformed input). `FutureRetrieveResponse.from_json/1` must call `from_map/1` for `"type" => "try_again"` variants and continue to return only union structs.

   Or, if you really want the `{:ok, ...} | {:error, ...}` shape, explicitly say how `FutureRetrieveResponse.from_json/1` should propagate the error.

2. **“Case-insensitive key handling” is slightly vague**

   You ask for:

   > JSON decoding tests for `TryAgainResponse.from_map/1` (case-insensitive key handling).

   It’s not obvious whether you mean:

   * The **JSON keys** (`"queue_state"`, `"QUEUE_STATE"`, `"Queue_State"`) are case-insensitive, or
   * The **values** (`"paused_rate_limit"`, `"Paused_Rate_Limit"`) are case-insensitive, or
   * Both.

   The API in practice uses lower_snake_case JSON keys; robustness usually matters more for the *values*. Your earlier docs emphasized value parsing for enums (`RequestErrorCategory`, `StopReason`) not key names.

   **Suggestion:**

   Reword that bullet to something like:

   > JSON decoding tests for `TryAgainResponse.from_map/1` covering:
   >
   > * both atom and string keys (`:queue_state` / `"queue_state"`),
   > * **case-insensitive queue_state values** (e.g. `"PAUSED_RATE_LIMIT"`).

   That keeps robustness where it actually matters and doesn’t force weird key-normalization logic.

3. **Where does the queue-state telemetry helper live?**

   You say:

   * “QueueState telemetry helper that emits …”
   * And later under constraints you describe what it must do.

   It’s pretty clearly *intended* to live in `Tinkex.Future`, but it might be worth one explicit line:

   > Implement the queue-state telemetry helper as a private function in `Tinkex.Future` (e.g. `maybe_emit_queue_state_change(prev_state, new_state, opts)`), and store the last queue state in the internal state struct.

   That makes the placement unambiguous for an agent.

Otherwise, Phase 3A now reads as tight and well-aligned with the repo.

---

## Phase 3B – Polling Engine & Queue Backpressure

### Big improvements

* ✅ **Arity & call site are now correct.**

  * You explicitly say `Tinkex.API.Futures.retrieve/2` and show the call shape: `retrieve(%{request_id: request_id}, config: config, timeout: http_timeout)`.
* ✅ **HTTP vs poll-level retries are distinct.**

  * Clear: “must NOT duplicate HTTP-level retry logic; treat each call to `retrieve/2` as a single attempt”.
* ✅ **Backoff constants are now unified with the async docs.**

  * Start 1s, cap 30s, 1–2–4–8–16–30–30–…
* ✅ **Timeout semantics are corrected.**

  * `opts[:timeout]` (in ms), default `:infinity`.
  * Timeout leads to `{:error, %Tinkex.Error{type: :api_timeout}}`, which matches your error module.
* ✅ **Observer wiring is now fully specified.**

  * `Tinkex.QueueStateObserver` behaviour.
  * `poll/2` accepts `opts[:queue_state_observer]`.
  * On state change, emit telemetry *and* call `observer.on_queue_state_change/1`.
* ✅ **Testable sleep injection is spelled out.**

  * `opts[:sleep_fun]` default `&Process.sleep/1`.
  * Tests must use `sleep_fun` instead of direct `Process.sleep`.

### Remaining sharp edges

1. **How to get from JSON map to typed responses**

   You say:

   > Parse JSON response into `%TryAgainResponse{}`.
   > Handles statuses `"completed"`, `"failed"`, `"pending"`, `TryAgainResponse`.

   But you don’t spell out the step in between:

   * `Tinkex.API.Futures.retrieve/2` returns `{:ok, map()} | {:error, Tinkex.Error.t()}`.
   * You already have `Tinkex.Types.FutureRetrieveResponse.from_json/1` to map maps into:

     * `%FuturePendingResponse{}`,
     * `%FutureCompletedResponse{}`,
     * `%FutureFailedResponse{}`,
     * `%TryAgainResponse{}`.

   Without explicit guidance, an agent might:

   * Hand-roll pattern matching on raw maps again, or
   * Ignore `FutureRetrieveResponse` entirely.

   **Suggested line under “Polling Loop”:**

   > After each successful `Tinkex.API.Futures.retrieve/2` call, convert the JSON map into a typed response using `Tinkex.Types.FutureRetrieveResponse.from_json/1`, and pattern match on the resulting struct type.

   That ensures you reuse the refactored types from 3A instead of duplicating logic.

2. **What exactly is a “failed with category :server → retries”?**

   Under tests you specify:

   * “Failed with category `:user` → no retry.”
   * “Failed with category `:server` → retries.”

   But there are *two* different “failure” layers:

   * HTTP-level failure → `{:error, %Tinkex.Error{}}` from `API.Futures.retrieve/2` (already handled by HTTP layer retries).
   * Future-level `"status" => "failed"` in the JSON body → `FutureFailedResponse`.

   Phase 3B is clearly intended to talk about the **FutureFailedResponse** case: the `error` object has a `category` we parse via `RequestErrorCategory.parse/1`.

   It would help to say, under “Polling Loop” or “Tests”:

   > For `"status": "failed"` responses:
   >
   > * Parse `error["category"]` with `RequestErrorCategory.parse/1`.
   > * If category is `:user`, do not retry—wrap in `%Tinkex.Error{type: :request_failed, category: :user}` and return `{:error, error}`.
   > * If category is `:server` or `:unknown`, treat it as retryable by the poll loop (backoff and retry), again wrapping failures as `Tinkex.Error` when giving up.

   Right now the test names assume this behaviour but the spec doesn’t state it explicitly.

3. **Relationship between `opts[:timeout]` and HTTP timeout**

   You specify:

   * `opts[:timeout]` is the *poll* timeout (total elapsed).
   * But the example call includes `timeout: http_timeout` passed to `retrieve/2`.

   It’s not yet clear:

   * Is `http_timeout` just `config.timeout`?
   * Is there a separate `opts[:http_timeout]`?

   To avoid guesswork, you could add:

   > Use `Keyword.get(opts, :http_timeout, config.timeout)` as the per-request HTTP timeout when calling `Tinkex.API.Futures.retrieve/2`. `opts[:timeout]` remains the total polling loop timeout.

   That pins down the “two timeouts” story.

4. **Test contracts could be slightly more precise**

   * For “TryAgainResponse with `queue_state: "paused_rate_limit"` (should sleep and log)” you might also mention that:

     * It should emit a queue state telemetry event, and
     * It should call the observer, if provided.
   * For “Failed with category `:server` → retries”, specify how many retries or at least that the poll loop eventually gives up and returns `{:error, Tinkex.Error}` after the timeout or some condition. Otherwise someone might accidentally implement an infinite loop.

5. **Return shape of the Task**

   This is clear in text, but for completeness:

   * You might add an explicit `@spec` in the prompt like:

     > `@spec poll(request_id | %{request_id: String.t()}, keyword()) :: Task.t({:ok, map()} | {:error, Tinkex.Error.t()})`

   That makes the expected result *type* explicit (e.g. the “result” is the decoded `result` map, not the whole `FutureCompletedResponse` struct).

   Right now “result” is a bit underspecified: is it the raw `result` map, a struct, or something else?

Overall, though, 3B is now in good shape; these are mostly clarity tweaks.

---

## Phase 3C – Metrics Reduction & Await Helpers

### Strong points

* ✅ **Input type for MetricsReduction is now aligned with the repo.**

  * `reduce/1` takes `[%ForwardBackwardOutput{}]` instead of generic maps.
* ✅ **First-chunk semantics are front and center.**

  * “Only metrics present in the first chunk should be reduced; extra later keys ignored” is highlighted multiple times.
* ✅ **Python parity is well described.**

  * Suffix-based reducers, weights from `loss_fn_outputs`, `:unique` semantics, unknown suffix → mean.
* ✅ **Await helpers intentionally separate timeouts.**

  * You explicitly say `poll/2` timeout and `await/2` timeout are separate concerns; `await/2` treats the task as a black box.

### Remaining gaps / clarifications

1. **Shape of `await_many/2`’s return values**

   You say:

   > `await_many/2` … returns list of results maintaining order.
   > Test: `await_many/2` preserves order and surfaces first error.

   But not:

   * Is the list `[{:ok, result} | {:error, Tinkex.Error}]`?
   * Or just `[result1, result2, ...]` and it raises on error?
   * Or does it short-circuit and return `{:error, error}` for the first error?

   Given the rest of the API, the most consistent would be:

   * Each Task itself returns `{:ok, result} | {:error, Tinkex.Error}` (from `poll/2`).
   * `await_many/2` returns a list of those values in the same order as the input `tasks`.

   And “surfaces first error” just means “if any Task returned `{:error, ...}`, you’ll see it at the appropriate index”.

   **Strongly recommend one explicit line:**

   > `await_many/2` should return a list of the underlying Task results (`{:ok, result}` or `{:error, %Tinkex.Error{}}`) in the same order as the input tasks; it must not raise on Task exits/timeouts.

2. **Where `combine_forward_backward_results/1` lives and its signature**

   You give two location options:

   * `Tinkex.Future.Combiner`
   * or a helper in `ForwardBackwardOutput`.

   That’s fine, but you don’t pin down the exact function signature. To make Phase 4’s integration unambiguous, consider:

   > Implement `Tinkex.Future.Combiner.combine_forward_backward_results/1` with:
   >
   > ```elixir
   > @spec combine_forward_backward_results([ForwardBackwardOutput.t()]) ::
   >         ForwardBackwardOutput.t()
   > ```
   >
   > TrainingClient in Phase 4 will depend on this exact function.

   Or, if you prefer it on the type module, say so explicitly (and drop the alternative).

3. **Where to keep `loss_fn_output_type` in the combined result**

   You say:

   * `combine_forward_backward_results(results)` → `%ForwardBackwardOutput{}`.
   * You specify how to combine `metrics` and `loss_fn_outputs`.

   But what about `loss_fn_output_type`?

   * All chunks should have the same `loss_fn_output_type` (per Python).
   * The combined result should almost certainly just pick the value from the first chunk (or assert they match).

   It’s worth adding:

   > The combined `%ForwardBackwardOutput{}` should:
   >
   > * Take `loss_fn_output_type` from the first chunk (and optionally assert all chunks agree).
   > * Flatten `loss_fn_outputs` from all chunks.
   > * Compute `metrics` via `Tinkex.MetricsReduction.reduce/1`.

4. **Error handling in `MetricsReduction`**

   You don’t need much here, but a tiny note could avoid weird behaviours:

   * What if `results` is empty? (Return `%{}` is fine.)
   * What if `total_weight` is 0? (Return 0.0 for means/slack maybe.)

   You could add:

   > If `results` is an empty list, `reduce/1` should return an empty map. For weighted reductions, if the total weight is 0, return `0.0` for that metric.

   That keeps implementations consistent.

Other than those, 3C is quite solid.

---

## Overall verdict

You’ve addressed almost all of the gnarly issues from the earlier version:

* Repo state & existing types are acknowledged.
* The arity / call-shape mismatch for `Futures.retrieve` is fixed.
* Backoff constants have one canonical source (the async model doc).
* Timeout semantics are coherently defined.
* QueueStateObserver wiring is clear and testable.
* MetricsReduction is now defined in terms of `ForwardBackwardOutput` structs with Python parity guarantees.

If you make the small clarifications around:

* `TryAgainResponse.from_map/1` vs `FutureRetrieveResponse.from_json/1` error propagation,
* explicit use of `FutureRetrieveResponse.from_json/1` inside the poll loop,
* the precise return shape of `await_many/2`, and
* how to handle `loss_fn_output_type` in the combiner,

these prompts will be in very good shape for “agent” consumption and for future you coming back to this work.
