\# Testing Parity \& Python→Elixir Porting Plan



\*\*This doc sits next to `0001\_testing\_strategy\_gpt\_5\_1\_extended.md`.\*\*



\* `0001` = \*what\* we’re going to test in Elixir (layers, goals, examples).

\* \*\*This doc\*\* = \*how to systematically port / adapt the Python test suite\* to achieve those goals.



Think of this as the \*\*bridge\*\* between:



\* The existing Python tests (`test\_\*.py`, `mock\_api\_server.py`)

\* The Elixir design docs (`00\_overview` … `07\_porting\_strategy`)

\* The new Elixir test tree you’re about to build (`Tinkex.\*Test` modules)



---



\## 1. Objectives of the test-port



We’re not doing a blind 1:1 translation of every pytest. The goal is:



1\. \*\*Behavioral parity where it matters to the wire:\*\*



&nbsp;  \* JSON shapes

&nbsp;  \* enums / literals

&nbsp;  \* metric reduction semantics

&nbsp;  \* retry \& backoff

&nbsp;  \* queue-state / TryAgain behavior

&nbsp;  \* futures \& training sequencing

&nbsp;  \* sampling / rate limiting behavior

&nbsp;  \* telemetry event shape



2\. \*\*Confidence that Elixir-specific bits are correct:\*\*



&nbsp;  \* GenServer / Task patterns (no hangs, no crashes)

&nbsp;  \* ETS-based SamplingClient / RateLimiter

&nbsp;  \* Tinkex.Config threading \& multi-tenant semantics

&nbsp;  \* Telemetry integration via `:telemetry`

&nbsp;  \* CLI behavior \& error mapping



3\. \*\*A porting process that’s repeatable:\*\*



&nbsp;  \* Every important Python test file is explicitly:



&nbsp;    \* \*\*MIRRORED\*\* (port key behaviors)

&nbsp;    \* \*\*ADAPTED\*\* (behavior same, implementation different)

&nbsp;    \* \*\*ACKED / SKIPPED\*\* (documented why not needed)



---



\## 2. Python test inventory → porting categories



\### 2.1 Core Python tests (repo root)



| Python file                               | Main focus                                                                                   | Port category       |

| ----------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------- |

| `test\_chunked\_fwdbwd\_helpers.py`          | Metrics reduction (`\_metrics\_reduction`, `REDUCE\_MAP` incl. `unique`, `slack`)               | \*\*MIRROR\*\*          |

| `test\_client.py`                          | BaseClient options, headers, retries, timeouts, idempotency, `Retry-After`, `x-should-retry` | \*\*ADAPT\*\*           |

| `test\_models.py`                          | Pydantic BaseModel quirks, unions, aliases, discriminated unions, Optional semantics, enums  | \*\*ADAPT\*\*           |

| `test\_transform.py`                       | `PropertyInfo`, `transform()/async\_transform`. Aliases, iso8601, base64, TypedDicts          | \*\*SKIP/ADAPT-LITE\*\* |

| `test\_response.py`                        | `APIResponse` parsing, `parse(to=...)`, streaming vs non-streaming, union responses          | \*\*ADAPT\*\*           |

| `test\_qs.py`                              | `\_qs.Querystring` parsing/stringify; array \& nested formats                                  | \*\*ADAPT-LITE\*\*      |

| `test\_required\_args.py`                   | `@required\_args` decorator semantics                                                         | \*\*SKIP\*\*            |

| `test\_streaming.py`                       | SSE parsing, unicode, chunk boundaries                                                       | \*\*ADAPT-MIN\*\*       |

| `test\_files.py` / `test\_extract\_files.py` | multipart \& `to\_httpx\_files`; file path handling                                             | \*\*ADAPT-MIN\*\*       |

| `test\_deepcopy.py`                        | `deepcopy\_minimal` behavior                                                                  | \*\*SKIP\*\*            |



\### 2.2 Test utilities



| Python file                 | Main focus                     | Port category |

| --------------------------- | ------------------------------ | ------------- |

| `test\_utils/test\_proxy.py`  | `LazyProxy` behavior           | \*\*SKIP\*\*      |

| `test\_utils/test\_typing.py` | generic type helpers, TypeVars | \*\*SKIP\*\*      |



