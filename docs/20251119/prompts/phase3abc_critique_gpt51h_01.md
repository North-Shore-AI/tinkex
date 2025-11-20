Here’s a structured critique of the Phase 3A / 3B / 3C prompts, with specific notes about how they line up (or don’t) with the current `tinkex` repo and the port docs you included.

---

## 0. High-level take

Overall, the three phase prompts are impressively structured:

* Clear targets and timeboxes.
* Explicit file lists, deliverables, constraints, and acceptance criteria.
* Good integration with the port docs (00–07) and the existing HTTP / error / telemetry design.

But there are a few consistent issues:

1. **They assume a slightly different type layout than your current code** (esp. futures / try-again / queue state).
2. **Some behaviour is specified twice and differently** (poll backoff, queue-state handling, where retry logic lives).
3. **QueueStateObserver wiring is under-specified** (who implements it and how it’s passed in).
4. **Tests vs implementation tension around `Process.sleep/1`** in the polling loop.
5. **Subtle acceptance-criteria vs docs mismatches** (e.g., starting backoff, where TryAgain parsing happens).

I’ll go phase by phase, then suggest concrete tweaks.

---

## 1. Phase 3A: Futures Infrastructure

### 1.1 Alignment with the existing code

**Where it fits nicely:**

* You don’t yet have a `Tinkex.Future` module, so adding a skeleton in 3A and the loop in 3B works conceptually.
* The prompts correctly tie into:

  * `Tinkex.API.Futures` (already exists),
  * `Tinkex.Config` (already wired into `Tinkex.API`),
  * `Tinkex.Error` and `RequestErrorCategory`.

**Where it conflicts with current layout:**

* You already have **futures types**:

  ```elixir
  Tinkex.Types.FuturePendingResponse
  Tinkex.Types.FutureCompletedResponse
  Tinkex.Types.FutureFailedResponse
  Tinkex.Types.TryAgainResponse
  Tinkex.Types.FutureRetrieveResponse.from_json/1
  ```

  all defined in `tinkex/types/future_responses.ex`.

* Phase 3A asks for a new `lib/tinkex/types/try_again_response.ex` and a new `Tinkex.Types.QueueState` module, but:

  * `Tinkex.Types.TryAgainResponse` already exists.
  * It already embeds `queue_state` as an atom and exposes `parse_queue_state/1`.

  So the prompt, as written, would cause **module duplication and/or refactors** rather than a greenfield implementation.

* The 3A acceptance criteria say:

  > `Tinkex.Types.QueueState.parse/1` covers all documented states + unknown.

  Right now `parse_queue_state/1` in `TryAgainResponse` maps unknown strings to `:active`, not `:unknown`. So this prompt **implicitly changes behaviour**, but doesn’t call that out as a change or ask for regression tests around the old behaviour.

**Concrete recommendation:**

Rewrite 3A’s file list and deliverables to **explicitly refactor** the existing code instead of “adding new”:

* Instead of “create `try_again_response.ex`”, say:

  > Extract `Tinkex.Types.TryAgainResponse` from `tinkex/types/future_responses.ex` into its own file, keeping the public API the same, then extend it with `from_map/1`.

* Instead of defining queue state only inside `TryAgainResponse`, say:

  > Introduce `Tinkex.Types.QueueState` and move queue‐state parsing logic out of `TryAgainResponse.parse_queue_state/1` into `QueueState.parse/1`. Update `FutureRetrieveResponse.from_json/1` to use the new module.

And explicitly call out that unknown states become `:unknown`, with a test that catches the change, so it’s clearly intentional.

---

### 1.2 TryAgainResponse API shape

The prompt asks for:

> `Tinkex.Types.TryAgainResponse` with `type`, `queue_state`, `retry_after_ms`
> Provide `from_map/1` helper returning `%TryAgainResponse{}` or `{:error, reason}`.
> “JSON decoding tests for TryAgainResponse (case-insensitive when mapping from API maps).”

But in your repo **JSON decoding already happens via**:

```elixir
Tinkex.Types.FutureRetrieveResponse.from_json/1
```

which:

* Branches on `"type" => "try_again"` and
* Constructs %TryAgainResponse{} directly.

So there are two possible designs:

1. **Centralize decoding in `FutureRetrieveResponse.from_json/1`** (status/type → typed struct), and have `TryAgainResponse` be a plain struct.
2. **Let `TryAgainResponse.from_map/1` do its own normalization** and have `FutureRetrieveResponse.from_json/1` delegate.

Right now you’re doing (1). The prompt implicitly wants (2), but **doesn’t say to update `FutureRetrieveResponse.from_json/1`**, so the agent could easily:

* Add `from_map/1`, but never use it.
* Or worse, introduce a second decoding code path.

**Recommendation:**

* Make the desired flow explicit:

  > Update `Tinkex.Types.FutureRetrieveResponse.from_json/1` to call `TryAgainResponse.from_map/1` for `"type" => "try_again"` variants. Add tests for this decoding path.

* Or, if you prefer to keep decoding central, drop `from_map/1` entirely and instead:

  > Extend `FutureRetrieveResponse.from_json/1` tests to assert:
  >
  > * case-insensitive handling of `"type"` and `"queue_state"`,
  > * correct atom mapping for queue states,
  > * propagation of `retry_after_ms`.

Right now the prompt asks for `from_map/1`, but nothing really needs it.

---

### 1.3 Future skeleton & behaviour

3A wants:

* `Tinkex.Future.poll/2` signature and internal state struct, but “no loop yet”.
* A QueueState telemetry helper.
* `@behaviour Tinkex.QueueStateObserver` declaration.

Issues:

1. **Return type consistency across phases**

   3A’s acceptance criteria only say:

   > `Tinkex.Future` module compiles with public `poll/2` (even if returning `{:error, :not_impl}` for now)

   3B then says:

   > `Tinkex.Future.poll/2` returns `Task.t({:ok, result} | {:error, Tinkex.Error.t()})`.

   That’s a different contract. If 3A’s skeleton returns a bare `{:error, :not_impl}`, 3B will later have to change the return type entirely, which is fine but confusing for an “agent” reading only one prompt.

   **Better**: lock the signature in 3A:

   * “`poll/2` must return a `Task.t`, even if the Task body is currently just `fn -> {:error, :not_impl} end`.”

2. **QueueStateObserver placement is vague**

   3A says:

   > `@behaviour Tinkex.QueueStateObserver` declaration (optional callbacks).

   3B then introduces `lib/tinkex/queue_state_observer.ex` as a new behaviour module. Later, 3C says “Finalize queue-state observer wiring”.

   What’s not clear is:

   * Does `Tinkex.Future` itself implement the behaviour?
   * Or is `Tinkex.Future` supposed to *call* an observer provided via `opts[:observer]`?
   * Or are `TrainingClient` / `SamplingClient` the observers, and Future just broadcasts telemetry?

   Without that, agents could easily put `@behaviour Tinkex.QueueStateObserver` in the wrong place.

   **Recommendation**: spell out the contract:

   * E.g.:

     > `Tinkex.Future.poll/2` accepts `opts[:observer]` implementing `Tinkex.QueueStateObserver`. When queue state changes, it calls `observer.on_queue_state_change(queue_state_atom)` and emits telemetry.

   Or explicitly say:

   > `Tinkex.Future` does *not* implement `Tinkex.QueueStateObserver`. It only emits telemetry. TrainingClient/SamplingClient will implement the behaviour in Phase 4.

---

### 1.4 Telemetry details

3A says:

* Emit `[:tinkex, :queue, :state_change]` with `%{queue_state: atom}` metadata.
* Add a doc snippet describing Training/Sampling clients implementing the observer.

Given you already have a pretty rich telemetry story (`[:tinkex, :http, :request, ...]` etc.), a couple of small gaps:

* It doesn’t say whether `queue_state` goes in **measurements** or **metadata**. You default it to metadata in the text, but the wording is easy to misread.
* It doesn’t say if you want to deduplicate events (emit only when the state actually changes vs every poll). The heading says “QueueState telemetry helper (state_change)”, which suggests change-only events, but the specifics are silent.

