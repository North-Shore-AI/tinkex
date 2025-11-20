Got it, you’ve split the big thing into 3 phase prompts and layered in more critiques. I’ll treat these as “specs for an agent” and review them holistically, then per phase, and call out concrete improvements rather than just vibes.

---

## 0. High-level critique across all three prompts

### ✅ What’s strong

* **Clear sequencing**: 2A → 2B → 2C is coherent and well-scoped per day.
* **Tight constraints**:

  * “No `Application.get_env` at call time”
  * “Config is required”
  * “x-should-retry has precedence”
    These are exactly the class of hard invariants an agent needs.
* **Excellent test-first framing**: Each phase ends with **Implementation checklist + Testing checklist + Type safety checklist**, which is agent-friendly and auditable.
* **Pool shape is consistently described** across all phases (table + repeated explanations).

### Global issues to fix

1. **Some duplication will cause drift.**
   The same retry semantics, header rules, and pool descriptions are repeated in 2A, 2B, and 2C. If you later tweak the contract, an agent might “follow the wrong version”.

   **Prescriptive change**:

   * Introduce a single short “HTTP contract” snippet (retry rules, header precedence, pool table) referenced by all three prompts, instead of fully restating.
   * In each phase, say “See shared HTTP spec for semantics; this phase only adds X”.

2. **Time / sleep in tests vs deterministic intent.**
   You’re okay with `Process.sleep` in tests here (which is fine for a client library), but there are a few places where timing-based assertions are fairly tight and may be flaky (e.g. `assert elapsed >= 900` for “1 second” waits).

   **Prescriptive change**:

   * Loosen thresholds and/or mark them as `@tag :slow` and run them only in a dedicated suite.
   * Prefer `assert elapsed >= value - tolerance` / `<= value + tolerance` if you ever assert upper bounds.

3. **Agent prompt style: sometimes too implementation-heavy, sometimes not opinionated enough.**
   In a few places you’re specifying exact code (down to `then/1`) where the behavior is what matters. In others, you leave behavior implicit.

   **Prescriptive rule**:

   * For anything where *style is not critical*, describe the behavior + type, not exact pipeline shape.
   * Reserve exact code snippets for places where subtle bugs are likely (e.g. `with_retries` ordering).

4. **Type story is good but not fully exploited.**
   You introduce typed responses in Session only (`create_typed/2`), but the rest of the endpoints are JSON-only. That’s fine as a staged plan, but as a spec it feels inconsistent.

   **Prescriptive change**:

   * Either explicitly declare “type helpers exist only for session in Phase 2; others get typed wrappers in Phase 3+”, or
   * Define a generic pattern once (e.g. `*_typed` for all endpoints) and list which ones you’ll implement now.

5. **No explicit story for dependency injection / mock HTTP client in 2C.**
   You define `Tinkex.HTTPClient` and then rely on Bypass everywhere. If the goal is also to support unit tests that don’t touch the network, you should explicitly connect the two.

   **Prescriptive change**:

   * Add a short section: “For unit-level tests, use `Tinkex.HTTPClient` behaviour and a fake implementation; for integration-level HTTP behavior, use Bypass + `Tinkex.API`.”

---

## 1. Phase 2A (HTTP Foundation) – critique

Overall: Very solid. Clear rationale, good config design, and appropriate separation.

### 1.1 `Tinkex.PoolKey`

**Good**

* URL normalization rules are well-specified and tested.
* You lower-case host and strip standard ports: correct and RFC-friendly.
* You raise on obviously-invalid URLs (nice, catches misconfig early).

**Critiques & tweaks**

1. **Strictness vs ergonomics.**
   `normalize_base_url("example.com")` raises. That’s correct for your intent, but agents and humans will absolutely try to pass raw hosts at some point.

   **Prescriptive option** (if you want slightly nicer DX):

   * Allow bare host and assume `https://` as default scheme *or*
   * Keep the strictness but explicitly call out in the docs:

     > “You MUST pass a proper URL (`https://host[:port]`). Bare hosts like `example.com` are intentionally rejected.”

2. **Where scheme mismatches exist.**
   You rely on base URL scheme to decide default port logic. That’s fine, but consider explicitly saying:

   > “We do not normalize scheme mismatches: `http://example.com:443` is treated literally.”

   so an agent doesn’t try to “fix” that.

