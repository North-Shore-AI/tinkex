# Phase 4C: Training & Sampling Clients - Agent Prompt

> **Target:** Implement `Tinkex.TrainingClient` (sequential send, concurrent polling) and `Tinkex.SamplingClient` (ETS-based, lock-free reads) with all safety requirements.  
> **Timebox:** Week 3 - Days 3-4  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 4A (Application foundations) and 4B (SessionManager + ServiceClient) complete.  
> **Next:** Phase 5 (Tokenizer integration) and Phase 6 (integration tests).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Training/Sampling client design, safety requirements | Lines 439-554 (critical) |
| `docs/20251119/port_research/03_async_model.md` | Futures combination, metrics reduction, blocking trade-offs | Combined futures + blocking notes |
| `docs/20251119/port_research/05_error_handling.md` | Error categorization (user vs server), retry semantics | Truth table |
| `docs/20251119/port_research/07_porting_strategy.md` | Implementation checklist, tokenizer note, multi-tenancy | Sections on Training/Sampling |
| `lib/tinkex/future.ex` | Polling + await helpers (Phase 3C) | For background tasks |
| `lib/tinkex/metrics_reduction.ex` | Combine chunk metrics | Use for forward_backward |
| `lib/tinkex/service_client.ex` | How clients are spawned via DynamicSupervisor | integrate with start_child |
| `lib/tinkex/rate_limiter.ex` | Shared backoff for SamplingClient | Use per `{base_url, api_key}` |
| `lib/tinkex/sampling_registry.ex` | ETS registration & cleanup | SamplingClient init must register |

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/training_client.ex
lib/tinkex/sampling_client.ex
lib/tinkex/api/training.ex            # if not yet created (wrapper around HTTP endpoints)
lib/tinkex/api/sampling.ex            # as needed
test/tinkex/training_client_test.exs
test/tinkex/sampling_client_test.exs
```

### 2.2 TrainingClient Requirements

- GenServer storing:
  - `model_id`, `session_id`, `config`, `request_id_counter`, `http_pool`.
  - Possibly `model_seq_id`, `sampling_session_id` references.
- `forward_backward/4`:
  - Chunk data (128 examples max, 500k “numbers” per chunk).
  - **Synchronous sends**: inside `handle_call`, iterate chunks sequentially; each call to `Tinkex.API.Training.forward_backward/3` returns `%{request_id: ...}`.
  - After sending all chunks, spawn `Task.start` that:
    - Wraps body in `try/rescue`.
    - Uses `Tinkex.Future.poll/2` for each request.
    - Combines results via `combine_forward_backward_results/1`.
    - On success/failure, calls `GenServer.reply/2`, rescuing `ArgumentError` (caller may die).
- `optim_step/2` similar (single request).
- `save_weights_for_sampler/2` (if part of scope) can return future or immediate result.
- Document blocking trade-off (GenServer busy during send phase).

### 2.3 SamplingClient Requirements

- `use GenServer`? The runtime pattern is: GenServer for init/cleanup, but sampling calls go straight to ETS.
- On `init/1`:
  - Create sampling session via API.
  - `Tinkex.SamplingRegistry.register(self(), config_entry)` where entry includes `sampling_session_id`, `http_pool`, `request_id_counter` atomics, `rate_limiter`, and stored `Tinkex.Config`.
- Public API `sample(pid, prompt, opts)` returns `Task.t()`:
  - Immediately reads config from ETS (`{:config, pid}`), without GenServer call.
  - Waits on `Tinkex.RateLimiter` (shared per `{base_url, api_key}`).
  - Increments request counter atomically.
  - Calls `Tinkex.API.Sampling.asample/3` with opts merged + `config: entry.config`.
  - On 429 error, call `Tinkex.RateLimiter.set_backoff/2` using `error.retry_after_ms`.
  - No automatic retry (document expectation).
- GenServer `terminate/2` should rely on registry to cleanup.

---

## 3. Tests

1. **TrainingClient**
   - Use Bypass to simulate chunked forward_backward (multiple chunks).
   - Ensure synchronous send order: e.g., record call sequence.
   - Verify polling task replies even on exception (simulate Bypass closing connection mid-stream).
   - Optim step success.
2. **SamplingClient**
   - ETS registration (via SamplingRegistry) ensures config stored.
   - `sample/4` fetches config, uses RateLimiter; verify backoff triggered when 429 returned.
   - Multi-client scenario: same config -> shared limiter; different base_url/key -> separate.

Note: For concurrency tests, use short sleeps (ms). Where necessary, stub `Tinkex.Future.poll/2` or use small responses.

---

## 4. Safety Checklist (must be satisfied)

- TrainingClient:
  - All `Task.start` bodies wrap logic in `try/rescue`.
  - `GenServer.reply/2` inside try/rescue to handle `ArgumentError`.
  - `Enum.reduce_while` or explicit case handling when sending chunks to handle HTTP errors without crashing.
- SamplingClient:
  - Never uses GenServer.call for `sample/4`; purely ETS + Task.
  - Always injects `entry.config` into API opts (prevents `Keyword.fetch!` crash).
  - Uses `Tinkex.RateLimiter.for_key/1` with normalized base URL + API key.
  - RateLimiter access via `:ets.insert_new/2` already implemented (Phase 4A).

---

## 5. Acceptance Criteria

- [ ] `Tinkex.TrainingClient` implements synchronous send + async polling per spec; tests cover success & failure.
- [ ] `Tinkex.SamplingClient` registers via registry, uses ETS/RateLimiter, returns Tasks; tests cover ETS lookups, backoff.
- [ ] All new tests pass (`mix test test/tinkex/training_client_test.exs test/tinkex/sampling_client_test.exs`).
- [ ] Full suite (`mix test`) + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load docs/source listed above (each prompt is standalone).
2. Implement TrainingClient & SamplingClient modules + supporting API wrappers.
3. Add robust tests (Bypass for HTTP interactions; use existing patterns).
4. Run targeted tests, then full suite, then dialyzer.
5. Summarize work referencing file paths/lines in final response.

**Reminder:** Provide self-contained instructions & outputs in your final response. Good luck!***