\### 2.3 Telemetry \& internal behavior



| Python file             | Main focus                      | Port category    |

| ----------------------- | ------------------------------- | ---------------- |

| `lib/telemetry\_test.py` | Telemetry events, session index | \*\*MIRROR/ADAPT\*\* |



\### 2.4 Mock server



| Python file          | Main focus                                             | Port category              |

| -------------------- | ------------------------------------------------------ | -------------------------- |

| `mock\_api\_server.py` | FastAPI mock covering training, sampling, futures etc. | \*\*USE for contract tests\*\* |



---



\## 3. Target Elixir test layout (from 0001, now more concrete)



This is the \*\*proposed Elixir `test/` map\*\*, annotated with where each comes from in Python:



\### 3.1 Pure unit / types / helpers



\* `test/tinkex/metrics\_reduction\_test.exs`



&nbsp; \* Mirrors: `test\_chunked\_fwdbwd\_helpers.py`

&nbsp; \* Ensures `Tinkex.MetricsReduction.reduce/1` = Python `\_metrics\_reduction`:



&nbsp;   \* `:mean` → \*\*weighted\*\* mean (by `length(loss\_fn\_outputs)`)

&nbsp;   \* `:sum`, `:min`, `:max`, `:slack`, `:unique` semantics

&nbsp;   \* Only metrics present in \*all\* results are reduced

&nbsp;   \* `:unique` emits suffixed keys `\*\_2`, `\*\_3`, …



\* `test/tinkex/types\_sample\_request\_test.exs`



&nbsp; \* Source: `test\_models.py`, `types/sample\_request.py`, `01\_type\_system.md`

&nbsp; \* Focus:



&nbsp;   \* `prompt\_logprobs` tri-state `nil | true | false`

&nbsp;   \* Optional fields encode as `"null"` (not stripped)

&nbsp;   \* `sampling\_session\_id`, `base\_model`, `model\_path`, `seq\_id` optional semantics.



\* `test/tinkex/types\_tensor\_data\_test.exs`



&nbsp; \* Source: `test\_models.py`, `types/tensor\_data.py`

&nbsp; \* Focus:



&nbsp;   \* `TensorData.from\_nx/1` aggressive casting `f64→float32`, `s32→int64`, `uint→int64`

&nbsp;   \* `shape: nil` vs list semantics

&nbsp;   \* Roundtrip `Nx.tensor` → `TensorData` → `Nx` yields correct dtype/shape.



\* `test/tinkex/types\_request\_error\_category\_test.exs`



&nbsp; \* Source: `types/request\_error\_category.py`, `05\_error\_handling.md`

&nbsp; \* Focus:



&nbsp;   \* Parser is case-insensitive; wire uses lowercase `"unknown"/"server"/"user"`

&nbsp;   \* `retryable?/1` semantics per truth table.



\* `test/tinkex/types\_image\_chunk\_test.exs`



&nbsp; \* Source: `types/image\_chunk.py`, `01\_type\_system.md` corrections

&nbsp; \* Focus:



&nbsp;   \* Field names exactly: `data`, `format`, `height`, `width`, `tokens`, `type`

&nbsp;   \* Base64 encode/decode in constructors

&nbsp;   \* `length/1` uses `tokens`.



\* `test/tinkex/types\_image\_asset\_pointer\_chunk\_test.exs`



&nbsp; \* Source: `types/image\_asset\_pointer\_chunk.py`

&nbsp; \* Focus:



&nbsp;   \* `location` field name (not `asset\_id`)

&nbsp;   \* Required fields present \& encoded correctly.



\*\*Adaptation rule:\*\*

From `test\_models.py`, only port tests that affect \*\*JSON wire format\*\* or semantics that survive Pydantic→Elixir (e.g., Optional, enums, discriminated unions when they map to JSON tags). Skip tests that only validate Pydantic’s internal type coercion or error messages.



---



\### 3.2 HTTP layer \& config



\* `test/tinkex/http\_client\_test.exs`



&nbsp; \* Mirrors: `test\_client.py` (+ `\_base\_client.py` behavior)

&nbsp; \* Focus:



&nbsp;   \* Default base URL \& override via `Tinkex.Config`

&nbsp;   \* `x-api-key` header; user headers merging

&nbsp;   \* `follow\_redirects` equivalent behavior (Elixir: Finch + manual handling or not)

&nbsp;   \* `Retry-After` parsing (`retry-after-ms`, numeric `retry-after`) → `retry\_after\_ms` on `Tinkex.Error`

&nbsp;   \* `x-should-retry` header honored before status code

&nbsp;   \* Retries for 5xx, 408, 429 only, with exponential backoff

&nbsp;   \* Timeouts: config timeout vs per-call override, mapping to Finch `receive\_timeout`.



\* `test/tinkex/config\_test.exs`



&nbsp; \* Derived from `test\_client.copy()` tests and docs in `02\_client\_architecture.md`, `07\_porting\_strategy.md`

&nbsp; \* Focus:



&nbsp;   \* `Tinkex.Config.new/1` picks env defaults when omitted

&nbsp;   \* Struct fields: `base\_url`, `api\_key`, `timeout`, `max\_retries`, `http\_pool`, `user\_metadata`

&nbsp;   \* Multiple configs with different `api\_key`s can coexist; ensures no global state.



\*\*Adaptation:\*\*

We \*\*do not\*\* replicate httpx-level details (e.g. `DefaultAioHttpClient`, proxies) unless we intentionally support them. For each Python test in `test\_client.py`, categorize:



\* \*\*Keep:\*\* anything about headers, retry, timeout, base\_url, `Retry-After`, `x-should-retry`.

\* \*\*Drop:\*\* httpx-specific features (proxy env vars, specific transport types) unless we add the feature.



---



\### 3.3 Client-level behavior (Training / Sampling / Rest)



\* `test/tinkex/training\_client\_test.exs`



&nbsp; \* Sources: `lib/public\_interfaces/training\_client.py`, `chunked\_fwdbwd\_helpers.py`, `03\_async\_model.md`, `02\_client\_architecture.md`

&nbsp; \* Focus:



&nbsp;   \* Chunking rules: `MAX\_CHUNK\_LEN = 128`, `MAX\_CHUNK\_NUMBER\_COUNT = 500\_000`

&nbsp;   \* \*\*Sequencing\*\*: for multiple `forward\_backward` calls, sequence IDs increase and chunk request order is preserved

&nbsp;   \* On error during submit:



&nbsp;     \* `forward\_backward/4` returns `{:error, %Tinkex.Error{}}`, GenServer stays alive

&nbsp;   \* Combined `ForwardBackwardOutput`:



&nbsp;     \* `loss\_fn\_outputs` concatenation

&nbsp;     \* `metrics` via `Tinkex.MetricsReduction.reduce/1` (not naïve mean)

&nbsp;   \* `optim\_step/2` uses increasing `seq\_id` and returns structured metrics if present.



\* `test/tinkex/sampling\_client\_test.exs`



&nbsp; \* Sources: `lib/public\_interfaces/sampling\_client.py`, `02\_client\_architecture.md`, `03\_async\_model.md`

&nbsp; \* Focus:



&nbsp;   \* ETS entry created on init; removed via `SamplingRegistry` on process exit

&nbsp;   \* `sample/4` reads config from ETS (no GenServer.call bottleneck)

&nbsp;   \* Request IDs from atomics; unique per client

&nbsp;   \* When `Tinkex.API.Sampling.asample` returns `{:error, %Tinkex.Error{status: 429, retry\_after\_ms: ms}}`:



&nbsp;     \* `RateLimiter` for `{base\_url, api\_key}` set to now+ms

&nbsp;     \* Subsequent calls wait on `RateLimiter.wait\_for\_backoff/1`

&nbsp;   \* Mixed API keys / base\_urls:



&nbsp;     \* Two clients with \*same\* `{base\_url, api\_key}` share backoff

&nbsp;     \* Different API keys remain independent.



\* `test/tinkex/rest\_client\_test.exs`



&nbsp; \* Based on `lib/public\_interfaces/rest\_client.py` and CLI commands

&nbsp; \* Focus:



&nbsp;   \* `list\_training\_runs`, `list\_checkpoints`, `list\_user\_checkpoints`, `get\_training\_run`, `get\_checkpoint\_archive\_url`

&nbsp;   \* Pagination semantics vs cursor in Python tests

&nbsp;   \* Proper mapping of `Checkpoint`, `TrainingRun`, `Cursor`.



\*\*Adaptation:\*\*

We are not porting Python’s `InternalClientHolder` tests; instead, we test the \*\*Elixir OTP architecture\*\*:



\* `TrainingClient` GenServer behavior (mailbox ordering, synchronous send phase, async poll task)

\* `SamplingClient` ETS + RateLimiter design (no central bottleneck)

\* `SessionManager` / telemetry interplay via unit + Bypass-driven integration tests.



---



\### 3.4 Futures \& queue state backpressure



\* `test/tinkex/future\_poll\_test.exs`



&nbsp; \* Sources: `lib/api\_future\_impl.py`, `types/future\_retrieve\_response.py`, `03\_async\_model.md`

&nbsp; \* Focus:



&nbsp;   \* Polling over `FuturePendingResponse`, `FutureCompletedResponse`, `FutureFailedResponse`, `TryAgainResponse` union:



&nbsp;     \* `status: "pending"` → backoff \& retry

&nbsp;     \* `status: "completed"` → returns decoded result

&nbsp;     \* `status: "failed"` + `category :user` → no retry

&nbsp;     \* `TryAgainResponse` with `queue\_state: "paused\_rate\_limit"` / `"paused\_capacity"`:



&nbsp;       \* Telemetry event `\[:tinkex, :queue, :state\_change]`

&nbsp;       \* Backoff behavior (e.g. ~1s) before next poll

&nbsp;   \* Timeout behavior: `poll/2` respects optional timeout (like `APIFuture.result(timeout=...)`).



\* `test/tinkex/queue\_state\_observer\_test.exs`



&nbsp; \* If you implement `QueueStateObserver` behaviour in Training/Sampling clients, test:



&nbsp;   \* `on\_queue\_state\_change/1` invoked with parsed queue state

&nbsp;   \* Logging / instrumentation.



---



\### 3.5 Telemetry



\* `test/tinkex/telemetry\_test.exs` (Elixir)



&nbsp; \* Mirror concepts from `lib/telemetry\_test.py`:



&nbsp;   \* Telemetry events for:



&nbsp;     \* HTTP request stop/exception: `\[:tinkex, :http, :request, :stop]`

&nbsp;     \* Retry events: `\[:tinkex, :retry]`

&nbsp;     \* Training operations: `\[:tinkex, :training, :forward\_backward, :stop]`

&nbsp;     \* Sampling operations: `\[:tinkex, :sampling, :sample, :stop]`

&nbsp;   \* `event\_session\_index` increments per event (like Python `\_session\_index`)

&nbsp;   \* Env-based enable/disable (`TINKEX\_TELEMETRY` or similar).



\* `test/tinkex/telemetry\_reporter\_test.exs`



&nbsp; \* Based on `Telemetry.Reporter` design in `06\_telemetry.md`:



&nbsp;   \* Batching \& flushing when queue size ≥ threshold

&nbsp;   \* Periodic flush interval

&nbsp;   \* Behavior when telemetry endpoint errors (no crash, log only).



---



\### 3.6 CLI



\* `test/tinkex/cli\_checkpoint\_test.exs`

\* `test/tinkex/cli\_run\_test.exs`

\* `test/tinkex/cli\_version\_test.exs`



Modeled on `tinker/cli/commands/\*.py`:



\* Use `System.cmd/3` or `Mix.Tasks` helpers to run CLI entrypoints.

\* Capture stdout/stderr (e.g. `ExUnit.CaptureIO`) to assert:



&nbsp; \* `run list` prints JSON and table variants

&nbsp; \* `checkpoint list` uses pagination semantics like Python CLI (limit/offset)

&nbsp; \* Error mapping from underlying `Tinkex.Error` to human-readable CLI errors.



---



\### 3.7 HTTP utilities / QS / files



Only port what you actually re-implement in Elixir:



\* If you implement a custom querystring module:



&nbsp; \* `test/tinkex/querystring\_test.exs` — mirror just the cases you use:



&nbsp;   \* `\["a", "b"]` → `"a=1\&b=2"` or similar

&nbsp;   \* nested objects if you rely on them.

\* If you \*don’t\* implement multi-part file upload in v1:



&nbsp; \* Only minimal tests around `ImageChunk` and base64; skip multipart-specific behavior from `test\_files.py` / `test\_extract\_files.py`.



---



\## 4. Mapping Python tests → Elixir suites in detail



This section unpacks `0001`’s mapping with \*\*explicit “keep/adapt/skip” per file\*\*.



\### 4.1 `test\_chunked\_fwdbwd\_helpers.py` → `Tinkex.MetricsReductionTest`



Keep \*\*all\*\* semantics:



\* ✅ Weighted mean (`:mean`)

\* ✅ `:sum`, `:min`, `:max`

\* ✅ `:slack` = `max(xs) - weighted\_mean(xs)`

\* ✅ `:unique`:



&nbsp; \* first value under base key

&nbsp; \* subsequent under `key\_2`, `key\_3`, …



Port the following test shapes:



\* Single vs multiple results

\* Mixed metrics (`clock\_cycle:unique` + `other\_metric:mean`)

\* Empty results

\* Missing metric keys (metric omitted if not present in all results).



Elixir tests should \*\*not\*\* rely on any Python-specific helpers; simulate `ForwardBackwardOutput` as plain maps:



```elixir

defp mk\_result(metrics, n\_outputs \\\\ 1) do

&nbsp; %{

&nbsp;   metrics: metrics,

&nbsp;   loss\_fn\_outputs: Enum.map(1..n\_outputs, fn \_ -> :dummy end)

&nbsp; }

end

```



\### 4.2 `test\_client.py` → `Tinkex.HTTP\*` \& `Tinkex.ConfigTest`



Port the following functional areas:



\* \*\*Base URL orchestration\*\*



&nbsp; \* Default base\_url from config/env

&nbsp; \* Overriding via `Tinkex.Config.new(base\_url: ...)`

&nbsp; \* Combining `base\_url` + relative path into final URL.



\* \*\*Headers\*\*



&nbsp; \* `x-api-key` always present if `api\_key` is configured

&nbsp; \* User headers in `opts\[:headers]` override defaults (like default `content-type`).



\* \*\*Timeouts \& retries\*\*



&nbsp; \* `max\_retries` from config/opts

&nbsp; \* Retry conditions: 5xx, 408, 429 only

&nbsp; \* `Retry-After` / `retry-after-ms` respected

&nbsp; \* `x-should-retry: true/false` overrides default logic.



\* \*\*Idempotency\*\*



&nbsp; \* If you implement idempotency keys (not strictly required in Elixir v1), port minimal tests:



&nbsp;   \* Provide key via opts → header present

&nbsp;   \* Without key, fallback to generated value.



Skip or drastically simplify:



\* httpx client pool internals

\* proxy env variables tests (unless you add them)

\* memory leak tests using `tracemalloc`.



\### 4.3 `test\_models.py` → `Tinkex.Types.\*Test`



Implementation guidance:



\* \*\*KEEP\*\* tests that assert:



&nbsp; \* `StopReason` literal values and JSON encoding

&nbsp; \* `TensorDtype` allowed values (`"int64"`, `"float32"`)

&nbsp; \* Optional vs required field semantics that impact JSON shape

&nbsp; \* Discriminated unions that correspond to real wire unions (e.g. `FutureRetrieveResponse`, `TelemetryEvent`).



\* \*\*ADAPT\*\* to Elixir:



&nbsp; \* Instead of Pydantic `BaseModel.construct`, use direct `%Struct{}` creation + `Jason.encode!/1` and `Jason.decode!/1`.

&nbsp; \* Use pattern-matching for union-like behavior.



\* \*\*SKIP\*\*:



&nbsp; \* Pydantic-specific behaviors (e.g. `model.dict()` intricacies, alias handling outside wire-critical cases)

&nbsp; \* `model\_dump\_json` vs `model\_dump` compatibility tests.



The idea is to enforce \*\*wire equivalence\*\*, not full Pydantic emulation.



\### 4.4 `test\_transform.py` → Elixir?



