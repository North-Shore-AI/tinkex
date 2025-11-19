\# 0101 – Phase-Aligned Testing Process for Tinkex



> \*\*This doc ties together:\*\*

>

> \* `0001\_testing\_strategy\_gpt\_5\_1\_extended.md` (what to test)

> \* `0100\_testing\_port\_plan` (Python→Elixir test mapping)

> \* `Tinkex SDK Implementation Process` (phased build)

>

> It answers: \*\*“Exactly what testing happens in each implementation phase, with what gates?”\*\*



---



\## 1. Role of this document



\* `0001` defines \*\*testing layers \& coverage goals\*\* (unit, HTTP, clients, futures, telemetry, CLI, contract).

\* `0100` defines \*\*how Python tests map onto Elixir\*\* (which files to mirror, adapt, or skip).

\* \*\*`0101` (this doc)\*\* defines a \*\*time-ordered testing workflow\*\*, phase by phase, matching the \*\*Implementation Process\*\* phases 0–7.



You should be able to read the Implementation Process and this doc side by side and see:



\* For each \*\*Phase N\*\*:



&nbsp; \* Which \*\*tests must exist\*\* before the phase is “done”.

&nbsp; \* What those tests are \*\*allowed to depend on\*\*.

&nbsp; \* How we \*\*prove parity\*\* with Python at that stage.



---



\## 2. Testing layers \& responsibilities (recap)



We’ll keep the same layered model from `0001`, but attach them to phases:



1\. \*\*Unit (pure)\*\*



&nbsp;  \* Types, helpers, MetricsReduction, TensorData, RequestErrorCategory, JSON encoding helpers.

2\. \*\*HTTP \& config\*\*



&nbsp;  \* Retry logic, headers, error mapping, `Retry-After`, `x-should-retry`, `Tinkex.Config`.

3\. \*\*Clients\*\*



&nbsp;  \* ServiceClient, TrainingClient, SamplingClient, RestClient; Bypass-based tests.

4\. \*\*Futures \& queue backpressure\*\*



&nbsp;  \* Future.poll, TryAgainResponse, QueueState, backoff semantics.

5\. \*\*Telemetry\*\*



&nbsp;  \* `:telemetry` events, reporter batching \& session index.

6\. \*\*CLI\*\*



&nbsp;  \* Commands \& error mapping.

7\. \*\*Contract / E2E\*\*



&nbsp;  \* Small suite against `mock\_api\_server.py` or real API.



Each phase of implementation “unlocks” more of these layers.



---



\## 3. Phase-by-Phase Testing Plan



\### Phase 0 – Wire Format Verification \& Baseline



\*\*Implementation goal:\*\*

Verify assumptions against live API / Python SDK before coding.



\*\*Testing goal:\*\*

Have a \*\*minimal, ad-hoc verification harness\*\* that produces a \*\*wire format report\*\* we’ll treat as a “golden contract” for Phase 1+.



\#### T0.1 – Wire format probes



For each critical item from the Implementation Process:



1\. \*\*StopReason\*\*



&nbsp;  \* Probe sampling endpoint at least twice:



&nbsp;    \* One run that stops by max tokens.

&nbsp;    \* One run that stops via explicit stop sequence.

&nbsp;  \* Record the raw JSON `stop\_reason` values.



2\. \*\*RequestErrorCategory\*\*



&nbsp;  \* Trigger a synthetic RequestFailedError (e.g. training or sampling with invalid input).

&nbsp;  \* Capture `category` field in JSON: confirm `"unknown" | "server" | "user"` and casing.



3\. \*\*Image types\*\*



&nbsp;  \* Call API with JSON `ImageChunk` / `ImageAssetPointerChunk` payload using Python SDK.

&nbsp;  \* Dump exactly what Python sends (`model\_dump\_json` / request body) to fixture files.



4\. \*\*SampleRequest.prompt\_logprobs\*\*



&nbsp;  \* Send three SampleRequests from Python:



&nbsp;    \* `prompt\_logprobs=None`

&nbsp;    \* `prompt\_logprobs=True`

&nbsp;    \* `prompt\_logprobs=False`

&nbsp;  \* Capture outgoing JSON bodies; confirm presence/omission and `null/true/false`.



5\. \*\*Rate limiting scope\*\*



&nbsp;  \* Use Python SDK to fire concurrent sampling requests with:



&nbsp;    \* Two clients using same `{base\_url, api\_key}`

&nbsp;    \* A third client with a different key or base\_url

