# Phase 6C: Multi-Client Concurrency & Telemetry - Agent Prompt

> **Target:** Validate multi-client concurrency (two training clients, 100+ sampling requests), error recovery, config isolation, and telemetry dashboards.  
> **Timebox:** Week 5 - Days 4-5  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 6A and 6B complete (training/sampling workflows).  
> **Objective:** Ensure vertical slice matches Python SDK behavior across all scenarios.

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Multi-client design, RateLimiter scope | Sampling + Training sections |
| `docs/20251119/port_research/03_async_model.md` | Futures, queue state telemetry | entire doc |
| `docs/20251119/port_research/04_http_layer.md` | HTTP/telemetry integration | Telemetry sections |
| `docs/20251119/port_research/05_error_handling.md` | Error recovery (429, 5xx, user errors) | truth table |
| `docs/20251119/port_research/07_porting_strategy.md` | Phase 6 checklist | scenarios list |
| `lib/tinkex/telemetry/metrics.ex` (if exists) | Telemetry metrics definitions | ensure coverage |
| Integration tests from 6A/6B | Build on earlier flows | referenced tests |

---

## 2. Scope

### 2.1 Deliverables

1. **Multi-Client Integration Test** (`test/integration/multi_client_concurrency_test.exs`)
   - Scenario: two ServiceClients with different configs (API keys or base URLs).
   - Each spawns TrainingClient + SamplingClient.
   - Run parallel training tasks (simulate sequential forward_backward + optim_step) and sampling tasks (100 requests).
   - Ensure no cross-talk (RateLimiter keyed per `{base_url, api_key}`) with explicit checks—for example, assert separate ETS entries like `:ets.lookup(:tinkex_rate_limiters, {:limiter, {normalized_base_url, key_a}})` vs `{..., key_b}` and confirm a 429 for client A does not delay client B’s requests.
2. **Error Recovery Coverage**
   - 429 backoff (shared limiter) validated.
   - 5xx retry behavior (HTTP layer) triggered for training/future polling (uses `with_retries/5`); sampling continues to use `max_retries: 0` and should not auto-retry 5xx unless you explicitly change the sampling design.
   - User error surfaces promptly without retries.
3. **Telemetry Dashboard**
   - Provide script/README snippet showing how to attach a telemetry handler or log/export metrics to console (even if simulated); keep expectations to a lightweight logger, not a full dashboard.
   - Optional: add `Tinkex.Telemetry.attach_logger/0` helper.

---

## 3. Tests

- Use Bypass to simulate both base URLs (or multiple endpoints).
- For concurrency, use `Task.async_stream` or `Supertester` harness if available.
- Record telemetry events using `:telemetry.attach/4`; assert counts/durations.
- Ensure the application is started in the test setup (`Application.ensure_all_started(:tinkex)`) so Finch, ETS tables, registries, and supervisors are running before invoking clients.
- If you lean on Supertester, reference existing patterns in `test/support` to keep the harness consistent with earlier phases.

---

## 4. Constraints & Guidance

- Tests must remain deterministic; use counters or short sleeps.
- Provide config isolation test (two configs, ensure ETS entries separate) by asserting distinct entries in ETS (e.g., RateLimiter atomics keyed by `{normalized_base_url, api_key}` and separate `:tinkex_sampling_clients` config entries per client).
- Document performance baseline approach (even if mocked; note how to measure vs Python). Performance measurements should be logged/documented only—integration tests must not assert on specific timings.

---

## 5. Acceptance Criteria

- [ ] Integration test covers multi-client concurrency, 429/5xx/user error coverage.
- [ ] Telemetry documentation/instrumentation included.
- [ ] Config isolation confirmed (no shared ETS entries between configs).
- [ ] Full `mix test` + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load required docs/code.
2. Implement integration tests + telemetry helper/docs.
3. Run targeted tests, full suite, dialyzer.
4. Summarize work referencing file paths/lines; note any performance observations.

**Reminder:** This prompt is standalone—include all necessary context/instructions. Good luck!***
