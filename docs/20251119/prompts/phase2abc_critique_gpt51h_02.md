You’ve cleaned these up a lot. The shared HTTP spec, the no-timing-assertions rule, and the clarified retry semantics all make this set of prompts much friendlier for both a human and an agent.

I’ll go phase by phase and then call out cross-cutting things I’d still tune.

---

## Big-picture improvements

* The **shared HTTP spec** in Phase 2A is exactly what was missing before: one authoritative place for pools, retries, header semantics, and invariants.
* You’ve **stopped hard-coding the buggy with_retries patterns** and instead clearly state “everything routes through `should_retry?`”. Good.
* The prompts now distinguish clearly between:

  * Phase 2A = foundation (pools, config, application).
  * Phase 2B = core HTTP client + retry semantics.
  * Phase 2C = endpoints + full test suite.
* You’ve made the testing rules explicit:

  * No timing assertions.
  * No `Process.sleep` in handlers.
  * Bypass tests are not async.
  * Use counters/agents to assert retries.

Overall, the revised prompts are much clearer and safer to follow.

Now, details.

---

## Phase 2A – HTTP Foundation

### What’s solid

* **HTTP spec section (2.x)**:
  Great consolidation. Pool table, retry semantics, header case-insensitivity, and invariants are all in one place now. The explicit invariants:

  * “Pool keys MUST be generated via `Tinkex.PoolKey.build/2`”
  * “Config MUST be threaded via `opts[:config]`”
  * “RequestErrorCategory.parse/1 MUST return an atom”

  …are exactly the kind of rules that prevent subtle breakages later.

* **PoolKey**:

  * Strict about requiring scheme + host.
  * Lowercases host, strips default ports.
  * Explicit note that bare hosts are rejected and `http://` is discouraged.

* **Config**:

  * Env access only in `new/1`, and explicitly wrapped in lambdas to avoid compile-time reads.
  * Good multi-tenant story, with concrete example of separate Finch pools per tenant.
  * `user_metadata` is explicitly marked as unused in Phase 2, which avoids it becoming a mysterious field.

* **Application**:

  * Uses tuple pool keys consistently.
  * Explicitly refers back to the shared pool spec rather than duplicating.

### Things I’d tighten

1. **Config validation doesn’t check URL structure.**

   Right now `Config.validate!/1` only checks presence of `base_url`, not whether it’s a syntactically valid URL. The prompt mentions that `PoolKey.normalize_base_url/1` can raise later, but that’s an extra hop.

   * You can either explicitly document:

     > “`validate!/1` only validates presence and types. Invalid base URLs will fail when used in `PoolKey.normalize_base_url/1` (e.g., in `Tinkex.Application`).”
   * Or add a very lightweight check (e.g., `URI.parse(base_url)` with a scheme/host guard) in `validate!/1`.

   Not required for correctness, but it clarifies where misconfigurations explode.

2. **`{:supertester, "~> 0.2", only: :test}` in deps is unexplained.**

   You add Supertester as a test dependency in mix.exs, but the prompts in Phase 2 never actually use it. Everything is ExUnit + Bypass.

   That’s not wrong, but for an agent this is a dangling “why?”:

   * Either remove it from the Phase 2A spec for now, or
   * Add a one-liner:

     > “Supertester is included as a test-only dependency for future OTP-level tests; Phase 2 tests use ExUnit + Bypass only.”

3. **`http://` base URLs.**

   You note that `http://` is “not recommended”, but Application config still happily uses `protocol: :http2` for all pools. That’s fine in practice, but I’d make the interaction explicit:

   > “Pools are configured for HTTP/2. Using `http://` base URLs is not recommended and may result in suboptimal behavior; the SDK is intended for HTTPS endpoints.”

---

## Phase 2B – HTTP Client

### What’s solid

* **Retry semantics + `max_retry_duration_ms`**:

  * You explicitly separate “retry decision window” from total wall-clock time.
  * You explicitly document that final wall-clock = `max_retry_duration_ms + receive_timeout` in the worst case. That’s the subtlety that was missing before.