&nbsp;  \* Observe whether rate limiting appears correlated; note in comments for Elixir RateLimiter tests (even if Python doesn’t share backoff state, Elixir’s shared limiter is deliberate).



6\. \*\*Tokenizer NIF safety (for later)\*\*



&nbsp;  \* Might be done in Elixir later, but plan the test (see Phase 5).



\*\*Output of Phase 0 testing:\*\*



\* A \*\*“wire contract” folder\*\* under `test/support/fixtures/wire/`:



&nbsp; \* `sample\_request\_prompt\_logprobs\_{null,true,false}.json`

&nbsp; \* `sampling\_stop\_reason\_{length,stop,...}.json`

&nbsp; \* `image\_chunk\_request.json`

&nbsp; \* `image\_asset\_pointer\_request.json`

&nbsp; \* Any error responses with `RequestErrorCategory`.



These fixtures become the \*\*canonical reference\*\* for type \& encoding tests in Phase 1.



\*\*Quality Gate Q0:\*\*



\* All listed probes run and produce fixtures.

\* Any discrepancy vs docs is explicitly noted and docs updated (types, enums, field names).

\* Team agrees “wire contract” is now the source of truth for Phase 1.



---



\### Phase 1 – Type System (Week 1, Days 4–7)



\*\*Implementation goal:\*\*

Elixir types that serialize/deserialize identically (for our purposes) to Python’s.



\*\*Testing goals:\*\*



\* Unit tests give \*\*strong guarantees\*\* that:



&nbsp; \* Wire-enforced fields are correct.

&nbsp; \* Optional/nullable behavior matches actual API.

&nbsp; \* Numeric casting behavior is correct for TensorData.

\* Golden JSON tests prove parity with Python’s fixtures from Phase 0.



\#### T1.1 – Enum \& literal tests



Modules: `Tinkex.Types.StopReason`, `LossFnType`, `RequestErrorCategory`, `TensorDtype`



Tests:



\* \*\*Roundtrip encode/decode:\*\*



&nbsp; \* For each enum value:



&nbsp;   \* Build Elixir value → `Jason.encode!` → assert expected string per wire fixture.

&nbsp;   \* For RequestErrorCategory: `parse/1` is case-insensitive; outputs atoms `:unknown | :server | :user`.



\* \*\*Error handling:\*\*



&nbsp; \* Unknown category string → `:unknown`.

&nbsp; \* For StopReason, ensure we either:



&nbsp;   \* Restrict to observed live values, OR

&nbsp;   \* Have a safe fallback for unknown strings (e.g. `:unknown` or `nil`) and document it.



\#### T1.2 – Struct JSON tests



Modules: `Tinkex.Types.SampleRequest`, `TensorData`, `ImageChunk`, `ImageAssetPointerChunk`, `ModelInput`, `Datum`, `ForwardBackwardOutput`, `OptimStepRequest`, etc.



Patterns:



1\. \*\*Type correctness tests\*\* (unit):



&nbsp;  \* Construction with required and optional fields.

&nbsp;  \* `@type` specs match actual usage (Dialyzer clean).



2\. \*\*Golden encoding tests:\*\*



&nbsp;  \* For each “wire critical” type, create a test like:



&nbsp;    ```elixir

&nbsp;    test "SampleRequest prompt\_logprobs encodes like Python fixtures" do

&nbsp;      req = %SampleRequest{ ... prompt\_logprobs: nil ... }

&nbsp;      json = Jason.encode!(req)



&nbsp;      assert json == File.read!("test/support/fixtures/wire/sample\_request\_prompt\_logprobs\_null.json")

&nbsp;    end

&nbsp;    ```



&nbsp;  \* Repeat for `true` and `false` fixture bodies.



3\. \*\*TensorData casting tests:\*\*



&nbsp;  \* Using Nx, ensure:



&nbsp;    \* `Nx.tensor(\[...], type: {:f, 64})` → `TensorData.dtype == :float32`.

&nbsp;    \* `Nx.tensor(\[...], type: {:s, 32})` → `:int64`.

&nbsp;    \* `uint` types → `:int64`.

&nbsp;  \* Roundtrip `to\_nx/1` respects `shape` (nil vs list).



4\. \*\*Image types tests:\*\*



&nbsp;  \* From fixtures:



&nbsp;    \* `ImageChunk.new(binary, :png, h, w, tokens)` → `Jason.encode!` equals Python fixture JSON (modulo ordering).

&nbsp;    \* `ImageAssetPointerChunk` uses `location` and matches fixture.



