These look really tight now. You’ve ironed out the big inconsistencies from earlier phases, and 6A–6C mostly just read as “plug all the pieces together and shake them.” I’ll still nitpick a bit, but it’s mostly small clarifications rather than structural issues.

---

## Phase 6A – End-to-End Training Loop

### What’s working well

* The vertical slice is clear:
  `ServiceClient.start_link` → `create_lora_training_client` → `forward_backward` → `optim_step` → `save_weights_for_sampler`.
* You now explicitly require:

  * A dedicated integration test module using Bypass.
  * `Application.ensure_all_started(:tinkex)` so Finch, ETS, SessionManager, supervisors, etc. are all running.
* The way you handle `save_weights_for_sampler/2` is sensible:

  * If it exists, stub it with a minimal JSON response and expect `{:ok, map}`.
  * Else allow a no-op call that still flows through the stack.
* You correctly frame performance hooks as **informational only**:

  * Time measurement/logging, but no assertions on timing.

### Small suggestions

1. **Be explicit about Task usage**

   You say “Ensure tasks return `{:ok, result}` and metrics combine correctly,” which implies the TrainingClient API returns `Task.t(...)` (per your earlier phases). It might help to nudge the test author:

   > In the integration test, call `TrainingClient.forward_backward/4` and `optim_step/2`, then `Tinkex.Future.await/2` or `Task.await/2` on the returned Tasks to assert `{:ok, result}` and metrics.

   That makes it clear you expect tests to exercise the Task-based API, not just synchronous helpers.

2. **Controlling heartbeats**

   You tell the test to stub “Session creation / heartbeat,” which is good. Just be aware that SessionManager will send heartbeats periodically using `Process.send_after`. If you don’t care about heartbeats in this integration, you might mention:

   > It’s enough to stub the first heartbeat call or use a short heartbeat interval; tests must not rely on real-time heartbeat timing.

   Not strictly necessary, but it prevents tests from accidentally depending on 10s timers.

Overall, 6A looks very solid.

---

## Phase 6B – Sampling Workflow & Concurrency

### What’s working well

* End-to-end path is clear:
  `ServiceClient` → `SamplingClient` → `SamplingClient.sample/4` → `Task.await`.
* You fixed the earlier “sampling should retry 5xx” inconsistency:

  > 5xx surfaces as `{:error, %Tinkex.Error{type: :api_status}}` with `max_retries: 0` (no automatic HTTP retries).

  That matches your earlier HTTP layer / sampling design.
* Concurrency & RateLimiter behaviour are specified realistically:

  * When a 429 with `retry_after_ms` is received, subsequent calls must respect the backoff before hitting Bypass again.
* You’ve aligned telemetry expectations with reality:

  > Attach handler for `[:tinkex, :http, :request, :start/stop]`; queue-state telemetry belongs to future polling, not this path.

### Minor clarifications

1. **How to assert backoff without brittle sleeps**

   You say:

   > ensure subsequent calls respect the backoff before hitting Bypass again.

   In practice your test will probably:

   * Count how many `/asample` requests Bypass sees in a time window after the first 429.
   * Or check that the RateLimiter’s `backoff_until` is set correctly.

   To keep tests deterministic, you might add:

   > Use counters and small, bounded sleeps (e.g. a few ms) or inspect RateLimiter state (e.g., via a helper) rather than asserting on wall-clock durations.

   You’ve already encouraged “counters instead of long sleeps,” but tying that explicitly to the backoff assertion is helpful.

2. **Task.await_many usage**

   Under Constraints:

   > SamplingClient API returns Tasks; ensure integration tests use `Task.await_many`.

   But your main deliverable describes a single `sample/4` call + `Task.await`. Both are fine, but they test slightly different things:

   * Single call → happy-path shape.
   * `await_many` → concurrency semantics.

   You might make that explicit:

   > Use `Task.await/2` for single-sample tests and `Task.await_many/2` or `Task.async_stream` for concurrency tests to exercise the Task-returning API.

Otherwise, 6B is very well aligned.

---

## Phase 6C – Multi-Client Concurrency & Telemetry

### What’s working well

* The target is exactly what you want this late in the plan:

  > two ServiceClients with different configs, concurrent training + sampling, error recovery, RateLimiter isolation, telemetry observation.

* You explicitly distinguish training vs sampling behaviour:

  * 5xx retry behaviour is tested for **training/future polling** (using `with_retries/5`).
  * Sampling continues to use `max_retries: 0` and should NOT auto-retry 5xx unless you consciously change that design.

* Config isolation is well defined:

  > assert distinct entries in ETS (e.g., RateLimiter atomics keyed by `{normalized_base_url, api_key}` and separate `:tinkex_sampling_clients` entries per client).

* Telemetry expectations are realistic:

  * Attach a handler using `:telemetry.attach/4`.
  * Optionally provide a small helper like `Tinkex.Telemetry.attach_logger/0`.
  * Keep it a “lightweight logger,” not a full-blown dashboard.

### Small tweaks

1. **Make the RateLimiter test expectations explicit**

   You say:

   > Ensure no cross-talk (RateLimiter keyed per `{base_url, api_key}`).

   You could give specific examples that testers can assert:

   * For clients `A` and `B` with different API keys:

     * `:ets.lookup(:tinkex_rate_limiters, {:limiter, {normalized_base_url, key_a}})` and …`key_b` should return different atomics.
   * Ensure 429 from client A does *not* affect client B’s ability to send requests immediately.

   That’s implied, but explicitly guiding the assertions will reduce ambiguity.

2. **Performance baseline wording**

   Under Constraints:

   > Document performance baseline approach (even if mocked; note how to measure vs Python).

   Just reinforce (as you did in 6A) that tests must not assert on performance numbers:

   > Performance measurements should be documented and logged only; integration tests must not assert on specific timings.

   That keeps tests robust across machines/CI environments.

3. **Supertester note**

   You mention `Task.async_stream` or `Supertester`. That’s good and matches earlier usage. No changes needed, but it’s worth remembering that if you lean heavily on Supertester, you may want to point back to the existing patterns in your `support/` modules (which you’ve already got).

---

## Overall

Across 6A–6C you’ve:

* Resolved the earlier retry vs no-retry ambiguity for sampling.
* Clarified where queue-state telemetry belongs.
* Standardized on starting the full application (`Application.ensure_all_started(:tinkex)`) for integration tests.
* Given concrete, realistic test targets without requiring “magic” behaviour from the system.

The remaining comments are mostly about making tests less brittle (performance / timing assertions) and being super explicit about the shape of the Task-based APIs the tests should use.

From here, someone can implement these phases with very little guesswork, and they’re unlikely to accidentally violate the core design decisions you made in earlier phases.
