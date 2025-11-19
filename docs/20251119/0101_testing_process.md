# 0101 – Phase-Aligned Testing Process for Tinkex

> **This doc ties together:**
>
> * `0001_testing_strategy_gpt_5_1_extended.md` (what to test)
> * `0100_testing_port_plan` (Python→Elixir test mapping)
> * `Tinkex SDK Implementation Process` (phased build)
>
> It answers: **"Exactly what testing happens in each implementation phase, with what gates?"**

---

## 1. Role of this document

* `0001` defines **testing layers & coverage goals** (unit, HTTP, clients, futures, telemetry, CLI, contract).
* `0100` defines **how Python tests map onto Elixir** (which files to mirror, adapt, or skip).
* **`0101` (this doc)** defines a **time-ordered testing workflow**, phase by phase, matching the **Implementation Process** phases 0–7.

You should be able to read the Implementation Process and this doc side by side and see:

* For each **Phase N**:
  * Which **tests must exist** before the phase is "done".
  * What those tests are **allowed to depend on**.
  * How we **prove parity** with Python at that stage.

---

## 2. Testing layers & responsibilities (recap)

We'll keep the same layered model from `0001`, but attach them to phases:

1. **Unit (pure)**
   * Types, helpers, MetricsReduction, TensorData, RequestErrorCategory, JSON encoding helpers.
2. **HTTP & config**
   * Retry logic, headers, error mapping, `Retry-After`, `x-should-retry`, `Tinkex.Config`.
3. **Clients**
   * ServiceClient, TrainingClient, SamplingClient, RestClient; Bypass-based tests.
4. **Futures & queue backpressure**
   * Future.poll, TryAgainResponse, QueueState, backoff semantics.
5. **Telemetry**
   * `:telemetry` events, reporter batching & session index.
6. **CLI**
   * Commands & error mapping.
7. **Contract / E2E**
   * Small suite against `mock_api_server.py` or real API.

Each phase of implementation "unlocks" more of these layers.

---

## 3. Phase-by-Phase Testing Plan

### Phase 0 – Wire Format Verification & Baseline

**Implementation goal:**
Verify assumptions against live API / Python SDK before coding.

**Testing goal:**
Have a **minimal, ad-hoc verification harness** that produces a **wire format report** we'll treat as a "golden contract" for Phase 1+.

#### T0.1 – Wire format probes

For each critical item from the Implementation Process:

1. **StopReason**
   * Probe sampling endpoint at least twice:
     * One run that stops by max tokens.
     * One run that stops via explicit stop sequence.
   * Record the raw JSON `stop_reason` values.

2. **RequestErrorCategory**
   * Trigger a synthetic RequestFailedError (e.g. training or sampling with invalid input).
   * Capture `category` field in JSON: confirm `"unknown" | "server" | "user"` and casing.

3. **Image types**
   * Call API with JSON `ImageChunk` / `ImageAssetPointerChunk` payload using Python SDK.
   * Dump exactly what Python sends (`model_dump_json` / request body) to fixture files.

4. **SampleRequest.prompt_logprobs**
   * Send three SampleRequests from Python:
     * `prompt_logprobs=None`
     * `prompt_logprobs=True`
     * `prompt_logprobs=False`
   * Capture outgoing JSON bodies; confirm presence/omission and `null/true/false`.

5. **Rate limiting scope**
   * Use Python SDK to fire concurrent sampling requests with:
     * Two clients using same `{base_url, api_key}`
     * A third client with a different key or base_url
   * Observe whether rate limiting appears correlated; note in comments for Elixir RateLimiter tests (even if Python doesn't share backoff state, Elixir's shared limiter is deliberate).

6. **Tokenizer NIF safety (for later)**
   * Might be done in Elixir later, but plan the test (see Phase 5).

**Output of Phase 0 testing:**

* A **"wire contract" folder** under `test/support/fixtures/wire/`:
  * `sample_request_prompt_logprobs_{null,true,false}.json`
  * `sampling_stop_reason_{length,stop,...}.json`
  * `image_chunk_request.json`
  * `image_asset_pointer_request.json`
  * Any error responses with `RequestErrorCategory`.

These fixtures become the **canonical reference** for type & encoding tests in Phase 1.

**Quality Gate Q0:**

* All listed probes run and produce fixtures.
* Any discrepancy vs docs is explicitly noted and docs updated (types, enums, field names).
* Team agrees "wire contract" is now the source of truth for Phase 1.

