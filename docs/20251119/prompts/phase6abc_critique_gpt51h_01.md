These are pretty nice “integration week” prompts. At this point you’re mostly stitching together pieces you already specified, and the prompts mostly reflect that. There *are* a few subtle mismatches and places where an implementer could quietly undo earlier design decisions, though.

I’ll go through 6A, 6B, 6C.

---

## Phase 6A – End-to-End Training Loop

### What’s working well

* Clear vertical slice: ServiceClient → TrainingClient → `forward_backward` → `optim_step` → `save_weights_for_sampler`.
* You explicitly want:

  * A real integration test module (not just unit tests).
  * Everything routed through public APIs (no direct `GenServer.call/3`).
* Required reading list is on point: training/client docs, async model, HTTP endpoints, and tokenization.

### Things to tighten

1. **Application / supervision startup**

   For an integration test that goes through ServiceClient and TrainingClient, you’ll need:

   * `Tinkex.Application` running (Finch, ETS tables, SessionManager, ClientSupervisor, etc.).

   Right now the prompt doesn’t say whether tests should:

   * Call `Application.ensure_all_started(:tinkex)`, or
   * Start specific supervisors (Finch, ClientSupervisor, SessionManager) manually in the test.

   If you want these to be *true* integration tests, I’d add a line like:

   > In `training_loop_test.exs`, start the application (`Application.ensure_all_started(:tinkex)`) so Finch, ETS, SessionManager, and supervisors are running before invoking ServiceClient.

2. **“Assert queue states” is underspecified**

   Under Tests:

   > Assert queue states, metrics reduction, etc., by checking the final returned structs.

   Metrics reduction: yes, `ForwardBackwardOutput.metrics` is visible. Queue state, not so much:

   * Queue state is surfaced via telemetry and `Tinkex.Future`’s polling and `QueueStateObserver`, not via the final `ForwardBackwardOutput` struct.

   Unless you plan to stuff queue state into a field (you haven’t specified that anywhere), I’d drop “queue states” from this bullet or change it to:

   > Assert metrics reduction via the final `ForwardBackwardOutput`; queue-state behaviour is already covered by Phase 3B tests and telemetry.

3. **Handling `save_weights_for_sampler/2`**

   You correctly say “if implemented; stub response otherwise.” It might help to suggest the exact “stub” approach:

   * Either Bypass returns a minimal JSON body and the client returns `{:ok, map}`.
   * Or you allow `save_weights_for_sampler/2` to be a no-op in the integration test, as long as the call flows successfully.

   Otherwise someone might be tempted to leave it out entirely, and the vertical slice wouldn’t actually hit that endpoint.

4. **Performance hooks vs determinism**

   You say:

   > Performance hooks – add timer/logging snippet (mocked if using Bypass).

   Good idea, but make sure you keep this out of the test’s *assertions*. A tiny note like:

   > Performance logging should be informational only; tests must not assert on exact timings.

   would guard against brittle “must finish under X ms” assertions.

Overall 6A is in solid shape with minor clarifications.

---

## Phase 6B – Sampling Workflow & Concurrency

### Good stuff

* Clear objective: ServiceClient → SamplingClient → `sample`, plus concurrency and error recovery.

* Required reading points back to:

  * SamplingClient architecture (ETS + RateLimiter).
  * Error semantics for 429/user/server.
  * Sampling endpoint docs.

* Deliverables line up with Phase 4C’s design:

  * Integration tests that go through the actual `SamplingClient.sample/4` API.
  * RateLimiter behaviour under 429.
  * Docs about concurrency usage.

### Important mismatches / ambiguities

1. **HTTP retry logic vs SamplingClient decisions**

   You say under Error Recovery Tests:

   > 5xx response uses HTTP retry logic.

   But earlier (Phase 4 / HTTP layer / Sampling design) you intentionally set sampling to:

   * Use `Tinkex.API.Sampling.sample_async/2` with `max_retries: 0` (no HTTP retries).
   * Have SamplingClient handle 429 via RateLimiter but *not* automatically retry.

   If you now require 5xx to “use HTTP retry logic” in the sampling path, that conflicts with:

   * The existing `Sampling` API test that asserts `max_retries` is 0.
   * The design decision to keep sampling lightweight and let callers handle retries.

   I’d either:

   * Change this bullet to:

     > 5xx responses from the sampling endpoint should surface as `{:error, %Tinkex.Error{type: :api_status}}` without automatic retries; HTTP retry logic remains disabled for sampling (as specified in earlier phases).

   * Or, if you really want sampling retries now, explicitly update the earlier phases’ spec and tests to say sampling uses the same `with_retries/5` semantics as training.

   Right now the prompts disagree.

2. **RateLimiter “prevents race” wording**

   > Concurrency test: spawn multiple sampling tasks (simulate 20-50 requests) using ETS state; ensure RateLimiter prevents race.

   RateLimiter doesn’t “prevent race” in the general sense; it only gates requests *after* a 429 with a `retry_after_ms`. Rapid sampling calls with no 429 should all proceed.

   More precise:

   > Concurrency test: spawn multiple sampling tasks and ensure that once a 429 with `retry_after_ms` is received, subsequent calls respect the backoff (do not immediately hit Bypass until backoff expires).

   And then you can separately verify ETS state isn’t corrupted under concurrency.

