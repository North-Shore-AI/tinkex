\# Tinkex SDK Implementation Process



\## Current State Assessment



\### What the Documents Provide



\- ✅ \*\*Technical Specifications\*\* - Exact type definitions, field names, architectural patterns

\- ✅ \*\*Rationale\*\* - Why decisions were made (10 rounds of critique/response)

\- ✅ \*\*Code Examples\*\* - Elixir implementation patterns for each component

\- ✅ \*\*Known Pitfalls\*\* - Critical bugs identified and fixed in rounds 7-10

\- ✅ \*\*Verification Checklists\*\* - Pre-implementation validation steps



\### What's Missing (The Gap)



\- ❌ \*\*Systematic Development Workflow\*\* - Ordered process from spec → working code

\- ❌ \*\*Dependency Graph\*\* - What MUST be built before what

\- ❌ \*\*Quality Gates\*\* - When to stop and verify before proceeding

\- ❌ \*\*Integration Strategy\*\* - How components assemble into working system

\- ❌ \*\*Behavioral Validation\*\* - Proving implementation matches Python SDK



---



\## Proposed Formal Implementation Process



\### Phase 0: Foundation \& Validation (Week 1 - Days 1-3)



\*\*Objective:\*\* Verify assumptions, establish baseline



\#### Critical Verification First (Doc 07, lines 1089-1444)



Must verify BEFORE coding:



1\. StopReason wire format (API emits "length"/"stop" or "max\_tokens"?)

2\. RequestErrorCategory casing (capitalized vs lowercase)

3\. Image type field names (data vs image\_data)

4\. SampleRequest.prompt\_logprobs semantics (Optional\[bool] vs bool)

5\. Rate limiter scope ({base\_url, api\_key} confirmed)

6\. Tokenizer NIF safety (can store in ETS?)



\#### Deliverables



\- Wire format verification report (actual API responses logged)

\- Mix project scaffold with correct dependencies

\- CI/CD pipeline (GitHub Actions + Dialyzer)

\- Mock HTTP server (Bypass) with verified response shapes



\*\*Quality Gate:\*\* No coding proceeds until wire format verification complete



---



\### Phase 1: Type System (Week 1 - Days 4-7)



\*\*Objective:\*\* Build validated data types matching verified wire format



\#### Implementation Order (Doc 01)



1\. Enums (StopReason, LossFnType, RequestErrorCategory) ← VERIFY FIRST

2\. Data structures (ModelInput, TensorData, Datum)

3\. Request types (ForwardBackwardRequest, SampleRequest, etc.)

4\. Response types (ForwardBackwardOutput, SampleResponse, etc.)

5\. Error types (Tinkex.Error with categories)



\#### Per-Component Process



For EACH type:



1\. Read spec (01\_type\_system.md specific section)

2\. Identify dependencies (what types does this reference?)

3\. Implement struct with @type specs

4\. Implement validation (pure functions, NOT Ecto)

5\. Implement Jason.Encoder (with @derive)

6\. Write property tests (use StreamData)

7\. Verify JSON encoding matches Python



\#### Deliverables



\- All 30-40 type modules with tests

\- Tinkex.Types.TensorData with Nx integration (aggressive casting)

\- JSON encoding tests (nil → null verified)

\- Dialyzer passes with zero warnings



\*\*Quality Gate:\*\* All types encode/decode to match Python SDK wire format



---



\### Phase 2: HTTP Layer \& Retry Logic (Week 2 - Days 1-3)



\*\*Objective:\*\* Build reliable HTTP foundation



\#### Implementation Order (Doc 04)



1\. Tinkex.PoolKey (centralized URL normalization)

2\. Tinkex.Config (multi-tenancy struct)

3\. Tinkex.API base module (with\_retries, handle\_response)

4\. Tinkex.API.\* endpoints (Training, Sampling, Futures, etc.)

5\. Separate Finch pools (training, sampling, session, futures, telemetry)



\#### Critical Requirements (Doc 04, lines 533-643)



Must implement:



\- x-should-retry header support

\- 429 with Retry-After parsing (retry-after-ms + numeric seconds)

\- Error categorization (Unknown/Server/User)

\- Config threading (NO Application.get\_env at call time)

\- Pool key normalization (single source of truth)



\#### Deliverables



\- HTTP client with verified retry logic

\- Config struct tested for multi-tenancy

\- Mock server tests for all retry scenarios

\- Telemetry events for HTTP operations