---

### Phase 1 – Type System (Week 1, Days 4–7)

**Implementation goal:**
Elixir types that serialize/deserialize identically (for our purposes) to Python's.

**Testing goals:**

* Unit tests give **strong guarantees** that:
  * Wire-enforced fields are correct.
  * Optional/nullable behavior matches actual API.
  * Numeric casting behavior is correct for TensorData.
* Golden JSON tests prove parity with Python's fixtures from Phase 0.

#### T1.1 – Enum & literal tests

Modules: `Tinkex.Types.StopReason`, `LossFnType`, `RequestErrorCategory`, `TensorDtype`

Tests:

* **Roundtrip encode/decode:**
  * For each enum value:
    * Build Elixir value → `Jason.encode!` → assert expected string per wire fixture.
    * For RequestErrorCategory: `parse/1` is case-insensitive; outputs atoms `:unknown | :server | :user`.

* **Error handling:**
  * Unknown category string → `:unknown`.
  * For StopReason, ensure we either:
    * Restrict to observed live values, OR
    * Have a safe fallback for unknown strings (e.g. `:unknown` or `nil`) and document it.

#### T1.2 – Struct JSON tests

Modules: `Tinkex.Types.SampleRequest`, `TensorData`, `ImageChunk`, `ImageAssetPointerChunk`, `ModelInput`, `Datum`, `ForwardBackwardOutput`, `OptimStepRequest`, etc.

Patterns:

1. **Type correctness tests** (unit):
   * Construction with required and optional fields.
   * `@type` specs match actual usage (Dialyzer clean).

2. **Golden encoding tests:**
   * For each "wire critical" type, create a test like:
     ```elixir
     test "SampleRequest prompt_logprobs encodes like Python fixtures" do
       req = %SampleRequest{ ... prompt_logprobs: nil ... }
       json = Jason.encode!(req)

       assert json == File.read!("test/support/fixtures/wire/sample_request_prompt_logprobs_null.json")
     end
     ```
   * Repeat for `true` and `false` fixture bodies.

3. **TensorData casting tests:**
   * Using Nx, ensure:
     * `Nx.tensor([...], type: {:f, 64})` → `TensorData.dtype == :float32`.
     * `Nx.tensor([...], type: {:s, 32})` → `:int64`.
     * `uint` types → `:int64`.
   * Roundtrip `to_nx/1` respects `shape` (nil vs list).

4. **Image types tests:**
   * From fixtures:
     * `ImageChunk.new(binary, :png, h, w, tokens)` → `Jason.encode!` equals Python fixture JSON (modulo ordering).
     * `ImageAssetPointerChunk` uses `location` and matches fixture.

5. **Property tests (optional but recommended):**
   * With StreamData:
     * Generate random lists of ints/floats and shapes; ensure `TensorData.from_nx/1 |> to_nx/1` roundtrips.

**Quality Gate Q1:**

* All core types have unit tests + golden JSON tests where relevant.
* No global "strip nils" logic; tests assert that `nil` becomes `null` in JSON when desired.
* Coverage for `Tinkex.Types.*` modules ~90%+.

---

### Phase 2 – HTTP Layer & Retry (Week 2, Days 1–3)

**Implementation goal:**
A robust HTTP layer that matches Python's retry semantics and header behavior.

**Testing goals:**

* Bypass-based tests simulate real HTTP responses covering the retry matrix.
* Tinkex.Config is correctly threaded and multi-tenant safe.
* No `Application.get_env` usage during requests (only at config creation).

#### T2.1 – Config & PoolKey tests

Modules: `Tinkex.Config`, `Tinkex.PoolKey`

Tests:

* Config overrides: `base_url`, `api_key`, `timeout`, `max_retries`, `user_metadata`.
* `PoolKey.normalize_base_url/1`:
  * `https://example.com:443` → `https://example.com`
  * `http://example.com:80` → `http://example.com`
  * Non-standard ports preserved.

#### T2.2 – HTTP retry matrix tests

Modules: `Tinkex.API` + helpers (with Bypass)

Key scenarios:

1. **200 OK without x-should-retry**
   * Single request, no retries.

2. **5xx with no x-should-retry**
   * Should retry up to `max_retries`.
   * Assert number of hits on Bypass by counting expectations.

3. **408 Timeout**
   * Treated as retryable.