* **GenServer blocking caveat**:

  * The warning and the `Task.async/await` example are great. This is the right level of “don’t do something naive with this”.

* **API moduledoc**:

  * References the shared HTTP spec instead of re-explaining everything.
  * Telemetry section now clearly states that events reflect final outcome after retries, not per attempt.

* **Error handling**:

  * Handles 429 specially with Retry-After.
  * Uses `RequestErrorCategory.parse/1` only when present and documents that it must return an atom.
  * Handles `Mint.TransportError`, `Mint.HTTPError`, and raw `:timeout`/`:closed` terms with a generic clause.

* **Tests**:

  * All tests are deterministic: no timing assertions, all behavior is via Agents/counters.
  * Bypass usage is non-async as required.
  * Coverage: 5xx retry, 429+Retry-After, header precedence, case-insensitive headers, `max_retries`, category parsing, connection refused, and “no config” error.

### Things I’d tighten

1. **Duplicate / divergent API test specs between 2B and 2C.**

   You now have:

   * A `Tinkex.APITest` in Phase 2B.
   * A more complete `Tinkex.APITest` in Phase 2C using `Tinkex.HTTPCase`.

   An agent could reasonably implement both, or get confused which is canonical.

   I’d pick one of these strategies:

   * **Preferred**: Make Phase 2B describe test *cases* in prose only (“write tests that…”) and explicitly say:

     > “The concrete test module and helpers are specified in Phase 2C; implement them there.”
   * Or: Keep only the Phase 2C version and remove the full code from 2B, leaving just the checklist.

   Right now, the overlap is more likely to cause drift than help.

2. **Coverage of 408 in 2B vs 2C.**

   Your 2B checklist mentions retrying on 408, but the explicit API test examples there don’t show a 408 case. That test *does* exist in the Phase 2C sample. That’s fine, but maybe add a small note in 2B:

   > “The concrete 408 test is defined in Phase 2C’s API test module.”

   Just to avoid an agent thinking you forgot it.

3. **HTTPClient behaviour is optional but under-tested.**

   You correctly define `Tinkex.HTTPClient` and implement it via `@behaviour`. Right now, the prompts don’t show any tests that exercise swapping in an alternative implementation (e.g., a fake client).

   Not strictly necessary, but a short note would clarify intent:

   > “In Phase 2 we rely on Bypass + `Tinkex.API` for HTTP integration tests. The HTTPClient behaviour exists to support future unit-level tests and host-library mocking; it doesn’t need dedicated tests in this phase.”

4. **Logging semantics.**

   The prompts say “structured logging for debugging” but the examples are simple `Logger.debug/Logger.warning` with strings. That’s fine, but “structured” might make someone think they need metadata logging.

   Either keep “structured” if you intend to use metadata in real code, or just say “debug logging” in the checklist to avoid over-promising.

---

## Phase 2C – Endpoints & Testing

### What’s solid

* **Endpoint modules**:

  * Clean, simple wrappers over `Tinkex.API`.
  * Pool types are consistently applied.
  * `sample_async/2` now uses explicit pipelines (no `then/1`), and sets `max_retries: 0` as spec’d.
  * Session typed helper is explicitly the only typed helper in Phase 2, and that’s called out up front.

* **Telemetry endpoints**:

  * Clear explanation that tasks are unsupervised and failures are logged & ignored.
  * `send/2` logs `inspect(error)` rather than `error.message`, which is safer.

* **HTTPCase helper**:

  * Good centralization for Bypass + config creation + telemetry attaching.
  * `stub_sequence/2` and `attach_telemetry/1` both clean up via `on_exit` now, which addresses process leak concerns.
  * `setup_http_client/1` has an explicit `@spec`, which helps Dialyzer and agents.