5\. \*\*Property tests (optional but recommended):\*\*



&nbsp;  \* With StreamData:



&nbsp;    \* Generate random lists of ints/floats and shapes; ensure `TensorData.from\_nx/1 |> to\_nx/1` roundtrips.



\*\*Quality Gate Q1:\*\*



\* All core types have unit tests + golden JSON tests where relevant.

\* No global “strip nils” logic; tests assert that `nil` becomes `null` in JSON when desired.

\* Coverage for `Tinkex.Types.\*` modules ~90%+.



---



\### Phase 2 – HTTP Layer \& Retry (Week 2, Days 1–3)



\*\*Implementation goal:\*\*

A robust HTTP layer that matches Python’s retry semantics and header behavior.



\*\*Testing goals:\*\*



\* Bypass-based tests simulate real HTTP responses covering the retry matrix.

\* Tinkex.Config is correctly threaded and multi-tenant safe.

\* No `Application.get\_env` usage during requests (only at config creation).



\#### T2.1 – Config \& PoolKey tests



Modules: `Tinkex.Config`, `Tinkex.PoolKey`



Tests:



\* Config overrides: `base\_url`, `api\_key`, `timeout`, `max\_retries`, `user\_metadata`.

\* `PoolKey.normalize\_base\_url/1`:



&nbsp; \* `https://example.com:443` → `https://example.com`

&nbsp; \* `http://example.com:80` → `http://example.com`

&nbsp; \* Non-standard ports preserved.



\#### T2.2 – HTTP retry matrix tests



Modules: `Tinkex.API` + helpers (with Bypass)



Key scenarios:



1\. \*\*200 OK without x-should-retry\*\*



&nbsp;  \* Single request, no retries.



2\. \*\*5xx with no x-should-retry\*\*



&nbsp;  \* Should retry up to `max\_retries`.

&nbsp;  \* Assert number of hits on Bypass by counting expectations.



3\. \*\*408 Timeout\*\*



&nbsp;  \* Treated as retryable.



4\. \*\*429 + Retry-After\*\*



&nbsp;  \* Response with headers:



&nbsp;    \* `retry-after-ms: "100"`

&nbsp;    \* or `retry-after: "3"`

&nbsp;  \* Verify `Tinkex.Error.retry\_after\_ms` is set (100 or 3000).

&nbsp;  \* When invoked via `with\_retries/3`, ensure it sleeps appropriately (can inject a fake sleep or assert ordering via timestamps/messages).



5\. \*\*x-should-retry: "true"/"false"\*\*



&nbsp;  \* Test a 4xx (e.g. 400) with `x-should-retry: "true"` → should retry.

&nbsp;  \* Test a 5xx with `x-should-retry: "false"` → should \*not\* retry.



6\. \*\*Error mapping\*\*



&nbsp;  \* Non-2xx responses map to `%Tinkex.Error{status: code, data: decoded\_json}`.



\#### T2.3 – Telemetry for HTTP



Modules: `Tinkex.API`, `Tinkex.Telemetry` (basic)



\* Attach temporary `:telemetry` handlers in tests to assert:



&nbsp; \* `\[:tinkex, :http, :request, :stop]` events emitted with `path`, `method`, `duration`.

&nbsp; \* `\[:tinkex, :retry]` emitted when retries occur.



\*\*Quality Gate Q2:\*\*



\* All retry branches (5xx, 408, 429, x-should-retry) exercised.

\* Config tests show no cross-contamination between clients.

\* Telemetry events validated for at least one request.



---



\### Phase 3 – Futures \& MetricsReduction (Week 2, Days 4–5)



\*\*Implementation goal:\*\*

`Tinkex.Future` polling logic \& `Tinkex.MetricsReduction` are correct and robust.



\*\*Testing goals:\*\*



\* Polling loops handle all variants of `FutureRetrieveResponse` union.

\* MetricsReduction unit tests match Python behavior exactly (using the Python-based reasoning and tests).



\#### T3.1 – MetricsReduction tests (unit)



Already outlined in `0100` and `0001`:



\* Weighted means across varying `loss\_fn\_outputs` lengths.

\* Each suffix strategy: `:sum`, `:min`, `:max`, `:mean`, `:slack`, `:unique`.

\* Empty input and missing metrics.



\#### T3.2 – Future.poll integration tests



Modules: `Tinkex.Future`, `Tinkex.API.Futures`



Using Bypass:



1\. \*\*Simple completion\*\*



&nbsp;  \* Sequence: `pending`, `pending`, `completed` → `{:ok, result}`.