4. **429 + Retry-After**
   * Response with headers:
     * `retry-after-ms: "100"`
     * or `retry-after: "3"`
   * Verify `Tinkex.Error.retry_after_ms` is set (100 or 3000).
   * When invoked via `with_retries/3`, ensure it sleeps appropriately (can inject a fake sleep or assert ordering via timestamps/messages).

5. **x-should-retry: "true"/"false"**
   * Test a 4xx (e.g. 400) with `x-should-retry: "true"` → should retry.
   * Test a 5xx with `x-should-retry: "false"` → should *not* retry.

6. **Error mapping**
   * Non-2xx responses map to `%Tinkex.Error{status: code, data: decoded_json}`.

#### T2.3 – Telemetry for HTTP

Modules: `Tinkex.API`, `Tinkex.Telemetry` (basic)

* Attach temporary `:telemetry` handlers in tests to assert:
  * `[:tinkex, :http, :request, :stop]` events emitted with `path`, `method`, `duration`.
  * `[:tinkex, :retry]` emitted when retries occur.

**Quality Gate Q2:**

* All retry branches (5xx, 408, 429, x-should-retry) exercised.
* Config tests show no cross-contamination between clients.
* Telemetry events validated for at least one request.

---

### Phase 3 – Futures & MetricsReduction (Week 2, Days 4–5)

**Implementation goal:**
`Tinkex.Future` polling logic & `Tinkex.MetricsReduction` are correct and robust.

**Testing goals:**

* Polling loops handle all variants of `FutureRetrieveResponse` union.
* MetricsReduction unit tests match Python behavior exactly (using the Python-based reasoning and tests).

#### T3.1 – MetricsReduction tests (unit)

Already outlined in `0100` and `0001`:

* Weighted means across varying `loss_fn_outputs` lengths.
* Each suffix strategy: `:sum`, `:min`, `:max`, `:mean`, `:slack`, `:unique`.
* Empty input and missing metrics.

#### T3.2 – Future.poll integration tests

Modules: `Tinkex.Future`, `Tinkex.API.Futures`

Using Bypass:

1. **Simple completion**
   * Sequence: `pending`, `pending`, `completed` → `{:ok, result}`.

2. **Failed with user error**
   * `status: "failed"` with `category: "user"` → no retry, immediate `{:error, ...}`.

3. **Failed with server error**
   * `status: "failed"` with `category: "server"` → treated as retryable in intermediate stage; eventually surfaces appropriately if logic re-polls or fails.

4. **TryAgainResponse with queue_state**
   * Sequence:
     * `{:ok, %{type: "try_again", "queue_state" => "paused_rate_limit"}}`
     * then `pending`
     * then `completed`.
   * Verify:
     * Telemetry event `[:tinkex, :queue, :state_change]` emitted with `queue_state: "paused_rate_limit"`.
     * Backoff is applied (you can assert via message timings or by counting Bypass expectations after increments).