3. **Pool key docs and Application configuration should be cross-linked.**
   Phase 2A docs for `PoolKey` define the tuple shape, and `Application` depends on it. It’s clear to a human, but an agent might change one without noticing the other.

   **Prescriptive change**:

   * In `Application` moduledoc, add:

     > “Pool keys MUST be generated via `Tinkex.PoolKey.build/2`; do not hand-construct tuples.”

### 1.2 `Tinkex.Config`

**Good**

* Enforced keys make sense.
* “Env only in `new/1`” is exactly the right discipline.
* Clear multi-tenancy story: different configs, different pools.

**Critiques & tweaks**

1. **`user_metadata` is under-specified.**
   You allow arbitrary metadata but don’t say how it will be used (if at all). This can become a dumping ground.

   **Prescriptive change**:

   * Add a short note in moduledoc:

     > “`user_metadata` is not used by the HTTP layer in Phase 2; it is passed through in telemetry events in Phase X (TBD).”

2. **Config of `http_pool` vs base_url.**
   You mention that different base URLs with the same `http_pool` name will share pools (and may not get tuned sizes). That’s correct but subtle.

   **Prescriptive improvement**:

   * Add an explicit invariant:

     > “If you use multiple base URLs in production, you must also configure distinct `http_pool` names per tenant; otherwise pool tuning is only guaranteed for the primary configured base URL.”

3. **`validate!/1` doesn’t re-normalize things.**
   It just checks types; that’s fine. But if someone constructs `%Config{}` manually, they could pass nonsense `base_url`. You already document that `normalize_base_url` will raise later, but:

   **Prescriptive change** (optional):

   * Either: mention “we do not validate URL structure here; invalid base URLs will fail when used in `PoolKey`”, or
   * Add a lightweight `URI.parse/1` check in `validate!/1` to fail earlier.

### 1.3 `Tinkex.Application`

**Good**

* Clear description of pool shapes and sizes aligned with the table.
* Using tuple keys consistently is coherent.
* Good moduledoc around multi-tenant weirdness.

**Critiques & tweaks**

1. **Protocol vs base URL scheme.**
   You hardcode `protocol: :http2` in all pool configs, but your default base URL is `https://…`. Finch will do ALPN negotiation under the hood, but if somebody uses `http://` base_url, that may get weird.

   **Prescriptive change**:

   * Add a small note:

     > “Pools are configured for HTTP/2. Using `http://` base URLs is not recommended and may result in suboptimal behavior.”

2. **No explicit failure mode if base_url is malformed in config.**
   `normalize_base_url/1` can raise inside `start/2`; that’s good (fail fast), but the prompt doesn’t say that.

   **Prescriptive change**:

   * Add to moduledoc: “If configured `:tinkex, :base_url` is invalid, application start will fail with `ArgumentError` – this is intentional.”

3. **Agent instructions for multi-tenant pools.**
   You hint at “configure additional pools in your app supervision tree” but don’t give even a one-line shape.

   **Prescriptive addition**:

   * Add a tiny code sample:

     ```elixir
     # In the host app:
     {Finch, name: TenantA.HTTP.Pool, pools: %{...}},
     {Finch, name: TenantB.HTTP.Pool, pools: %{...}}
     ```

---

## 2. Phase 2B (HTTP Client) – critique

This phase is the most subtle (retry logic, error typing, telemetry, etc.). Overall it’s strong.

### 2.1 Retry logic & `with_retries`

**Good**

* You explicitly point out the previous “clause ordering bug” and fix it.
* `should_retry?/4` centralizes decision logic.
* x-should-retry precedence is spelled out clearly and reflected in code.
* You have a **total retry duration cap** to prevent unbounded waits.

**Critiques & tweaks**

1. **Total duration semantics are a bit misleading.**
   `@max_retry_duration_ms` is checked *before* making the next attempt, but the overall latency is actually:

   `total = elapsed + (current attempt’s receive_timeout)`

   So a single long `receive_timeout` can push you well beyond 30s from user perspective, even if your retry logic thinks you’re under budget.

   **Prescriptive improvement** (no need to rework code now, but clarify):

   * Clarify in docs:

     > “`@max_retry_duration_ms` bounds the **backoff/retry window**, not the per-request network timeout; total wall-clock latency may be `max_retry_duration_ms + timeout` in the worst case.”

   * Optionally in a later phase, accept a “global_timeout_ms” and pass a lowered `receive_timeout` on later attempts.