3. **Queue state / telemetry mention**

   Under Constraints & Guidance:

   > Logging/telemetry: confirm queue state events (if any) are emitted (can attach simple telemetry handler in test).

   Queue-state telemetry is associated with the **Future poll loop** (training / futures), not the sampling path (which hits `/asample` directly). Unless you have some separate queue-state signalling for sampling (not documented so far), this may confuse things.

   I’d either:

   * Drop “queue state” here and just say:

     > Optionally attach a telemetry handler to confirm `[:tinkex, :http, :request, :start/stop]` events for sampling.

   or explicitly call out you’re just checking HTTP telemetry, not queue-state.

4. **Starting the application**

   Same comment as 6A: these integration tests should either:

   * Ensure `Tinkex.Application` is started, or
   * Manually start `Finch`, ETS tables, `SamplingRegistry`, etc.

   Adding a line like:

   > In `sampling_workflow_test.exs`, ensure `:tinkex` is started (`Application.ensure_all_started(:tinkex)`) so supervised components (Finch, ETS tables, SamplingRegistry) are running.

   keeps everyone on the same page.

Other than those, 6B is conceptually aligned with your earlier SamplingClient design.

---

## Phase 6C – Multi-Client Concurrency & Telemetry

### Strong parts

* This is exactly the “shake it hard” phase you want:

  * Two ServiceClients with different configs.
  * Training + sampling running concurrently.
  * rate-limiter behaviour under 429.
  * HTTP retries under 5xx.
* You explicitly include:

  * Config isolation (RateLimiter keyed by `{base_url, api_key}`).
  * Telemetry integration (attach handler, maybe `Tinkex.Telemetry.attach_logger/0`).

### Subtleties / minor tweaks

1. **Clarify which paths are expected to retry 5xx**

   For 5xx, we now have:

   * Training / futures → HTTP `with_retries/5` should retry 5xx and 408/429, per earlier docs.
   * Sampling → as discussed in 6B, likely **no HTTP retries** (unless you decide otherwise).

   In 6C’s “Error Recovery Coverage” you say:

   > 5xx retry behavior (HTTP layer) triggered.

   I’d clarify that this is specifically validating the training/future path:

   > For training / future polling, simulate 5xx responses and ensure the HTTP layer’s retry behaviour (`with_retries/5`) is exercised. Sampling continues to use `max_retries: 0` and should not auto-retry 5xx (unless Phase 6B changed that explicitly).

2. **Config isolation vs ETS tables**

   > Provide config isolation test (two configs, ensure ETS entries separate).

   This is good; I’d just be a bit more explicit:

   * For RateLimiter: there should be different atomics for `{base_url_a, api_key_a}` and `{base_url_b, api_key_b}`.
   * For SamplingClient entries: `:tinkex_sampling_clients` should have distinct `{:config, pid}` entries for clients spawned from different configs.

   That way your tests can assert specifics (e.g., `:ets.lookup(:tinkex_rate_limiters, {:limiter, {normalized_url, api_key}})` returns distinct entries).

3. **Telemetry “dashboard” scope**

   You say:

   > Provide script/README snippet showing how to attach telemetry handler or export metrics to console (even if simulated). Optional: add `Tinkex.Telemetry.attach_logger/0` helper.

   That’s very achievable and matches the earlier telemetry spec. Just make sure not to oversell “dashboard” here; what you’re really asking for is:

   * A helper to attach a basic handler that logs events or aggregates metrics.
   * Instructions/snippet, not a full Grafana/dashboard integration.

   The prompt text basically says that already but “dashboard” may set expectations a bit high for this phase.

4. **Using `Supertester` vs plain `Task.async_stream`**

   You mention:

   > Use `Task.async_stream` or `Supertester` harness if available.

   Given your repo already uses `Supertester` for concurrency tests in Phase 2 HTTP tests, this is a good callout. Nothing to fix here; just noting this is nicely aligned.

---

## Overall

These Phase 6 prompts are doing the right thing:

* They build on the earlier phased design rather than introducing new behaviours.
* They force you to verify:

  * Training and sampling flows working end-to-end.
  * Retry vs no-retry semantics.
  * RateLimiter behaviour.
  * Config isolation.
  * Telemetry visibility.

The main corrections I’d make:

* In 6B/6C, be explicit that **sampling** continues to use `max_retries: 0` (no HTTP retries) unless you’re consciously changing that design.
* Clarify that queue-state telemetry belongs to the future-poll/training path, not sampling.
* Make it explicit in each integration test that `:tinkex` needs to be started so the application tree (Finch, ETS, registries, supervisors) is available.

Once those are adjusted, the Phase 6 prompts will be as implementable (and self-consistent) as the earlier phases you’ve been iterating on.