2\. \*\*Failed with user error\*\*



&nbsp;  \* `status: "failed"` with `category: "user"` → no retry, immediate `{:error, ...}`.



3\. \*\*Failed with server error\*\*



&nbsp;  \* `status: "failed"` with `category: "server"` → treated as retryable in intermediate stage; eventually surfaces appropriately if logic re-polls or fails.



4\. \*\*TryAgainResponse with queue\_state\*\*



&nbsp;  \* Sequence:



&nbsp;    \* `{:ok, %{type: "try\_again", "queue\_state" => "paused\_rate\_limit"}}`

&nbsp;    \* then `pending`

&nbsp;    \* then `completed`.

&nbsp;  \* Verify:



&nbsp;    \* Telemetry event `\[:tinkex, :queue, :state\_change]` emitted with `queue\_state: "paused\_rate\_limit"`.

&nbsp;    \* Backoff is applied (you can assert via message timings or by counting Bypass expectations after increments).



5\. \*\*Timeout handling\*\*



&nbsp;  \* Provide short timeout to `poll/2` and ensure it returns error after expected elapsed time (don’t let tests actually sleep long; you can stub `Process.sleep/1` via Mox or use a small threshold).



\*\*Quality Gate Q3:\*\*



\* All Future response variants tested.

\* MetricsReduction tests pass and match both your own reasoning and (optionally) Python golden metrics if you capture them.



---



\### Phase 4 – Client Architecture (Week 3–4)



\*\*Implementation goal:\*\*

ServiceClient, TrainingClient, SamplingClient, SessionManager, RateLimiter, SamplingRegistry all wired and safe.



\*\*Testing goals:\*\*



\* GenServers are robust: no deadlocks, no “caller never gets reply” scenarios.

\* ETS \& RateLimiter semantics enforced (no split-brains).

\* TrainingClient sequencing \& SamplingClient concurrency validated.



\#### T4.1 – TrainingClient behavior



Modules: `Tinkex.TrainingClient`



Tests (likely `async: false` because of Bypass and concurrency):



1\. \*\*Sequential chunk submission\*\*



&nbsp;  \* For a large batch that triggers multiple chunks:



&nbsp;    \* Bypass expects N `forward\_backward` calls in order; assert they arrive sequentially.

&nbsp;  \* Two consecutive `forward\_backward` calls:



&nbsp;    \* Confirm chunk requests from second call only occur after first call’s chunk sends are complete (inspected via recorded messages in the test).



2\. \*\*Polling Task safety\*\*



&nbsp;  \* Simulate a failing poll (e.g. Bypass returns invalid JSON for `/future/retrieve` after first `pending`):



&nbsp;    \* Verify `TrainingClient.forward\_backward` still replies with `{:error, %Tinkex.Error{}}` instead of hanging.

&nbsp;    \* Check that the TrainingClient process is still alive after the error.



3\. \*\*GenServer.reply ArgumentError rescue\*\*



&nbsp;  \* Simulate the caller dying before Task replies:



&nbsp;    \* Fire a `forward\_backward` call from a short-lived process, kill the caller before Task completes.

&nbsp;    \* Ensure the Task does not crash the VM when `GenServer.reply` raises `ArgumentError`.



4\. \*\*Metrics combination\*\*



&nbsp;  \* Use Bypass to return multiple Futures whose results include metrics with different suffixes.

&nbsp;  \* Assert the final `ForwardBackwardOutput.metrics` uses `Tinkex.MetricsReduction`.



\#### T4.2 – SamplingClient + RateLimiter + SamplingRegistry



Modules: `Tinkex.SamplingClient`, `Tinkex.RateLimiter`, `Tinkex.SamplingRegistry`



Tests:



1\. \*\*ETS config presence\*\*



&nbsp;  \* After starting SamplingClient, `:ets.lookup(:tinkex\_sampling\_clients, {:config, pid})` returns config struct.

&nbsp;  \* After the process exits (normal or `:kill`), ETS entry is removed by `SamplingRegistry`.



2\. \*\*Shared RateLimiter across `{base\_url, api\_key}`\*\*



&nbsp;  \* Start two SamplingClients with same config; ensure they share the same limiter (e.g. `for\_key/1` returns same ETS entry / atomics ref).

&nbsp;  \* Start client with different key; limiter reference is distinct.



3\. \*\*insert\_new semantics\*\*



&nbsp;  \* Simulate two callers racing to create limiter (you can spawn tasks that call `for\_key/1` concurrently).

