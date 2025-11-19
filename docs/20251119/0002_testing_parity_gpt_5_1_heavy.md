# Testing Parity & Python→Elixir Porting Plan

**This doc sits next to `0001_testing_strategy_gpt_5_1_extended.md`.**

* `0001` = *what* we're going to test in Elixir (layers, goals, examples).
* **This doc** = *how to systematically port / adapt the Python test suite* to achieve those goals.

Think of this as the **bridge** between:

* The existing Python tests (`test_*.py`, `mock_api_server.py`)
* The Elixir design docs (`00_overview` … `07_porting_strategy`)
* The new Elixir test tree you're about to build (`Tinkex.*Test` modules)

---

## 1. Objectives of the test-port

We're not doing a blind 1:1 translation of every pytest. The goal is:

1. **Behavioral parity where it matters to the wire:**
   * JSON shapes
   * enums / literals
   * metric reduction semantics
   * retry & backoff
   * queue-state / TryAgain behavior
   * futures & training sequencing
   * sampling / rate limiting behavior
   * telemetry event shape

2. **Confidence that Elixir-specific bits are correct:**
   * GenServer / Task patterns (no hangs, no crashes)
   * ETS-based SamplingClient / RateLimiter
   * Tinkex.Config threading & multi-tenant semantics
   * Telemetry integration via `:telemetry`
   * CLI behavior & error mapping

3. **A porting process that's repeatable:**
   * Every important Python test file is explicitly:
     * **MIRRORED** (port key behaviors)
     * **ADAPTED** (behavior same, implementation different)
     * **ACKED / SKIPPED** (documented why not needed)

---

## 2. Python test inventory → porting categories

### 2.1 Core Python tests (repo root)

| Python file                               | Main focus                                                                                   | Port category       |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------- |
| `test_chunked_fwdbwd_helpers.py`          | Metrics reduction (`_metrics_reduction`, `REDUCE_MAP` incl. `unique`, `slack`)               | **MIRROR**          |
| `test_client.py`                          | BaseClient options, headers, retries, timeouts, idempotency, `Retry-After`, `x-should-retry` | **ADAPT**           |
| `test_models.py`                          | Pydantic BaseModel quirks, unions, aliases, discriminated unions, Optional semantics, enums  | **ADAPT**           |
| `test_transform.py`                       | `PropertyInfo`, `transform()/async_transform`. Aliases, iso8601, base64, TypedDicts          | **SKIP/ADAPT-LITE** |
| `test_response.py`                        | `APIResponse` parsing, `parse(to=...)`, streaming vs non-streaming, union responses          | **ADAPT**           |
| `test_qs.py`                              | `_qs.Querystring` parsing/stringify; array & nested formats                                  | **ADAPT-LITE**      |
| `test_required_args.py`                   | `@required_args` decorator semantics                                                         | **SKIP**            |
| `test_streaming.py`                       | SSE parsing, unicode, chunk boundaries                                                       | **ADAPT-MIN**       |
| `test_files.py` / `test_extract_files.py` | multipart & `to_httpx_files`; file path handling                                             | **ADAPT-MIN**       |
| `test_deepcopy.py`                        | `deepcopy_minimal` behavior                                                                  | **SKIP**            |

### 2.2 Test utilities

| Python file                 | Main focus                     | Port category |
| --------------------------- | ------------------------------ | ------------- |
| `test_utils/test_proxy.py`  | `LazyProxy` behavior           | **SKIP**      |
| `test_utils/test_typing.py` | generic type helpers, TypeVars | **SKIP**      |

### 2.3 Telemetry & internal behavior

| Python file             | Main focus                      | Port category    |
| ----------------------- | ------------------------------- | ---------------- |
| `lib/telemetry_test.py` | Telemetry events, session index | **MIRROR/ADAPT** |

### 2.4 Mock server

| Python file          | Main focus                                             | Port category              |
| -------------------- | ------------------------------------------------------ | -------------------------- |
| `mock_api_server.py` | FastAPI mock covering training, sampling, futures etc. | **USE for contract tests** |