Python’s `transform()` is a rich TypedDict + Annotated + PropertyInfo system. In Elixir, you are \*\*not\*\* building a comparable generic transformer; you’re encoding structs directly.



Port only the \*\*conceptual pieces\*\* you actually recreate:



\* If you add a small helper for base64 / ISO8601 formatting, test that helper.

\* Do \*\*not\*\* try to replicate annotated alias/system generically — it’s unnecessary and brittle.



So: \*\*no 1:1 transform port.\*\* Just targeted tests for formatting helpers / JSON encoding done for specific structs.



\### 4.5 `test\_response.py` → `Tinkex.ResponseParsingTest`



Key points to adapt:



\* In Python, `APIResponse.parse(to=...)` can:



&nbsp; \* Return Pydantic models, plain dicts, union types, `httpx.Response`, bools etc.



\* In Elixir, you will likely:



&nbsp; \* Parse responses into plain maps/structs via `Jason` and explicit `decode` functions.



Port only:



\* Union behavior for \*\*wire unions\*\* you care about:



&nbsp; \* `FutureRetrieveResponse` union

&nbsp; \* `TelemetryEvent` union

&nbsp; \* Any other `type`- or `status`-discriminated responses.



Write tests that:



\* Given raw JSON from Bypass, your decoding logic correctly:



&nbsp; \* Produces the right struct type

&nbsp; \* Handles invalid / mismatched content gracefully (error or fallback).



---



\## 5. Porting mechanics: pytest → ExUnit patterns



\### 5.1 Parametrized tests



Python:



```python

@pytest.mark.parametrize("value", \[1, 2, 3])

def test\_thing(value): ...

```



Elixir:



```elixir

Enum.each(\[1, 2, 3], fn value ->

&nbsp; test "thing with value=#{value}" do

&nbsp;   # use value bound from closure

&nbsp; end

end)

```



Or just hand-unroll when it’s clearer.



\### 5.2 Fixtures / setup



Python uses fixtures (`client`, `async\_client`, `respx\_mock`, `mock\_api\_server`). Elixir equivalents:



\* `setup` / `setup\_all` for shared state

\* `ExUnit.Case, async: true/false`

\* `Bypass.open/0` inside `setup` to simulate endpoints.



Pattern:



```elixir

setup do

&nbsp; bypass = Bypass.open()



&nbsp; config =

&nbsp;   Tinkex.Config.new(

&nbsp;     base\_url: "http://localhost:#{bypass.port}",

&nbsp;     api\_key: "test-key"

&nbsp;   )



&nbsp; {:ok, bypass: bypass, config: config}

end

```



\### 5.3 Mock server vs Bypass



Two test layers:



1\. \*\*Unit/integration (default):\*\*



&nbsp;  \* `Bypass` in Elixir, per-test or shared.

&nbsp;  \* Define expectations inline (`Bypass.expect/4`).



2\. \*\*Contract suite (optional, CI-only):\*\*



&nbsp;  \* Spin up `mock\_api\_server.py` using `System.cmd/3` or Mix task → get port → plug into `Tinkex.Config.base\_url`.

&nbsp;  \* Run a \*\*small\*\* cross-language suite:



&nbsp;    \* forward\_backward

&nbsp;    \* optim\_step

&nbsp;    \* sample

&nbsp;    \* get\_info / get\_server\_capabilities



The contract suite doesn’t need to mirror every test; it just ensures we haven’t misread the Python behavior or API shape.



---



\## 6. Phased porting plan for tests (aligned with 07\_porting\_strategy)



You can align test-port work with the main implementation phases:



\### Phase A: Types \& helpers (Week 1–2)



\* Implement:



&nbsp; \* `Tinkex.MetricsReduction` + tests

&nbsp; \* `Tinkex.Types` modules (`SampleRequest`, `TensorData`, `Image\*`, `RequestErrorCategory`, `StopReason`, etc.)

\* Port tests:



&nbsp; \* `test\_chunked\_fwdbwd\_helpers.py` → `metrics\_reduction\_test.exs`

&nbsp; \* Core type semantics from `test\_models.py` into individual `Types.\*Test` modules.