&nbsp;  \* Ensure resulting ETS table has only one entry for the key.



4\. \*\*429 behavior\*\*



&nbsp;  \* Bypass: first call returns 429 with `retry-after-ms: "10"`; second call returns success.

&nbsp;  \* Confirm:



&nbsp;    \* First call returns `{:error, %Tinkex.Error{status: 429, retry\_after\_ms: 10}}`.

&nbsp;    \* Subsequent calls wait for RateLimiter backoff (can control with small ms and assert ordering via messages).



5\. \*\*No GenServer bottleneck\*\*



&nbsp;  \* Fire many concurrent `SamplingClient.sample` invocations (e.g. 100 tasks).

&nbsp;  \* Assert:



&nbsp;    \* All tasks complete.

&nbsp;    \* RateLimiter properly backs off when you inject a 429 after some threshold.



\#### T4.3 – SessionManager \& ServiceClient



Modules: `Tinkex.SessionManager`, `Tinkex.ServiceClient`



Tests:



\* Session creation:



&nbsp; \* Bypass for `/create\_session` returning valid session\_id.

&nbsp; \* ServiceClient init uses this and stores in state.



\* Heartbeat:



&nbsp; \* SessionManager periodically sends heartbeat; Bypass assert hits on `/session\_heartbeat` endpoint.



\* Client creation:



&nbsp; \* `ServiceClient.create\_lora\_training\_client` returns a `TrainingClient` pid tied to the same config supplied at start.



\*\*Quality Gate Q4:\*\*



\* TrainingClient has robust tests around sequencing \& Task safety.

\* SamplingClient/RateLimiter/Registry behave correctly under concurrency.

\* No known deadlocks or crash-on-error patterns in clients.



---



\### Phase 5 – Tokenization (Week 5, Days 1–2)



\*\*Implementation goal:\*\*

Safe, lean tokenization using `tokenizers` NIF with caching.



\*\*Testing goals:\*\*



\* Prove NIF handles are safe to share via ETS or implement safe alternative.

\* Tokenizer ID resolution matches Python semantics (including Llama-3 hack).



\#### T5.1 – NIF safety test



Module: `Tinkex.Tokenizer` + test support ETS table



\* The test described in the Implementation doc:



&nbsp; \* Create tokenizer in Process A, store in ETS.

&nbsp; \* Use it from Process B via ETS lookup and call encode.

&nbsp; \* Assert no crash; ensure tokens returned are a list of integers.



If unsafe:



\* Add alternative tests validating whichever safe design you choose (e.g. a TokenizerServer that owns the handles).



\#### T5.2 – TokenizerId resolution tests



Modules: `Tinkex.Tokenizer`, `Tinkex.TrainingClient.get\_info/1` (or equivalent)



\* Simulate `get\_info` responses via Bypass:



&nbsp; \* With `tokenizer\_id` set.

&nbsp; \* Without `tokenizer\_id`, with model\_name containing "Llama-3".

&nbsp; \* Without `tokenizer\_id`, unknown model.



\* Assert:



&nbsp; \* For Llama-3: `"baseten/Meta-Llama-3-tokenizer"` used.

&nbsp; \* For other models: fallback to `model\_name`.



\#### T5.3 – Encode helper tests



\* `encode(text, model\_name)` returns a non-empty list of ints for known model (use local or test-specific HF tokenizer).

\* `ModelInput.from\_text/2` uses the tokenizer and produces a `ModelInput` with one `EncodedTextChunk` with matching length.



\*\*Quality Gate Q5:\*\*



\* Tokenization is functional and tested.

\* Caching behavior safe per NIF semantics.



---



\### Phase 6 – Integration \& Parity (Week 5–6)



\*\*Implementation goal:\*\*

End-to-end workflows and Python parity.



\*\*Testing goals:\*\*



\* Use golden fixtures and/or mock API server to confirm behavior matches Python SDK for representative flows.



\#### T6.1 – Contract tests vs `mock\_api\_server.py` (optional but recommended)



\* Spin up `mock\_api\_server.py` from the repo (or a subset of its routes).

\* Integration tests:



&nbsp; \* Simple `forward\_backward` on a small batch; compare metrics and shapes vs Python results.

&nbsp; \* `optim\_step` + `forward\_backward` chained.

&nbsp; \* `save\_weights\_for\_sampler` → `SamplingClient.sample`.

&nbsp; \* `get\_info` plus tokenization check.



Record any differences and either:



\* Fix Elixir implementation to match; or