---

## 3. Target Elixir test layout (from 0001, now more concrete)

This is the **proposed Elixir `test/` map**, annotated with where each comes from in Python:

### 3.1 Pure unit / types / helpers

* `test/tinkex/metrics_reduction_test.exs`
  * Mirrors: `test_chunked_fwdbwd_helpers.py`
  * Ensures `Tinkex.MetricsReduction.reduce/1` = Python `_metrics_reduction`:
    * `:mean` → **weighted** mean (by `length(loss_fn_outputs)`)
    * `:sum`, `:min`, `:max`, `:slack`, `:unique` semantics
    * Only metrics present in *all* results are reduced
    * `:unique` emits suffixed keys `*_2`, `*_3`, …

* `test/tinkex/types_sample_request_test.exs`
  * Source: `test_models.py`, `types/sample_request.py`, `01_type_system.md`
  * Focus:
    * `prompt_logprobs` tri-state `nil | true | false`
    * Optional fields encode as `"null"` (not stripped)
    * `sampling_session_id`, `base_model`, `model_path`, `seq_id` optional semantics.

* `test/tinkex/types_tensor_data_test.exs`
  * Source: `test_models.py`, `types/tensor_data.py`
  * Focus:
    * `TensorData.from_nx/1` aggressive casting `f64→float32`, `s32→int64`, `uint→int64`
    * `shape: nil` vs list semantics
    * Roundtrip `Nx.tensor` → `TensorData` → `Nx` yields correct dtype/shape.

* `test/tinkex/types_request_error_category_test.exs`
  * Source: `types/request_error_category.py`, `05_error_handling.md`
  * Focus:
    * Parser is case-insensitive; wire uses lowercase `"unknown"/"server"/"user"`
    * `retryable?/1` semantics per truth table.

* `test/tinkex/types_image_chunk_test.exs`
  * Source: `types/image_chunk.py`, `01_type_system.md` corrections
  * Focus:
    * Field names exactly: `data`, `format`, `height`, `width`, `tokens`, `type`
    * Base64 encode/decode in constructors
    * `length/1` uses `tokens`.

* `test/tinkex/types_image_asset_pointer_chunk_test.exs`
  * Source: `types/image_asset_pointer_chunk.py`
  * Focus:
    * `location` field name (not `asset_id`)
    * Required fields present & encoded correctly.

**Adaptation rule:**
From `test_models.py`, only port tests that affect **JSON wire format** or semantics that survive Pydantic→Elixir (e.g., Optional, enums, discriminated unions when they map to JSON tags). Skip tests that only validate Pydantic's internal type coercion or error messages.

---

### 3.2 HTTP layer & config

* `test/tinkex/http_client_test.exs`
  * Mirrors: `test_client.py` (+ `_base_client.py` behavior)
  * Focus:
    * Default base URL & override via `Tinkex.Config`
    * `x-api-key` header; user headers merging
    * `follow_redirects` equivalent behavior (Elixir: Finch + manual handling or not)
    * `Retry-After` parsing (`retry-after-ms`, numeric `retry-after`) → `retry_after_ms` on `Tinkex.Error`
    * `x-should-retry` header honored before status code
    * Retries for 5xx, 408, 429 only, with exponential backoff
    * Timeouts: config timeout vs per-call override, mapping to Finch `receive_timeout`.

* `test/tinkex/config_test.exs`
  * Derived from `test_client.copy()` tests and docs in `02_client_architecture.md`, `07_porting_strategy.md`
  * Focus:
    * `Tinkex.Config.new/1` picks env defaults when omitted
    * Struct fields: `base_url`, `api_key`, `timeout`, `max_retries`, `http_pool`, `user_metadata`
    * Multiple configs with different `api_key`s can coexist; ensures no global state.

**Adaptation:**
We **do not** replicate httpx-level details (e.g. `DefaultAioHttpClient`, proxies) unless we intentionally support them. For each Python test in `test_client.py`, categorize:

* **Keep:** anything about headers, retry, timeout, base_url, `Retry-After`, `x-should-retry`.
* **Drop:** httpx-specific features (proxy env vars, specific transport types) unless we add the feature.

---

### 3.3 Client-level behavior (Training / Sampling / Rest)

* `test/tinkex/training_client_test.exs`
  * Sources: `lib/public_interfaces/training_client.py`, `chunked_fwdbwd_helpers.py`, `03_async_model.md`, `02_client_architecture.md`
  * Focus:
    * Chunking rules: `MAX_CHUNK_LEN = 128`, `MAX_CHUNK_NUMBER_COUNT = 500_000`
    * **Sequencing**: for multiple `forward_backward` calls, sequence IDs increase and chunk request order is preserved
    * On error during submit:
      * `forward_backward/4` returns `{:error, %Tinkex.Error{}}`, GenServer stays alive
    * Combined `ForwardBackwardOutput`:
      * `loss_fn_outputs` concatenation
      * `metrics` via `Tinkex.MetricsReduction.reduce/1` (not naïve mean)
    * `optim_step/2` uses increasing `seq_id` and returns structured metrics if present.

* `test/tinkex/sampling_client_test.exs`
  * Sources: `lib/public_interfaces/sampling_client.py`, `02_client_architecture.md`, `03_async_model.md`
  * Focus:
    * ETS entry created on init; removed via `SamplingRegistry` on process exit
    * `sample/4` reads config from ETS (no GenServer.call bottleneck)
    * Request IDs from atomics; unique per client
    * When `Tinkex.API.Sampling.asample` returns `{:error, %Tinkex.Error{status: 429, retry_after_ms: ms}}`:
      * `RateLimiter` for `{base_url, api_key}` set to now+ms
      * Subsequent calls wait on `RateLimiter.wait_for_backoff/1`
    * Mixed API keys / base_urls:
      * Two clients with *same* `{base_url, api_key}` share backoff
      * Different API keys remain independent.

* `test/tinkex/rest_client_test.exs`
  * Based on `lib/public_interfaces/rest_client.py` and CLI commands
  * Focus:
    * `list_training_runs`, `list_checkpoints`, `list_user_checkpoints`, `get_training_run`, `get_checkpoint_archive_url`
    * Pagination semantics vs cursor in Python tests
    * Proper mapping of `Checkpoint`, `TrainingRun`, `Cursor`.

**Adaptation:**
We are not porting Python's `InternalClientHolder` tests; instead, we test the **Elixir OTP architecture**:

* `TrainingClient` GenServer behavior (mailbox ordering, synchronous send phase, async poll task)
* `SamplingClient` ETS + RateLimiter design (no central bottleneck)
* `SessionManager` / telemetry interplay via unit + Bypass-driven integration tests.

---

### 3.4 Futures & queue state backpressure

* `test/tinkex/future_poll_test.exs`
  * Sources: `lib/api_future_impl.py`, `types/future_retrieve_response.py`, `03_async_model.md`
  * Focus:
    * Polling over `FuturePendingResponse`, `FutureCompletedResponse`, `FutureFailedResponse`, `TryAgainResponse` union:
      * `status: "pending"` → backoff & retry
      * `status: "completed"` → returns decoded result
      * `status: "failed"` + `category :user` → no retry
      * `TryAgainResponse` with `queue_state: "paused_rate_limit"` / `"paused_capacity"`:
        * Telemetry event `[:tinkex, :queue, :state_change]`
        * Backoff behavior (e.g. ~1s) before next poll
    * Timeout behavior: `poll/2` respects optional timeout (like `APIFuture.result(timeout=...)`).

* `test/tinkex/queue_state_observer_test.exs`
  * If you implement `QueueStateObserver` behaviour in Training/Sampling clients, test:
    * `on_queue_state_change/1` invoked with parsed queue state
    * Logging / instrumentation.

---

### 3.5 Telemetry