2. **`Process.sleep` in the client is okay but should be acknowledged more strongly.**
   You already have a note that it blocks the caller. Given you’re building something to be called from GenServers as well, this is important.

   **Prescriptive change**:

   * Add a short “Usage caveat” in `Tinkex.API` moduledoc:

     > “If you call Tinkex.API from inside a GenServer, that GenServer will be blocked during retries. For high-concurrency callers, consider wrapping calls in `Task.async/await` or a supervised worker pool.”

3. **Jitter & attempt indexing**
   You use `base_delay = initial * 2^attempt`. That’s fine but starting from attempt 0 = 500ms*1. That’s a relatively large initial delay if you want snappy retries.

   **Prescriptive suggestion** (optional tuning, not correctness):

   * Document the approximate backoff: “Attempts: 0 → ~0–500ms, 1 → ~0–1000ms, … up to 8s cap.”

4. **429 handling & concurrency**
   Handling of Retry-After is good. Just note that you sleep synchronously, so hitting a rate limit will freeze that process for the Retry-After duration.

   **Prescriptive doc tweak**:

   * Add to 429 docs: “Retry-After semantics cause the calling process to sleep; this is by design to avoid busy loops. Don’t call Tinkex.API from critical GenServer loops if you expect rate limits frequently.”

### 2.2 Error mapping / categorization

**Good**

* Error categories map logically: 4xx → :user, 5xx → :server, with override from JSON `category`.
* Non-Exception `{:error, term}` handling is explicitly considered.

**Critiques**

1. **`Tinkex.Types.RequestErrorCategory.parse/1` is used but not constrained in spec.**
   You assume it returns atoms for valid input; that’s fine, but if it ever returns `{:error, _}`, your code will treat the tuple as category.

   **Prescriptive change**:

   * In the spec, explicitly state:

     > “`Tinkex.Types.RequestErrorCategory.parse/1` MUST return an atom category; it MUST NOT return `{:error, _}`.”

2. **Error struct mapping for connection failures could include more context.**
   You add the raw exception term to `data`, but not the request metadata. Sometimes having method/path in the error struct is useful.

   **Prescriptive suggestion**:

   * Consider adding an optional `context` field later; but not necessary for Phase 2.

### 2.3 Telemetry

**Good**

* Start/stop/exception events with clear naming.
* Include method, path, pool_type, base_url, and result type in metadata.

**Critique**

1. **You don’t explicitly ensure telemetry is emitted for the final error case after retries.**
   It is, because `execute_with_telemetry` wraps `with_retries`, but it might be worth adding a line of text:

   > “The `:stop`/`:exception` telemetry events reflect the **final outcome after retries**, not per-attempt outcomes.”

2. **No doc on how to hook telemetry into central monitoring.**
   You do provide an `attach_telemetry` helper in 2C; good. But maybe link from `Tinkex.API` docs.

---

## 3. Phase 2C (Endpoints & Testing) – critique

This phase is mainly composition: calling `Tinkex.API` correctly, choosing pools, and wiring tests.

### 3.1 Endpoint modules (Training, Sampling, Futures, Session, Service, Weights, Telemetry)

**Good**

* Clear mapping of each endpoint to pool type.
* Naming is mostly verb-based (`create`, `heartbeat`, `save_weights`, etc.).
* Telemetry is explicitly fire-and-forget except the `_sync` variant.

**Critiques & refinements**

1. **`sample_async/2` signature & naming**
   You highlight that the HTTP endpoint is `/api/v1/asample` but function is `sample_async`. That’s good.

   * Using `then/1` in the implementation is cute but slightly non-idiomatic for library code in a spec (it leaks Elixir version requirements into the spec).

   **Prescriptive change**:

   * Specify behaviorally:

     ```elixir
     opts = opts
       |> Keyword.put(:pool_type, :sampling)
       |> Keyword.put(:max_retries, 0)

     Tinkex.API.post("/api/v1/asample", request, opts)
     ```

     and leave `then/1` as an implementation detail if you want.

2. **Typed response pattern is only specified for `create_typed/2`.**
   You call out typed helpers in Session only.

   **Prescriptive clarification**:

   * Add a one-liner:

     > “In Phase 2, only session creation gets a typed helper; other endpoints return raw JSON. Future phases will introduce typed wrappers as needed.”

   That prevents an agent from feeling obligated to add `*_typed` everywhere immediately.

