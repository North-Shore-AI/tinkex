These are in really good shape now. They line up with the existing repo, close the earlier gaps, and are very “agent-friendly”. I’ll still nitpick a few last details, but they’re minor.

I’ll go phase by phase.

---

## Phase 3A – Futures Infrastructure

### What’s solid

* ✅ **Repo state + refactor framing** are clear:

  * You explicitly say `TryAgainResponse` and `FutureRetrieveResponse` already live in `future_responses.ex`, and this phase is extraction/refactor, not greenfield.
* ✅ **QueueState behaviour change** is explicit and tested:

  * New `QueueState.parse/1` returns `:active | :paused_rate_limit | :paused_capacity | :unknown`.
  * You call out the breaking change (unknown → `:unknown`) and require a test.
* ✅ **`TryAgainResponse.from_map/1` contract is now clean**:

  * Returns `%TryAgainResponse{}` directly.
  * Handles atom/string keys and case-insensitive values.
  * You clarified *why* it returns just the struct (to keep `FutureRetrieveResponse.from_json/1` returning only union structs).
* ✅ **Delegation is nailed down**:

  * `FutureRetrieveResponse.from_json/1` must delegate to `TryAgainResponse.from_map/1` for `"type" => "try_again"`.
* ✅ **Future skeleton contract is fixed early**:

  * Spec + stub: `poll/2 :: Task.t({:ok, map()} | {:error, Tinkex.Error.t()})` with `Task.async(fn -> {:error, :not_implemented} end)`.
* ✅ **Queue-state telemetry helper is precisely located and behaved**:

  * Private helper in `Tinkex.Future`.
  * Emits `[:tinkex, :queue, :state_change]` with metadata `%{queue_state: atom}`.
  * Emits only on transitions, and the internal state must track previous queue state.
* ✅ **Future vs observer separation is explicit**:

  * “Future does *not* implement `QueueStateObserver`.”

### Tiny things you might still tweak

1. **Retiring the old `parse_queue_state/1`**

   You say “extract from existing `parse_queue_state/1` logic” but don’t explicitly say “and remove/deprecate the old `TryAgainResponse.parse_queue_state/1`”. Without that note, a future reader could wonder why both exist.

   A one-liner like:

   > After extracting `QueueState.parse/1`, remove or deprecate `TryAgainResponse.parse_queue_state/1` to avoid duplicated parsing logic.

   would close that loop.

2. **How strict `from_map/1` should be on malformed input**

   You say:

   > `from_map/1` should return `%TryAgainResponse{}` directly (raise or log on malformed input).

   That’s fine, but it might help to hint what “malformed” means (e.g. missing `request_id`, missing `queue_state`, wrong type) and whether tests should cover at least one bad-input case. Not required, but helpful if an agent is being very literal.

Outside of that, 3A looks very coherent.

---

## Phase 3B – Polling Engine & Queue Backpressure

### What’s working well

* ✅ **Signature and result shape are pinned down:**

  ```elixir
  @spec poll(String.t() | %{request_id: String.t()}, keyword()) ::
          Task.t({:ok, map()} | {:error, Tinkex.Error.t()})
  ```

  And “result” is clearly the `result` map from a completed response, not the whole struct.

* ✅ **Correct API call & config threading**:

  * Uses `Tinkex.API.Futures.retrieve/2` with `config: config` and `timeout: http_timeout`.
  * Per-request HTTP timeout from `Keyword.get(opts, :http_timeout, config.timeout)`.
  * Poll timeout from `opts[:timeout]` (separate concern).

* ✅ **Typed responses are mandatory**:

  * After each successful `retrieve/2`, you must call `FutureRetrieveResponse.from_json/1` and pattern-match on `%FuturePendingResponse{}`, `%FutureCompletedResponse{}`, `%FutureFailedResponse{}`, `%TryAgainResponse{}`.
  * This reuses the 3A refactor instead of duplicating map logic.

* ✅ **HTTP vs poll-level retries are cleanly separated**:

  * “Do not wrap `retrieve/2` in additional retry logic” + “Always use `FutureRetrieveResponse.from_json/1`”.
  * Poll loop only handles pending / try-again / failed-category semantics; API handles transport/5xx/408/429.

* ✅ **FutureFailedResponse handling is finally explicit**:

  * Parse `error["category"]` via `RequestErrorCategory.parse/1`.
  * `:user` → no retry, return `{:error, %Tinkex.Error{type: :request_failed, category: :user, ...}}`.
  * `:server` / `:unknown` → retry with backoff, eventually return `:request_failed` error when giving up.