You probably want something like:

> The helper should only emit an event when the queue state transitions from one atom to another. The state should be stored in the Future’s internal struct to allow comparison.

Otherwise an agent may fire an event on every `TryAgainResponse`, which could be noisy.

---

## 2. Phase 3B: Polling Engine & Queue Backpressure

This is the most subtle phase because it touches concurrency, error handling, and retry semantics.

### 2.1 Polling loop spec vs docs & HTTP layer

3B says:

> Exponential backoff for pending/poll errors: 500ms start, cap 30s.

In `03_async_model.md`, the example for polling backoff uses:

* 1s, 2s, 4s, … with some iteration math, capped at 30s.

In `04_http_layer.md`, HTTP retries use:

* `@initial_retry_delay 500` ms, cap 8s.

So you now have **three different backoff stories**:

1. HTTP layer (`Tinkex.API`) → 500ms base, 8s cap.
2. Async doc example → 1s base, 30s cap.
3. Phase 3B prompt → 500ms base, 30s cap.

That’s not catastrophic, but if the target is “parity with Python SDK”, you should pick one and say so explicitly. Otherwise future you will be wondering which one is “the truth” for Future polling.

**Suggestion:**

Decide on **one** (probably the one in `03_async_model.md` or 3B) and add a line to the prompt like:

> Use the same backoff constants as documented in `docs/20251119/port_research/03_async_model.md` (start 1_000 ms, cap 30_000 ms) to match Python’s behaviour.

or vice-versa: explicitly say that Future polling uses a slightly different backoff than HTTP retries, and why (e.g., to slow down queue polling).

---

### 2.2 API.Futures signature mismatch

3B says:

> Loop calls `/api/v1/future/retrieve` via `Tinkex.API.Futures.retrieve/3`.

In the repo, `Tinkex.API.Futures.retrieve/2` is:

```elixir
@spec retrieve(map(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
def retrieve(request, opts) do
  Tinkex.API.post("/api/v1/future/retrieve", request, Keyword.put(opts, :pool_type, :futures))
end
```

So the prompt is off by arity, and doesn’t mention that `opts` must contain `:config`.

That’s a tiny thing for a human, but for an “agent prompt” it matters. I would rephrase:

> Call `Tinkex.API.Futures.retrieve(%{request_id: request_id}, config: config, timeout: http_timeout)` and rely on its existing signature (request map + opts keyword list).

It’s a one-line fix, but it prevents the agent from inventing a non-existent `retrieve/3`.

---

### 2.3 Timeout semantics & Tinkex.Error

3B says:

> Timeout support: `opts[:timeout]` (ms). If elapsed exceeds, return `{:error, timeout}`.
> Test 6: Timeout reached → `{:error, %Tinkex.Error{type: :api_timeout}}`.

So the text and tests are slightly out of sync:

* One says `{:error, timeout}` (bare atom? plain reason?),
* The other expects a `Tinkex.Error` struct with `type: :api_timeout`.

Given your existing error module (`Tinkex.Error.new/3`, `type` + `status` + `data`), you definitely want the latter.

**Recommendation:**

* In the **Features** section, change the spec to:

  > If elapsed exceeds `opts[:timeout]`, return `{:error, %Tinkex.Error{type: :api_timeout}}`.

* Also specify what `timeout` default should be (`:infinity` vs `config.timeout` vs explicit value) so agents don’t guess.

3C’s `Future.await/2` also wraps `Task.await` timeouts into `Tinkex.Error{type: :api_timeout}`, so those two need to agree.

---

### 2.4 QueueStateObserver wiring

3B introduces a new file:

```text
lib/tinkex/queue_state_observer.ex     # optional behaviour (new)
```

and says:

> Optional callback invoked when queue state transitions.

But it never states **how** that observer is chosen or passed in, e.g.:

* `opts[:observer]` in `poll/2`?
* A global per-client observer in training/sampling clients?
* A single global module attribute somewhere?

Given 03_async_model’s suggestion that TrainingClient and SamplingClient may implement the behaviour, a reasonable design is:

* `Tinkex.Future.poll(request_id, observer: observer)` where `observer` implements `c:on_queue_state_change/1`.
* Poll loop calls `observer.on_queue_state_change(queue_state_atom)` when it observes a new queue state, and also emits telemetry.

But the prompt doesn’t say that. As an “agent prompt”, it leaves too much room for incompatible interpretations.

**Suggestion:**

Add 2–3 explicit sentences, e.g.:

> `Tinkex.Future.poll/2` should accept an optional `opts[:queue_state_observer]` implementing `Tinkex.QueueStateObserver`. When the queue state changes, the poll loop MUST:
>
> * emit telemetry,
> * call `observer.on_queue_state_change(new_state)` if the observer is present.

And, if you want to avoid wiring that in 3B, move “Observer behaviour” into 3C instead of 3B, or make 3B only define the behaviour module without actually using it.

---

### 2.5 Tests vs Process.sleep

You explicitly say:

> No `Process.sleep/1` in tests—use counters or `System.monotonic_time` assertions with small delays (0ms/5ms). Use Mox or Bypass to track call counts.

That’s good, but the polling loop itself will absolutely have `Process.sleep` calls (for backoff). So tests that invoke the real `poll/2` with real delays will be slow and flaky.

The prompt doesn’t give the agent a way out, e.g.:

* Inject a `:sleep_fun` / `:timer` into `opts` so tests can stub it out.
* Or use a backoff function that can be overridden in the tests.

Without that, the instruction “no Process.sleep in tests” and the requirement “backoff with Process.sleep in implementation” are a bit at odds.

**Suggestion:**

Add something like:

> Design the poll loop so that the sleeping function can be overridden via `opts[:sleep_fun]` (defaults to `&Process.sleep/1`). Tests should pass a sleep function that records calls or uses a very small delay (e.g., 0–1 ms) to avoid slow tests.

That gives a clear, testable injection point.

---

## 3. Phase 3C: Metrics Reduction & Await Helpers

This phase is mostly aligned with the port docs and not yet implemented in the repo, so it’s in better shape.

### 3.1 MetricsReduction vs existing types

You already have `Tinkex.Types.ForwardBackwardOutput` with:

* `loss_fn_output_type :: String.t()`
* `loss_fn_outputs :: [map()]`
* `metrics :: %{String.t() => float()}`

Phase 3C says:

> `MetricsReduction.reduce/1` must accept list of maps with keys `:metrics` and `:loss_fn_outputs`.

That’s fine, but not quite aligned with your type — your *natural* input will be `[ForwardBackwardOutput.t()]`, not `[ %{metrics: ..., loss_fn_outputs: ...} ]`.

And in `03_async_model.md` you already sketched an implementation that takes full structs and then accesses `r.metrics` and `r.loss_fn_outputs` directly.

**Recommendation:**

Change the spec to:

> `MetricsReduction.reduce/1` accepts a list of `%ForwardBackwardOutput{}` structs (or at least something that responds to `:metrics` and `:loss_fn_outputs`). Use only `metrics` keys present in the first element; ignore metrics missing in later chunks.

That avoids an unnecessary intermediate shape.

### 3.2 Reduction semantics

The prompt’s spec is consistent with your docs:

* `:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`.
* Weighted mean by number of `loss_fn_outputs` per chunk.
* Unknown suffix → treat as mean.

There’s just one subtlety that’s **critical** and should be explicitly highlighted in the prompt (it is hinted in 07_porting_strategy, but not in the 3C text):

> Only metrics present in the **first chunk** should be reduced; keys missing in later chunks are ignored for that key, not treated as zero.

You already call this out under Constraints:

> Align metrics map key handling with Python: only metrics present in first chunk considered, ignore keys missing in later chunks.

But it’s under Constraints vs the main bullet list; for an agent, it’s easy to miss. I’d move that up into the Features section with a bold “Python parity” note.

### 3.3 Await / await_many helpers

The spec is good:

* `Future.await(task, timeout \\ :infinity)` wraps `Task.await/2` and turns exits/timeouts into `%Tinkex.Error{type: :api_timeout}`.
* `await_many/2` returns list of results in order and surfaces first error.