* `test/tinkex/telemetry_test.exs` (Elixir)
  * Mirror concepts from `lib/telemetry_test.py`:
    * Telemetry events for:
      * HTTP request stop/exception: `[:tinkex, :http, :request, :stop]`
      * Retry events: `[:tinkex, :retry]`
      * Training operations: `[:tinkex, :training, :forward_backward, :stop]`
      * Sampling operations: `[:tinkex, :sampling, :sample, :stop]`
    * `event_session_index` increments per event (like Python `_session_index`)
    * Env-based enable/disable (`TINKEX_TELEMETRY` or similar).

* `test/tinkex/telemetry_reporter_test.exs`
  * Based on `Telemetry.Reporter` design in `06_telemetry.md`:
    * Batching & flushing when queue size ≥ threshold
    * Periodic flush interval
    * Behavior when telemetry endpoint errors (no crash, log only).

---

### 3.6 CLI

* `test/tinkex/cli_checkpoint_test.exs`
* `test/tinkex/cli_run_test.exs`
* `test/tinkex/cli_version_test.exs`

Modeled on `tinker/cli/commands/*.py`:

* Use `System.cmd/3` or `Mix.Tasks` helpers to run CLI entrypoints.
* Capture stdout/stderr (e.g. `ExUnit.CaptureIO`) to assert:
  * `run list` prints JSON and table variants
  * `checkpoint list` uses pagination semantics like Python CLI (limit/offset)
  * Error mapping from underlying `Tinkex.Error` to human-readable CLI errors.

---

### 3.7 HTTP utilities / QS / files

Only port what you actually re-implement in Elixir:

* If you implement a custom querystring module:
  * `test/tinkex/querystring_test.exs` — mirror just the cases you use:
    * `["a", "b"]` → `"a=1&b=2"` or similar
    * nested objects if you rely on them.
* If you *don't* implement multi-part file upload in v1:
  * Only minimal tests around `ImageChunk` and base64; skip multipart-specific behavior from `test_files.py` / `test_extract_files.py`.

---

## 4. Mapping Python tests → Elixir suites in detail

This section unpacks `0001`'s mapping with **explicit "keep/adapt/skip" per file**.

### 4.1 `test_chunked_fwdbwd_helpers.py` → `Tinkex.MetricsReductionTest`

Keep **all** semantics:

* ✅ Weighted mean (`:mean`)
* ✅ `:sum`, `:min`, `:max`
* ✅ `:slack` = `max(xs) - weighted_mean(xs)`
* ✅ `:unique`:
  * first value under base key
  * subsequent under `key_2`, `key_3`, …

Port the following test shapes:

* Single vs multiple results
* Mixed metrics (`clock_cycle:unique` + `other_metric:mean`)
* Empty results
* Missing metric keys (metric omitted if not present in all results).

Elixir tests should **not** rely on any Python-specific helpers; simulate `ForwardBackwardOutput` as plain maps:

```elixir
defp mk_result(metrics, n_outputs \\ 1) do
  %{
    metrics: metrics,
    loss_fn_outputs: Enum.map(1..n_outputs, fn _ -> :dummy end)
  }
end
```

### 4.2 `test_client.py` → `Tinkex.HTTP*` & `Tinkex.ConfigTest`

Port the following functional areas:

* **Base URL orchestration**
  * Default base_url from config/env
  * Overriding via `Tinkex.Config.new(base_url: ...)`
  * Combining `base_url` + relative path into final URL.

* **Headers**
  * `x-api-key` always present if `api_key` is configured
  * User headers in `opts[:headers]` override defaults (like default `content-type`).

* **Timeouts & retries**
  * `max_retries` from config/opts
  * Retry conditions: 5xx, 408, 429 only
  * `Retry-After` / `retry-after-ms` respected
  * `x-should-retry: true/false` overrides default logic.

* **Idempotency**
  * If you implement idempotency keys (not strictly required in Elixir v1), port minimal tests:
    * Provide key via opts → header present
    * Without key, fallback to generated value.

Skip or drastically simplify:

* httpx client pool internals
* proxy env variables tests (unless you add them)
* memory leak tests using `tracemalloc`.

### 4.3 `test_models.py` → `Tinkex.Types.*Test`

Implementation guidance:

* **KEEP** tests that assert:
  * `StopReason` literal values and JSON encoding
  * `TensorDtype` allowed values (`"int64"`, `"float32"`)
  * Optional vs required field semantics that impact JSON shape
  * Discriminated unions that correspond to real wire unions (e.g. `FutureRetrieveResponse`, `TelemetryEvent`).

* **ADAPT** to Elixir:
  * Instead of Pydantic `BaseModel.construct`, use direct `%Struct{}` creation + `Jason.encode!/1` and `Jason.decode!/1`.
  * Use pattern-matching for union-like behavior.

* **SKIP**:
  * Pydantic-specific behaviors (e.g. `model.dict()` intricacies, alias handling outside wire-critical cases)
  * `model_dump_json` vs `model_dump` compatibility tests.

The idea is to enforce **wire equivalence**, not full Pydantic emulation.

### 4.4 `test_transform.py` → Elixir?

Python's `transform()` is a rich TypedDict + Annotated + PropertyInfo system. In Elixir, you are **not** building a comparable generic transformer; you're encoding structs directly.

Port only the **conceptual pieces** you actually recreate:

* If you add a small helper for base64 / ISO8601 formatting, test that helper.
* Do **not** try to replicate annotated alias/system generically — it's unnecessary and brittle.

So: **no 1:1 transform port.** Just targeted tests for formatting helpers / JSON encoding done for specific structs.

### 4.5 `test_response.py` → `Tinkex.ResponseParsingTest`

Key points to adapt:

* In Python, `APIResponse.parse(to=...)` can:
  * Return Pydantic models, plain dicts, union types, `httpx.Response`, bools etc.

* In Elixir, you will likely:
  * Parse responses into plain maps/structs via `Jason` and explicit `decode` functions.

Port only:

* Union behavior for **wire unions** you care about:
  * `FutureRetrieveResponse` union
  * `TelemetryEvent` union
  * Any other `type`- or `status`-discriminated responses.

Write tests that:

* Given raw JSON from Bypass, your decoding logic correctly:
  * Produces the right struct type
  * Handles invalid / mismatched content gracefully (error or fallback).

---

## 5. Porting mechanics: pytest → ExUnit patterns

### 5.1 Parametrized tests

Python:

```python
@pytest.mark.parametrize("value", [1, 2, 3])
def test_thing(value): ...
```

Elixir:

```elixir
Enum.each([1, 2, 3], fn value ->
  test "thing with value=#{value}" do
    # use value bound from closure
  end
end)
```

Or just hand-unroll when it's clearer.

### 5.2 Fixtures / setup

Python uses fixtures (`client`, `async_client`, `respx_mock`, `mock_api_server`). Elixir equivalents:

* `setup` / `setup_all` for shared state
* `ExUnit.Case, async: true/false`
* `Bypass.open/0` inside `setup` to simulate endpoints.

Pattern:

```elixir
setup do
  bypass = Bypass.open()

  config =
    Tinkex.Config.new(
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test-key"
    )

  {:ok, bypass: bypass, config: config}
end
```

### 5.3 Mock server vs Bypass

Two test layers:

1. **Unit/integration (default):**
   * `Bypass` in Elixir, per-test or shared.
   * Define expectations inline (`Bypass.expect/4`).

2. **Contract suite (optional, CI-only):**
   * Spin up `mock_api_server.py` using `System.cmd/3` or Mix task → get port → plug into `Tinkex.Config.base_url`.
   * Run a **small** cross-language suite:
     * forward_backward
     * optim_step
     * sample
     * get_info / get_server_capabilities

The contract suite doesn't need to mirror every test; it just ensures we haven't misread the Python behavior or API shape.

---

## 6. Phased porting plan for tests (aligned with 07_porting_strategy)

You can align test-port work with the main implementation phases:

### Phase A: Types & helpers (Week 1–2)

* Implement:
  * `Tinkex.MetricsReduction` + tests
  * `Tinkex.Types` modules (`SampleRequest`, `TensorData`, `Image*`, `RequestErrorCategory`, `StopReason`, etc.)
* Port tests:
  * `test_chunked_fwdbwd_helpers.py` → `metrics_reduction_test.exs`
  * Core type semantics from `test_models.py` into individual `Types.*Test` modules.

### Phase B: HTTP & config (Week 2–3)

* Implement:
  * `Tinkex.Config`
  * `Tinkex.API` with retry, headers, `Retry-After`, `x-should-retry`
* Port tests:
  * `test_client.py` behaviors relevant to HTTP & config
  * Be strict about `Retry-After` and 429 semantics.

### Phase C: Training & Futures (Week 3–5)

* Implement:
  * `TrainingClient` GenServer with synchronous send + async poll
  * `Tinkex.Future` polling with TryAgain/QueueState, telemetry
* Port tests:
  * Behavior from `TrainingClient` Python methods (chunking, sequencing)
  * Future behavior from `api_future_impl.py` + `future_retrieve_response` types
  * Metrics combo via `Tinkex.MetricsReduction`.

### Phase D: Sampling & rate limiting (Week 5–6)

* Implement:
  * `SamplingClient` ETS architecture
  * `Tinkex.RateLimiter` keyed by `{base_url, api_key}`
  * `SamplingRegistry` for ETS cleanup
* Port tests:
  * Asynchronous sampling behavior (multiple concurrent calls)
  * Shared backoff semantics (429)
  * Correct wiring of `Tinkex.Config` into HTTP layer (prevent `Keyword.fetch!` crash).

### Phase E: CLI, telemetry & parity fixtures (Week 6–8)

* Implement:
  * Telemetry wiring and reporter
  * CLI commands
* Port/adapt:
  * Telemetry tests from `lib/telemetry_test.py`
  * CLI output tests modeled on Python CLI behavior
  * Golden JSON fixtures comparing Python Elixir output for a handful of critical payloads.

---

## 7. Explicit "skip list" (documented non-goals)

To avoid accidental scope creep, this doc also blesses certain *non*-ported areas:

* `test_utils/test_proxy.py` (LazyProxy): **no Elixir equivalent**, skip.
* `test_utils/test_typing.py`: generic TypeVar manipulation tests; irrelevant to Elixir.
* `test_required_args.py`: `@required_args` decorator semantics; you're not porting that abstraction.
* `test_deepcopy.py`: `deepcopy_minimal` behavior; immutability in Elixir makes this unnecessary.
* Streaming tests (`test_streaming.py`) **beyond** a couple of smoke tests that v1 streaming stubs: v1 streaming is explicitly non-production.

---

## 8. What "done" looks like

You can call the **testing port complete** when:

1. For each Python test file in §2, there is:
   * A corresponding Elixir test module (for MIRROR / ADAPT) **or**
   * An explicit note in this doc that it's intentionally skipped.

2. The following critical behaviors are covered by tests in Elixir:
   * Metrics reduction (all reductions, esp. `unique` and `slack`)
   * JSON wire semantics for key types (SampleRequest, TensorData, Image types, StopReason, RequestErrorCategory, Futures, Telemetry events)
   * Retry & backoff (5xx, 408, 429 + `Retry-After` and `x-should-retry`)
   * TrainingClient chunking, sequencing, metrics combination, error handling
   * Future polling with TryAgain/QueueState backpressure
   * SamplingClient ETS + RateLimiter behavior
   * Telemetry events and session indexing
   * CLI commands, both JSON and human output.

3. A small contract test suite against `mock_api_server.py` passes, using the Elixir client with the same scenarios as the Python SDK.

At that point, `0001` (strategy), this doc (porting plan), and the implementation docs (`00`–`07`) form a coherent story: **you know what to test, how to test it, and exactly how the Python suite maps onto the Elixir world.**