\### Phase B: HTTP \& config (Week 2–3)



\* Implement:



&nbsp; \* `Tinkex.Config`

&nbsp; \* `Tinkex.API` with retry, headers, `Retry-After`, `x-should-retry`

\* Port tests:



&nbsp; \* `test\_client.py` behaviors relevant to HTTP \& config

&nbsp; \* Be strict about `Retry-After` and 429 semantics.



\### Phase C: Training \& Futures (Week 3–5)



\* Implement:



&nbsp; \* `TrainingClient` GenServer with synchronous send + async poll

&nbsp; \* `Tinkex.Future` polling with TryAgain/QueueState, telemetry

\* Port tests:



&nbsp; \* Behavior from `TrainingClient` Python methods (chunking, sequencing)

&nbsp; \* Future behavior from `api\_future\_impl.py` + `future\_retrieve\_response` types

&nbsp; \* Metrics combo via `Tinkex.MetricsReduction`.



\### Phase D: Sampling \& rate limiting (Week 5–6)



\* Implement:



&nbsp; \* `SamplingClient` ETS architecture

&nbsp; \* `Tinkex.RateLimiter` keyed by `{base\_url, api\_key}`

&nbsp; \* `SamplingRegistry` for ETS cleanup

\* Port tests:



&nbsp; \* Asynchronous sampling behavior (multiple concurrent calls)

&nbsp; \* Shared backoff semantics (429)

&nbsp; \* Correct wiring of `Tinkex.Config` into HTTP layer (prevent `Keyword.fetch!` crash).



\### Phase E: CLI, telemetry \& parity fixtures (Week 6–8)



\* Implement:



&nbsp; \* Telemetry wiring and reporter

&nbsp; \* CLI commands

\* Port/adapt:



&nbsp; \* Telemetry tests from `lib/telemetry\_test.py`

&nbsp; \* CLI output tests modeled on Python CLI behavior

&nbsp; \* Golden JSON fixtures comparing Python Elixir output for a handful of critical payloads.



---



\## 7. Explicit “skip list” (documented non-goals)



To avoid accidental scope creep, this doc also blesses certain \*non\*-ported areas:



\* `test\_utils/test\_proxy.py` (LazyProxy): \*\*no Elixir equivalent\*\*, skip.

\* `test\_utils/test\_typing.py`: generic TypeVar manipulation tests; irrelevant to Elixir.

\* `test\_required\_args.py`: `@required\_args` decorator semantics; you’re not porting that abstraction.

\* `test\_deepcopy.py`: `deepcopy\_minimal` behavior; immutability in Elixir makes this unnecessary.

\* Streaming tests (`test\_streaming.py`) \*\*beyond\*\* a couple of smoke tests that v1 streaming stubs: v1 streaming is explicitly non-production.



---



\## 8. What “done” looks like



You can call the \*\*testing port complete\*\* when:



1\. For each Python test file in §2, there is:



&nbsp;  \* A corresponding Elixir test module (for MIRROR / ADAPT) \*\*or\*\*

&nbsp;  \* An explicit note in this doc that it’s intentionally skipped.



2\. The following critical behaviors are covered by tests in Elixir:



&nbsp;  \* Metrics reduction (all reductions, esp. `unique` and `slack`)

&nbsp;  \* JSON wire semantics for key types (SampleRequest, TensorData, Image types, StopReason, RequestErrorCategory, Futures, Telemetry events)

&nbsp;  \* Retry \& backoff (5xx, 408, 429 + `Retry-After` and `x-should-retry`)

&nbsp;  \* TrainingClient chunking, sequencing, metrics combination, error handling

&nbsp;  \* Future polling with TryAgain/QueueState backpressure

&nbsp;  \* SamplingClient ETS + RateLimiter behavior

&nbsp;  \* Telemetry events and session indexing

&nbsp;  \* CLI commands, both JSON and human output.



3\. A small contract test suite against `mock\_api\_server.py` passes, using the Elixir client with the same scenarios as the Python SDK.



At that point, `0001` (strategy), this doc (porting plan), and the implementation docs (`00`–`07`) form a coherent story: \*\*you know what to test, how to test it, and exactly how the Python suite maps onto the Elixir world.\*\*