\*\*Quality Gate:\*\* Retry behavior matches Python SDK (5xx, 408, 429, x-should-retry)



---



\### Phase 3: Future \& Polling (Week 2 - Days 4-5)



\*\*Objective:\*\* Async polling mechanism



\#### Implementation Order (Doc 03)



1\. Tinkex.Future.poll/2 (with queue state handling)

2\. Tinkex.Future.await/2 (wrapper around Task.await)

3\. Tinkex.MetricsReduction (6 suffix strategies)

4\. TryAgainResponse + QueueState types



\#### Critical Requirements (Doc 03, lines 251-356)



Must handle:



\- TryAgainResponse (queue backpressure)

\- QueueState (:active, :paused\_rate\_limit, :paused\_capacity)

\- Exponential backoff for polling

\- Timeout handling

\- Metric reduction (sum/min/max/mean/slack/unique)



\#### Deliverables



\- Future polling with backpressure

\- Metric reduction matching Python REDUCE\_MAP

\- Telemetry for queue state changes



\*\*Quality Gate:\*\* Polling loop handles all response types, metrics reduce correctly



---



\### Phase 4: Client Architecture (Week 3-4)



\*\*Objective:\*\* GenServer clients with correct concurrency patterns



\#### Implementation Order (Doc 02)



1\. Tinkex.Application (ETS tables, Finch pools, supervisors)

2\. Tinkex.SamplingRegistry (process monitoring for ETS cleanup)

3\. Tinkex.RateLimiter (atomics-based shared backoff)

4\. Tinkex.SessionManager (heartbeat mechanism)

5\. Tinkex.ServiceClient (creates other clients)

6\. Tinkex.TrainingClient (sequential sends, concurrent polling)

7\. Tinkex.SamplingClient (ETS-based, lock-free reads)



\#### Critical Safety Requirements (Doc 02, lines 439-554)



\*\*TrainingClient MUST:\*\*



\- Send chunks synchronously (prevents race conditions)

\- Spawn polling Task with try/rescue (prevents infinite hangs)

\- Handle GenServer.reply with ArgumentError rescue

\- Use reduce\_while for error handling (prevents GenServer crash)



\*\*SamplingClient MUST:\*\*



\- Read config from ETS (lock-free)

\- Inject entry.config into API opts (prevents Keyword.fetch! crash)

\- Share RateLimiter per {base\_url, api\_key}

\- Use :ets.insert\_new for RateLimiter (prevents split-brain)



\#### Deliverables



\- All client GenServers with supervision

\- TrainingClient with blocking documented

\- SamplingClient with ETS architecture

\- Multi-tenancy tests (different API keys)



\*\*Quality Gate:\*\* No deadlocks, no crashes, concurrent requests work



---



\### Phase 5: Tokenization (Week 5 - Days 1-2)



\*\*Objective:\*\* Lean tokenizer integration



\#### Implementation (Doc 02, lines 1237-1335)



1\. Verify tokenizers NIF safety (ETS caching test)

2\. Tinkex.Tokenizer.get\_tokenizer\_id/2 (Llama-3 hack)

3\. Tinkex.Tokenizer.encode/3 (with ETS caching by resolved ID)

4\. ModelInput.from\_text/2 helper



\#### Critical Verification



BEFORE implementing ETS caching:



```elixir

test "tokenizer NIF resources safe across processes" do

\&nbsp; {:ok, tok} = Tokenizers.Tokenizer.from\\\_pretrained("gpt2")

\&nbsp; :ets.insert(:test, {:tok, tok})



\&nbsp; Task.async(fn ->

\&nbsp;   \\\[{:tok, tok2}] = :ets.lookup(:test, :tok)

\&nbsp;   {:ok, enc} = Tokenizers.Tokenizer.encode(tok2, "hello")

\&nbsp;   assert is\\\_list(Tokenizers.Encoding.get\\\_ids(enc))

\&nbsp; end) |> Task.await()

end

```



\#### Deliverables



\- NIF safety verified

\- Tokenizer caching (or GenServer fallback if unsafe)

\- Llama-3 workaround tested



\*\*Quality Gate:\*\* Tokenization works, caching safe



---



\### Phase 6: Integration \& End-to-End (Week 5-6)



\*\*Objective:\*\* Vertical slice workflows



\#### Test Scenarios



1\. Full training loop (create client → forward\_backward → optim\_step → save)

2\. Sampling workflow (create client → sample → verify output)

3\. Multi-client concurrency (2 training, 100 sampling)

4\. Error recovery (429 backoff, 5xx retry, user error propagation)