3. **Telemetry module: logging failure uses `error.message`.**
   This assumes `Tinkex.Error.t()` has `message` field (it does), but if an unexpected error shape appears, this will crash the Task.

   **Prescriptive improvement**:

   * In the prompt, suggest:

     ```elixir
     Logger.warning("Telemetry send failed: #{inspect(error)}")
     ```

     rather than `error.message` to be safer.

4. **Fire-and-forget semantics: mention Task supervision.**
   `Task.start/1` creates unlinked processes (Elixir OTP convention changed; `Task.start/1` spawns linked or unlinked? In recent versions it’s unlinked but still “fire-and-forget”). If the process crashes, you just lose telemetry – which is fine for this domain.

   **Prescriptive doc addition**:

   * Mention: “Telemetry tasks are not supervised; failures are logged and otherwise ignored. This is intentional.”

### 3.2 HTTPCase test helper

**Good**

* Nice centralization of Bypass setup and stubbing helpers.
* `attach_telemetry/1` is really handy and well-shaped.
* `stub_sequence/2` with Agent is a solid pattern.

**Critiques**

1. **Missing `use ExUnit.CaseTemplate` callbacks clarity.**
   You use `use ExUnit.CaseTemplate` correctly and define `using do ...`. Good. But you should also define `setup` callbacks as `@doc false` or in the prompt clarify that they return maps.

   **Prescriptive tweak**:

   * Add explicit `@spec setup_http_client(map()) :: map()` to the prompt so an agent will type it.

2. **`stub_sequence/2` Agent isn’t cleaned up.**
   The agent used as counter is not terminated; in test suites this usually doesn’t matter, but you could accumulate processes over many tests.

   **Prescriptive improvement**:

   * In the helper, you can:

     ```elixir
     on_exit(fn -> Process.exit(counter, :normal) end)
     ```

   so tests don’t leak agents.

3. **Case template vs `Code.require_file`**
   In test_helper you both `ExUnit.start()` and `Code.require_file("support/http_case.ex", __DIR__)`. That’s correct. Maybe add a note: “We rely on the file being required before any tests.” An agent will handle this, but explicit mention helps.

### 3.3 API tests (retry logic etc.)

**Good**

* Very thorough coverage of the retry rules and header precedence.
* Case-insensitive header tests are solid.
* Telemetry tests assert metadata shape (method, path, pool_type).

**Critiques**

1. **Bypass concurrency and `async: true`.**
   You correctly *don’t* mark `Tinkex.APITest` as `async: true`, because Bypass is known to be brittle under heavy concurrent use.

   **Prescriptive addition**:

   * Add a sentence in the prompt:

     > “All Bypass-based tests in this module MUST NOT be `async: true`.”

   so an agent doesn’t “optimize” it away later.

2. **Concurrent request test uses `Process.sleep(10)` in handler.**
   Fine for simulating slow responses, but note that 50 concurrent tasks plus Bypass plus 10ms sleep might be borderline in CI on small machines depending on scheduler load.

   **Prescriptive tweak**:

   * Either:

     * Mark as `@tag :slow` with a longer timeout, or
     * Reduce concurrency to, say, 20 and keep the semantics.

---

## 4. If you want “quick edits” to make the prompts cleaner for an agent

If you only want to change a few things now, I’d do these:

1. **Consolidate the HTTP semantics.**
   Create a tiny shared “HTTP Specification” snippet and have all three phases refer to it rather than restating rules.

2. **Be explicit about which tests MUST NOT be async.**
   In Phase 2B/2C, clearly state for `Tinkex.APITest` and any Bypass-based suites: `use ExUnit.Case, async: false`.

3. **Clarify that typed responses are limited in Phase 2.**
   In 2C, explicitly say: “Only Session has a typed helper in this phase; others stay JSON.”

4. **Relax timing assertions slightly.**
   For tests asserting Retry-After delays, accept “>= 80% of target” or mark as slow, to reduce CI flakiness.

5. **Add one small note about retry total duration semantics.**
   In 2B, clearly state that `@max_retry_duration_ms` limits retry/backoff, not overall wall-clock latency (due to `receive_timeout` per attempt).

---

If you’d like next, I can rewrite one of these prompts (say Phase 2B) into its “final, deduplicated, agent-ready” form incorporating these critiques, instead of just commenting on it.