\* Document deliberate deviations (e.g. enhanced RateLimiter semantics).



\#### T6.2 – Golden JSON parity tests



For functions where you can easily capture Python request bodies:



\* Compare Python and Elixir JSON for:



&nbsp; \* `ForwardBackwardRequest`

&nbsp; \* `OptimStepRequest`

&nbsp; \* `SampleRequest` (various modes: with sampling\_session\_id vs base\_model/model\_path)

&nbsp; \* `FutureRetrieveRequest` variants.



Even if the key ordering differs, equality on decoded maps should hold.



\#### T6.3 – Multi-client concurrency



Scenarios:



1\. \*\*Two training clients + many sampling clients:\*\*



&nbsp;  \* Ensure no global state leaks (e.g. Config from one is not used by another).

&nbsp;  \* Rate limiting per `{base\_url, api\_key}` still holds.



2\. \*\*Error recovery:\*\*



&nbsp;  \* With Bypass, simulate intermittent 5xx / 429; ensure:



&nbsp;    \* No deadlocks.

&nbsp;    \* Errors eventually surface correctly after retries.



\*\*Quality Gate Q6:\*\*



\* Core flows (train, optimize, save, sample) pass against mock or real API.

\* Parity tests show Elixir and Python produce equivalent request/response shapes for canonical scenarios.



---



\### Phase 7 – CLI \& Documentation (Week 7–8)



\*\*Implementation goal:\*\*

User-facing CLI + docs.



\*\*Testing goals:\*\*



\* CLI commands behave like Python CLI in terms of options, output shapes, and error handling.



\#### T7.1 – CLI smoke tests



Use `ExUnit.CaptureIO` or `System.cmd/3`:



\* `tinkex version`



&nbsp; \* Should print version string from Elixir package.



\* `tinkex run list`



&nbsp; \* With Bypass or mock RestClient, assert:



&nbsp;   \* Table output contains correct headers and rows.

&nbsp;   \* `--format json` prints valid JSON with expected keys.



\* `tinkex checkpoint list` / `checkpoint info`



&nbsp; \* Ensure tinker path parsing \& error messages make sense (align with Python CLI semantics).



\#### T7.2 – CLI error mapping



\* Simulate API errors (4xx, 5xx, timeout) via Bypass/mocks and assert:



&nbsp; \* CLI exits with non-zero status.

&nbsp; \* Human readable error messages similar to Python CLI (not necessarily identical wording, but same \*content\*).



\*\*Quality Gate Q7:\*\*



\* CLI is stable enough for real users (no panics, helpful error messages).

\* JSON output is parsable and suitable for scripting.



---



\## 4. CI / Quality Gates Summary



At the end of each Phase, the Implementation Process already defines quality gates. For \*\*testing\*\* specifically:



\* \*\*Q0:\*\* Wire contract fixtures exist and are trusted.

\* \*\*Q1:\*\* Types: high coverage, JSON parity with fixtures; Dialyzer clean for Types.

\* \*\*Q2:\*\* HTTP: retry matrix coverage; config \& PoolKey tests; HTTP telemetry validated.

\* \*\*Q3:\*\* Futures \& Metrics: all union variants covered; metrics reduction matches Python semantics.

\* \*\*Q4:\*\* Clients: no deadlocks; error handling robust; RateLimiter/ETS behaviors correct.

\* \*\*Q5:\*\* Tokenization safe \& functional; fallback plan documented if NIF caching unsafe.

\* \*\*Q6:\*\* Integration flows match Python on representative scenarios; concurrency stable.

\* \*\*Q7:\*\* CLI behaves correctly and exposes data in table/JSON formats, with good error handling.



Each gate is enforced via:



```bash

mix test

mix dialyzer

mix credo --strict

mix format --check-formatted

```



Plus the additional \*\*golden/parity tests\*\* described above.



---



\## 5. How to use this doc day-to-day



\* When starting a Phase, read:



&nbsp; \* Implementation Process → Phase N

&nbsp; \* This doc → Testing for Phase N

&nbsp; \* `0001`/`0100` for deeper context if needed.



\* At the end of the Phase:



&nbsp; \* Ensure all T-phase tests exist and pass.

&nbsp; \* Confirm Q-gate N is ticked.

&nbsp; \* Only then move to next Phase.



If you’d like, next we can draft:



\* Concrete ExUnit skeletons for the \*\*Phase 1 type tests\*\*, or

\* A minimal \*\*“wire contract” fixture generator\*\* script based on the Python SDK.