5. **Timeout handling**
   * Provide short timeout to `poll/2` and ensure it returns error after expected elapsed time (don't let tests actually sleep long; you can stub `Process.sleep/1` via Mox or use a small threshold).

**Quality Gate Q3:**

* All Future response variants tested.
* MetricsReduction tests pass and match both your own reasoning and (optionally) Python golden metrics if you capture them.

---

### Phase 4 – Client Architecture (Week 3–4)

**Implementation goal:**
ServiceClient, TrainingClient, SamplingClient, SessionManager, RateLimiter, SamplingRegistry all wired and safe.

**Testing goals:**

* GenServers are robust: no deadlocks, no "caller never gets reply" scenarios.
* ETS & RateLimiter semantics enforced (no split-brains).
* TrainingClient sequencing & SamplingClient concurrency validated.

#### T4.1 – TrainingClient behavior

Modules: `Tinkex.TrainingClient`

Tests (likely `async: false` because of Bypass and concurrency):

1. **Sequential chunk submission**
   * For a large batch that triggers multiple chunks:
     * Bypass expects N `forward_backward` calls in order; assert they arrive sequentially.
   * Two consecutive `forward_backward` calls:
     * Confirm chunk requests from second call only occur after first call's chunk sends are complete (inspected via recorded messages in the test).

2. **Polling Task safety**
   * Simulate a failing poll (e.g. Bypass returns invalid JSON for `/future/retrieve` after first `pending`):
     * Verify `TrainingClient.forward_backward` still replies with `{:error, %Tinkex.Error{}}` instead of hanging.
     * Check that the TrainingClient process is still alive after the error.

3. **GenServer.reply ArgumentError rescue**
   * Simulate the caller dying before Task replies:
     * Fire a `forward_backward` call from a short-lived process, kill the caller before Task completes.
     * Ensure the Task does not crash the VM when `GenServer.reply` raises `ArgumentError`.

4. **Metrics combination**
   * Use Bypass to return multiple Futures whose results include metrics with different suffixes.
   * Assert the final `ForwardBackwardOutput.metrics` uses `Tinkex.MetricsReduction`.

#### T4.2 – SamplingClient + RateLimiter + SamplingRegistry

Modules: `Tinkex.SamplingClient`, `Tinkex.RateLimiter`, `Tinkex.SamplingRegistry`

Tests:

1. **ETS config presence**
   * After starting SamplingClient, `:ets.lookup(:tinkex_sampling_clients, {:config, pid})` returns config struct.
   * After the process exits (normal or `:kill`), ETS entry is removed by `SamplingRegistry`.

2. **Shared RateLimiter across `{base_url, api_key}`**
   * Start two SamplingClients with same config; ensure they share the same limiter (e.g. `for_key/1` returns same ETS entry / atomics ref).
   * Start client with different key; limiter reference is distinct.

3. **insert_new semantics**
   * Simulate two callers racing to create limiter (you can spawn tasks that call `for_key/1` concurrently).
   * Ensure resulting ETS table has only one entry for the key.

4. **429 behavior**
   * Bypass: first call returns 429 with `retry-after-ms: "10"`; second call returns success.
   * Confirm:
     * First call returns `{:error, %Tinkex.Error{status: 429, retry_after_ms: 10}}`.
     * Subsequent calls wait for RateLimiter backoff (can control with small ms and assert ordering via messages).

5. **No GenServer bottleneck**
   * Fire many concurrent `SamplingClient.sample` invocations (e.g. 100 tasks).
   * Assert:
     * All tasks complete.
     * RateLimiter properly backs off when you inject a 429 after some threshold.

#### T4.3 – SessionManager & ServiceClient

Modules: `Tinkex.SessionManager`, `Tinkex.ServiceClient`

Tests:

* Session creation:
  * Bypass for `/create_session` returning valid session_id.
  * ServiceClient init uses this and stores in state.

* Heartbeat:
  * SessionManager periodically sends heartbeat; Bypass assert hits on `/session_heartbeat` endpoint.

* Client creation:
  * `ServiceClient.create_lora_training_client` returns a `TrainingClient` pid tied to the same config supplied at start.

**Quality Gate Q4:**

* TrainingClient has robust tests around sequencing & Task safety.
* SamplingClient/RateLimiter/Registry behave correctly under concurrency.
* No known deadlocks or crash-on-error patterns in clients.

---

### Phase 5 – Tokenization (Week 5, Days 1–2)

**Implementation goal:**
Safe, lean tokenization using `tokenizers` NIF with caching.

**Testing goals:**

* Prove NIF handles are safe to share via ETS or implement safe alternative.
* Tokenizer ID resolution matches Python semantics (including Llama-3 hack).

#### T5.1 – NIF safety test

Module: `Tinkex.Tokenizer` + test support ETS table

* The test described in the Implementation doc:
  * Create tokenizer in Process A, store in ETS.
  * Use it from Process B via ETS lookup and call encode.
  * Assert no crash; ensure tokens returned are a list of integers.

If unsafe:

* Add alternative tests validating whichever safe design you choose (e.g. a TokenizerServer that owns the handles).

#### T5.2 – TokenizerId resolution tests

Modules: `Tinkex.Tokenizer`, `Tinkex.TrainingClient.get_info/1` (or equivalent)

* Simulate `get_info` responses via Bypass:
  * With `tokenizer_id` set.
  * Without `tokenizer_id`, with model_name containing "Llama-3".
  * Without `tokenizer_id`, unknown model.

* Assert:
  * For Llama-3: `"baseten/Meta-Llama-3-tokenizer"` used.
  * For other models: fallback to `model_name`.

#### T5.3 – Encode helper tests

* `encode(text, model_name)` returns a non-empty list of ints for known model (use local or test-specific HF tokenizer).
* `ModelInput.from_text/2` uses the tokenizer and produces a `ModelInput` with one `EncodedTextChunk` with matching length.

**Quality Gate Q5:**

* Tokenization is functional and tested.
* Caching behavior safe per NIF semantics.

---

### Phase 6 – Integration & Parity (Week 5–6)

**Implementation goal:**
End-to-end workflows and Python parity.

**Testing goals:**

* Use golden fixtures and/or mock API server to confirm behavior matches Python SDK for representative flows.

#### T6.1 – Contract tests vs `mock_api_server.py` (optional but recommended)

* Spin up `mock_api_server.py` from the repo (or a subset of its routes).
* Integration tests:
  * Simple `forward_backward` on a small batch; compare metrics and shapes vs Python results.
  * `optim_step` + `forward_backward` chained.
  * `save_weights_for_sampler` → `SamplingClient.sample`.
  * `get_info` plus tokenization check.

Record any differences and either:

* Fix Elixir implementation to match; or
* Document deliberate deviations (e.g. enhanced RateLimiter semantics).

#### T6.2 – Golden JSON parity tests

For functions where you can easily capture Python request bodies:

* Compare Python and Elixir JSON for:
  * `ForwardBackwardRequest`
  * `OptimStepRequest`
  * `SampleRequest` (various modes: with sampling_session_id vs base_model/model_path)
  * `FutureRetrieveRequest` variants.

Even if the key ordering differs, equality on decoded maps should hold.

#### T6.3 – Multi-client concurrency

Scenarios:

1. **Two training clients + many sampling clients:**
   * Ensure no global state leaks (e.g. Config from one is not used by another).
   * Rate limiting per `{base_url, api_key}` still holds.

2. **Error recovery:**
   * With Bypass, simulate intermittent 5xx / 429; ensure:
     * No deadlocks.
     * Errors eventually surface correctly after retries.

**Quality Gate Q6:**

* Core flows (train, optimize, save, sample) pass against mock or real API.
* Parity tests show Elixir and Python produce equivalent request/response shapes for canonical scenarios.

---

### Phase 7 – CLI & Documentation (Week 7–8)

**Implementation goal:**
User-facing CLI + docs.

**Testing goals:**

* CLI commands behave like Python CLI in terms of options, output shapes, and error handling.

#### T7.1 – CLI smoke tests

Use `ExUnit.CaptureIO` or `System.cmd/3`:

* `tinkex version`
  * Should print version string from Elixir package.

* `tinkex run list`
  * With Bypass or mock RestClient, assert:
    * Table output contains correct headers and rows.
    * `--format json` prints valid JSON with expected keys.

* `tinkex checkpoint list` / `checkpoint info`
  * Ensure tinker path parsing & error messages make sense (align with Python CLI semantics).

#### T7.2 – CLI error mapping

* Simulate API errors (4xx, 5xx, timeout) via Bypass/mocks and assert:
  * CLI exits with non-zero status.
  * Human readable error messages similar to Python CLI (not necessarily identical wording, but same *content*).

**Quality Gate Q7:**

* CLI is stable enough for real users (no panics, helpful error messages).
* JSON output is parsable and suitable for scripting.

---

## 4. CI / Quality Gates Summary

At the end of each Phase, the Implementation Process already defines quality gates. For **testing** specifically:

* **Q0:** Wire contract fixtures exist and are trusted.
* **Q1:** Types: high coverage, JSON parity with fixtures; Dialyzer clean for Types.
* **Q2:** HTTP: retry matrix coverage; config & PoolKey tests; HTTP telemetry validated.
* **Q3:** Futures & Metrics: all union variants covered; metrics reduction matches Python semantics.
* **Q4:** Clients: no deadlocks; error handling robust; RateLimiter/ETS behaviors correct.
* **Q5:** Tokenization safe & functional; fallback plan documented if NIF caching unsafe.
* **Q6:** Integration flows match Python on representative scenarios; concurrency stable.
* **Q7:** CLI behaves correctly and exposes data in table/JSON formats, with good error handling.

Each gate is enforced via:

```bash
mix test
mix dialyzer
mix credo --strict
mix format --check-formatted
```

Plus the additional **golden/parity tests** described above.

---

## 5. How to use this doc day-to-day

* When starting a Phase, read:
  * Implementation Process → Phase N
  * This doc → Testing for Phase N
  * `0001`/`0100` for deeper context if needed.

* At the end of the Phase:
  * Ensure all T-phase tests exist and pass.
  * Confirm Q-gate N is ticked.
  * Only then move to next Phase.

If you'd like, next we can draft:

* Concrete ExUnit skeletons for the **Phase 1 type tests**, or
* A minimal **"wire contract" fixture generator** script based on the Python SDK.