But given 3B also has a timeout concept inside `poll/2`, you want to be explicit about **who is responsible** for which timeout:

* `poll/2`’s `opts[:timeout]` → total polling time, independent of Task.await.
* `Future.await(task, timeout)` → how long caller will wait for the Task process; could be different from the poll timeout.

Right now the prompts don’t say whether those timeouts are expected to be the same; this can lead to weird “double timeout translation” if someone sets both.

**Suggestion:**

Add one clarifying line:

> `Future.await/2` should treat the task as an opaque black box: it must not attempt to compute or enforce the poll timeout itself. `poll/2`’s `opts[:timeout]` governs how long the loop runs; `await/2` only governs how long the caller is willing to wait on the Task.

That keeps concerns separated.

---

## 4. Cross-phase / meta issues

### 4.1 “Standalone prompt” vs repo state

Each phase prompt says:

> This prompt is standalone—include all necessary context and commands.

but also:

* Phase 3B: Prereq = Phase 3A complete.
* Phase 3C: Prereq = 3A + 3B complete.

For a human, that means “fresh ChatGPT context, but same repo with previous phases merged”. For an agent, it’s ambiguous — they might think they’re starting from the round-0 repo every time.

You can reduce confusion by making the assumption explicit at the top of each:

> Assume the repository already includes all changes from Phase 3A (respectively 3A+3B).

Right now, the presence of `Tinkex.Types.TryAgainResponse` and `FutureRetrieveResponse` in the repo makes that assumption especially important — otherwise an agent might try to recreate what’s already there.

### 4.2 Division of labour between HTTP retries and Future polling

* HTTP layer (`Tinkex.API`) already does retries on 5xx / 408 / 429 with `x-should-retry` semantics.
* Phase 3B adds its own “retry pending, poll errors” logic at the future level.

That’s intended: HTTP retries for transient transport / status issues, Future retries for “operation not done yet” semantics.

I’d still add a one-liner in 3B:

> `Tinkex.Future.poll/2` must not duplicate HTTP-level retry logic; it should treat each call to `Tinkex.API.Futures.retrieve/2` as a single attempt and only handle retrying on pending / TryAgain / polling-level errors, letting the HTTP layer manage connection retries and 5xx/408/429 behaviour.

This prevents someone from accidentally wrapping `with_retries` around `retrieve/2` inside `poll/2` again.

---

## 5. Suggested small edits (summary)

If you want a quick checklist of the most impactful tweaks:

1. **Phase 3A**

   * Rewrite “create new TryAgainResponse module” into “extract/refactor existing `Tinkex.Types.TryAgainResponse` from `future_responses.ex`.”
   * Introduce `Tinkex.Types.QueueState` and migrate `parse_queue_state/1` into it, making the change to `:unknown` explicit and tested.
   * Fix `poll/2` signature to return `Task.t` even in 3A’s stub.
   * Clarify QueueStateObserver: do *not* put `@behaviour` in `Tinkex.Future` unless you really mean “Future itself is an observer”.

2. **Phase 3B**

   * Correct `Tinkex.API.Futures.retrieve/3 → /2` and explicitly pass `config: config`.
   * Make timeout semantics match tests: `{:error, %Tinkex.Error{type: :api_timeout}}`.
   * Pick a single polling backoff scheme and tie it to `03_async_model.md`.
   * Clarify how `queue_state_observer` is passed to `poll/2`.
   * Mention injectable sleep / backoff for tests so “no Process.sleep in tests” is achievable.

3. **Phase 3C**

   * Change `MetricsReduction.reduce/1` input from “list of maps” to “list of `%ForwardBackwardOutput{}`”.
   * Promote the “first chunk’s metrics define the metric set” constraint up into the main feature bullets.
   * Clarify that `await/2`’s timeout is separate from `poll/2`’s and doesn’t enforce poll behaviour.

If you’d like, I can take one of these phases (say 3A) and rewrite it concretely to match the current repo and docs, so you have a “drop-in corrected version” for future agents.