* **API test suite**:

  * Fully deterministic: all retry behavior is verified via counters; no elapsed-time assertions.
  * Tests explicitly cover:

    * 5xx retries
    * 408
    * 429 (ms and seconds)
    * x-should-retry true/false
    * case-insensitive headers
    * `max_retries`
    * error categorization
    * connection refusal
    * telemetry start/stop events + pool_type metadata
    * moderate concurrent load (20 requests)

* **Phase-level rules**:

  * “All Bypass-based tests are NOT async: true”
  * “No Process.sleep in Bypass handlers”
  * “No timing assertions”
    These are crystal clear now.

### Things I’d tighten

1. **`TelemetryTest` still uses a time-based wait.**

   In `Tinkex.API.TelemetryTest`:

   ```elixir
   result = Tinkex.API.Telemetry.send(%{event: "test"}, config: config)
   assert result == :ok

   # Give the async task time to complete
   :timer.sleep(50)
   ```

   Two minor issues:

   * This technically violates your “no timing assertions” policy’s spirit (but you’re not asserting on elapsed time, just sleeping).
   * It is still a time-based sync mechanism that can flake in slow CI environments.

   Possible improvements:

   * Either:

     * Explicitly bless this as the one allowed tiny sleep:

       > “We use a small `:timer.sleep/1` here only to avoid races with the Task; it does not participate in assertions.”
     * Or better, couple it to something observable:

       * Attach a telemetry handler or use a `stub_success` with `Bypass.expect_once` and assert *before* test exit that the expectation was hit (e.g. via a message or a counter), so you can drop the sleep.
   * Also, since your pitfalls list “No Process.sleep in tests”, I’d either:

     * Clarify it also covers `:timer.sleep`, or
     * Change the rule to “No arbitrary sleeps” and explicitly call out this one as intentional.

2. **HTTPCase vs Phase 2B APITest duplication (same as above).**

   Phase 2C defines the canonical `Tinkex.APITest` using HTTPCase; Phase 2B also defines an APITest.

   I’d treat the Phase 2C version as the canonical one and make Phase 2B just say: “Tests are defined in `test/tinkex/api/api_test.exs` as specified in Phase 2C,” to avoid confusion or duplicate work.

3. **Pool-type verification tests in endpoint modules could be more explicit.**

   In `Tinkex.API.TrainingTest`, your “uses training pool” test is essentially a smoke test; you hint that in a real test you’d inspect telemetry.

   Since you already have `attach_telemetry/1`, it would be really nice to demonstrate:

   ```elixir
   attach_telemetry([[:tinkex, :http, :request, :start]])
   stub_success(bypass, %{loss: 0.5})

   {:ok, _} = Tinkex.API.Training.forward_backward(...)

   assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, metadata}
   assert metadata.pool_type == :training
   ```

   Not mandatory, but it “closes the loop” and proves your pool wiring works.

4. **Pitfalls list vs actual code**

   * “Don’t use `then/1`” – already enforced.
   * “Don’t use Process.sleep in tests” – you replaced it with `:timer.sleep/1`, which is functionally the same; if you want to be really consistent, either ban both or explicitly allow the tiny `:timer.sleep` in that one test.
   * “Don’t use `error.message` in Logger” – already enforced.

---

## Overall assessment

These revised prompts are in good shape:

* They’re **internally consistent** (thanks to the shared HTTP spec).
* They’re **agent-friendly**: clear ordering, explicit file and test layout, checklists at the end.
* They encode subtle behaviors (retry semantics, header precedence, GenServer blocking, telemetry semantics) in a way that will be hard to accidentally break.

If you make one structural change, I’d suggest:

> **Centralize the APITest spec entirely in Phase 2C and have Phase 2B simply refer to it**, to avoid drift.

And if you make one small behavioral tweak:

> Either justify or remove the `:timer.sleep(50)` in `TelemetryTest` so your “no timing dependence” story stays clean.

Other than those, this is a very solid spec pack to drive actual implementation from.