* ✅ **TryAgainResponse + queue state are fully integrated**:

  * Use the typed `%TryAgainResponse{}` (queue state already parsed to atom via 3A).
  * Sleep 1s or `retry_after_ms`.
  * Emit telemetry and call observer on state transitions.

* ✅ **Backoff/timeout story is now coherent**:

  * Backoff: 1s–2–4–8–16–30–30–… as per `03_async_model.md`.
  * Poll timeout: `opts[:timeout]`, default `:infinity`, error is `%Tinkex.Error{type: :api_timeout}`.
  * HTTP timeout: `opts[:http_timeout]` or `config.timeout`.

* ✅ **Observer behaviour & testable sleep** are spec’d in detail.

### Small remaining rough edges

1. **“Timeout or max retries exhausted” vs no defined max retries**

   In the FutureFailedResponse section:

   > After timeout or max retries exhausted, return `{:error, %Tinkex.Error{...}}`.

   But nowhere in 3B do you define a numeric “max retries” or “max attempts” for the poll loop—only a time-based timeout and backoff.

   As written, an implementer will probably only use the timeout and ignore “max retries”, which is slightly confusing.

   You can fix this either by:

   * Removing “or max retries exhausted”, and making the poll timeout the only stop condition:

     > After the poll timeout is reached, return `{:error, %Tinkex.Error{...}}`.

   or by defining a concrete limit, e.g.:

   > Optionally also stop after `opts[:max_attempts]` (default: `:infinity`) attempts.

2. **Clarify that failed-category logic is for the *Future* layer**

   The text implies it, but you could add one phrase to make it completely unambiguous:

   > For `%FutureFailedResponse{}` (i.e., `"status": "failed"` in the JSON body), …

   just so nobody confuses it with HTTP status failures (which `Tinkex.API` already turns into `{:error, %Tinkex.Error{type: :api_status, ...}}`).

Everything else in 3B now reads tight and consistent.

---

## Phase 3C – Metrics Reduction & Await Helpers

### Strong parts

* ✅ **Input type & API shape are now fully aligned:**

  * `MetricsReduction.reduce/1` takes `[%ForwardBackwardOutput{}]`.
  * Combiner is `Tinkex.Future.Combiner.combine_forward_backward_results/1` with a precise spec.

* ✅ **Python parity is heavily emphasized:**

  * First chunk defines metric set.
  * Missing keys in later chunks are ignored (not treated as zero).
  * Suffix-based reducers (`:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`).
  * Weighted mean by `length(loss_fn_outputs)` per chunk.
  * Unknown suffix → mean.

* ✅ **Edge cases are covered:**

  * Empty results → `%{}`.
  * Zero total weight → `0.0`.

* ✅ **Combiner behaviour is well specified:**

  * `loss_fn_output_type` is taken from first chunk (and tests confirm behaviour).
  * `loss_fn_outputs` flattened.
  * `metrics` via `MetricsReduction.reduce/1`.

* ✅ **Await / await_many semantics are explicit and consistent:**

  * `Future.await/2` wraps `Task.await/2`, converts exits/timeouts into `%Tinkex.Error{type: :api_timeout}`.
  * `Future.await_many/2`:

    * returns a list of `{:ok, result}` or `{:error, %Tinkex.Error{}}`,
    * preserves order,
    * must not raise—convert Task exits/timeouts into error tuples.
  * Clear separation of responsibilities between `poll/2` timeout and `await/2` timeout.

### Very minor suggestions

1. **What to do on mismatched `loss_fn_output_type`**

   You say:

   > Take `loss_fn_output_type` from the first chunk (optionally assert all chunks agree).

   If you want implementations to be deterministic, you could suggest one default behaviour, for example:

   * “In dev/test, you *may* raise if types disagree; in prod, log and take the first.”

   But that’s optional; the current wording is acceptable as long as TrainingClient doesn’t depend on the assertion.

2. **`await_many/2` implementation note**

   You already say “must not raise” and “convert Task exits/timeouts to errors”, which is enough for an implementer. If you wanted to be super explicit you could hint that `Task.await_many/2` raises on failure and they should wrap it in `try/rescue`, or call `Task.await/2` per task—but this is more commentary than a spec requirement.

---

## Bottom line

These prompts are now:

* Internally consistent across 3A–3C.
* Consistent with the existing codebase (types, API, error/telemetry design).
* Concrete enough that an “agent” implementation won’t need to guess at arities, result shapes, or who owns which timeout/retry logic.

If you clean up that one “max retries” phrase in 3B (or define it explicitly), you’re essentially at “ready to run” spec quality.