5\. Config isolation (different API keys don't interfere)



\#### Deliverables



\- End-to-end examples working

\- Performance baseline (compare to Python)

\- Telemetry dashboard (metrics visible)



\*\*Quality Gate:\*\* All workflows match Python SDK behavior



---



\### Phase 7: CLI \& Documentation (Week 7-8)



\*\*Objective:\*\* User-facing tools



\#### Deliverables



\- CLI with checkpoint/run/version commands

\- ExDoc documentation (all modules)

\- Getting started guide

\- API reference

\- Troubleshooting guide



---



\## Quality Assurance Strategy



\### Continuous Verification



After EVERY component:



```bash

mix test                          # Unit tests pass

mix dialyzer                      # Type checks pass

mix credo                         # Code quality

mix format --check-formatted      # Style

```



\### Integration Checkpoints



\- \*\*After Phase 1:\*\* All types encode/decode correctly

\- \*\*After Phase 2:\*\* HTTP client retries work

\- \*\*After Phase 3:\*\* Futures poll correctly

\- \*\*After Phase 4:\*\* Clients don't deadlock

\- \*\*After Phase 5:\*\* Tokenization works

\- \*\*After Phase 6:\*\* End-to-end matches Python



\### Behavioral Parity Tests



Compare Elixir vs Python for same inputs:



```elixir

test "forward\\\_backward matches Python output" do

\&nbsp; # 1. Run Python SDK with fixture data

\&nbsp; # 2. Run Elixir SDK with same data

\&nbsp; # 3. Compare HTTP requests (same JSON)

\&nbsp; # 4. Compare responses (same parsing)

end

```



---



\## Critical Path Dependencies



```

Verify Wire Format

\&nbsp;       ↓

\&nbsp;  Type System

\&nbsp;       ↓

\&nbsp;  HTTP Layer

\&nbsp;       ↓

\&nbsp;    Futures

\&nbsp;       ↓

\&nbsp;    Clients

\&nbsp;       ↓

\&nbsp;  Tokenizer

\&nbsp;       ↓

\&nbsp; Integration

\&nbsp;       ↓

\&nbsp;  CLI/Docs

```



\*\*Cannot skip:\*\* Each phase blocks the next. No "parallel work" until Phase 4.



---



\## Risk Mitigation



\### Top Risks from Docs



1\. \*\*Infinite hangs\*\* → Mitigated by try/rescue in Task.start (Doc 02, line 489)

2\. \*\*Type mismatches\*\* → Mitigated by wire format verification (Doc 07, lines 1089-1195)

3\. \*\*Race conditions\*\* → Mitigated by synchronous sends (Doc 02, line 468)

4\. \*\*Multi-tenancy bugs\*\* → Mitigated by Config struct (Doc 02, lines 69-114)

5\. \*\*Tokenizer crashes\*\* → Mitigated by NIF safety test (Doc 07, lines 1321-1348)



---



\## Recommended Approach



\### Immediate Next Steps (This Week)



1\. \*\*Day 1:\*\* Run wire format verification tests (Doc 07 checklist)

2\. \*\*Day 2:\*\* Scaffold project, set up CI/CD

3\. \*\*Day 3:\*\* Implement Phase 1 types (starting with verified enums)

4\. \*\*Day 4-5:\*\* Continue types + JSON encoding tests

5\. \*\*Day 6-7:\*\* HTTP layer with verified retry logic



\### Integration with Your Testing Strategy



\- \*\*You develop:\*\* Integration tests, property tests, performance benchmarks

\- \*\*I'll align:\*\* Component implementation with your test fixtures

\- \*\*Sync point:\*\* After each phase (use your tests to verify my components)



\### Deliverables Format



Each component comes with:



\- Implementation code

\- Unit tests (component isolated)

\- Dialyzer specs

\- Example usage

\- Known limitations



---



\## Questions for You



1\. \*\*Wire format verification:\*\* Can you provide access to a live API endpoint for verification tests? (Critical for Phase 0)

2\. \*\*Testing sync:\*\* Do you want to review tests per-phase or batch at the end?

3\. \*\*Performance baselines:\*\* Do you have target latency/throughput numbers from Python SDK?

4\. \*\*Scope cuts:\*\* Are the v2.0 deferrals acceptable (streaming, custom loss, chat templates)?



---



\## Summary



This formal process ensures we don't code blindly - every component is spec'd → implemented → verified before moving forward. The documents are excellent technical specs; this process is the bridge to working code.



