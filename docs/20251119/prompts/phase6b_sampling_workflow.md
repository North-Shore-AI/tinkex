# Phase 6B: Sampling Workflow & Concurrency - Agent Prompt

> **Target:** Validate the sampling workflow end-to-end (ServiceClient → SamplingClient → sample) including concurrency and error recovery scenarios.  
> **Timebox:** Week 5 - Day 3 (afternoon)  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 6A (training loop integration) complete.  
> **Next:** Phase 6C (multi-client, telemetry dashboard, config isolation).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | SamplingClient architecture, ETS + RateLimiter | Sampling section |
| `docs/20251119/port_research/05_error_handling.md` | Error recovery (429, user errors) | Truth table |
| `docs/20251119/port_research/04_http_layer.md` | Sampling endpoints | `/asample` |
| `lib/tinkex/service_client.ex` | How sampling clients created | relevant API |
| `lib/tinkex/sampling_client.ex` | Implementation from Phase 4C | ETS-based logic |
| `lib/tinkex/tokenizer.ex`, `ModelInput` | For prompt encoding | from_text helper |

---

## 2. Scope

### 2.1 Deliverables

1. **Integration Tests** (`test/integration/sampling_workflow_test.exs`)
   - Scenario: create ServiceClient → SamplingClient → call `SamplingClient.sample/4` (Task) and `Task.await`.
   - Bypass responses:
     - Sampling session creation.
     - `/asample` success returning sequences/logprobs.
   - Concurrency test: spawn multiple sampling tasks (simulate 20-50 requests) using ETS state; ensure RateLimiter prevents race.
2. **Error Recovery Tests**
   - 429 response triggers RateLimiter backoff (ensure backoff applied).
   - 5xx response uses HTTP retry logic.
   - User error (400) surfaces immediately with `{:error, %Tinkex.Error{}}`.
3. **Documentation**
   - Add section in README or guide describing sampling workflow usage and concurrency considerations.

---

## 3. Tests

- Use Bypass to control responses; track `Plug.Conn.assigns[:call_count]` to assert concurrency.
- For RateLimiter, simulate 429 with `retry_after_ms` header; ensure subsequent call waits.
- Multi-client concurrency (two ServiceClients with different configs) to verify isolation.

---

## 4. Constraints & Guidance

- SamplingClient API returns Tasks; ensure integration tests use `Task.await_many`.
- Logging/telemetry: confirm queue state events (if any) are emitted (can attach simple telemetry handler in test).
- Keep tests deterministic; rely on counters instead of long sleeps.

---

## 5. Acceptance Criteria

- [ ] Integration test covers sampling flow with concurrency and error recovery.
- [ ] RateLimiter behavior verified in tests.
- [ ] Documentation updated with sampling workflow instructions.
- [ ] Full suite + dialyzer clean.

---

## 6. Execution Checklist

1. Load required docs/code.
2. Implement integration tests + docs.
3. Run targeted tests, `mix test`, `mix dialyzer`.
4. Summarize changes referencing file paths/lines.

**Reminder:** Each prompt is standalone; include all relevant context/instructions in final response. Good luck!***
