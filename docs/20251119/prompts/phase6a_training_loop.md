# Phase 6A: End-to-End Training Loop - Agent Prompt

> **Target:** Build the first vertical slice: full training workflow (ServiceClient → TrainingClient → forward_backward → optim_step → save weights).  
> **Timebox:** Week 5 - Day 3 (start of integration week)  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 1‑5 complete (types, HTTP, clients, tokenization).  
> **Next:** Phase 6B (Sampling workflow) and 6C (Multi-client, telemetry).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Overall client interactions, save_weights flow | Sections on TrainingClient + ServiceClient |
| `docs/20251119/port_research/03_async_model.md` | Futures combination; blocking notes | Combined futures |
| `docs/20251119/port_research/04_http_layer.md` | API endpoints for training/save weights | `/forward_backward`, `/optim_step`, `/save_weights` |
| `docs/20251119/port_research/05_error_handling.md` | Retry/error semantics | Truth table |
| `lib/tinkex/service_client.ex` | Current implementation | ensure APIs ready |
| `lib/tinkex/training_client.ex` | Implementation from Phase 4C | how to call ops |
| `lib/tinkex/types/forward_backward_output.ex` | Structures to inspect | metrics |
| `lib/tinkex/tokenizer.ex` + `ModelInput` | For building sample data | from_text helper |

---

## 2. Scope

### 2.1 Deliverables

1. **Integration Tests**
   - New test module `test/integration/training_loop_test.exs` (or similar) using Bypass to simulate the entire training flow.
   - Scenario covers:
     - `Tinkex.ServiceClient.start_link/1`
     - `create_lora_training_client/2`
     - `forward_backward/4` with chunked data.
     - `optim_step/2`
     - `save_weights_for_sampler/2` (if implemented; stub response otherwise — e.g., Bypass returns minimal JSON and client yields `{:ok, map}` or the call is a no-op that still flows).
     - Ensure tasks return `{:ok, result}` and metrics combine correctly.
2. **Example Script (optional but encouraged)**
   - Under `examples/` or `docs/guides/`, create a script showing how to run the training loop against staging endpoints.
3. **Performance Hooks**
   - Add timer / logging snippet (just instrumentation for now) to measure total time (mocked if using Bypass); keep this informational only—no assertions on timing in tests.

---

## 3. Tests

- Use Bypass to stub:
  - Session creation / heartbeat (reuse from Phase 4B patterns).
  - Model creation.
  - `forward_backward` responses (multiple chunks).
  - `optim_step` response.
  - `save_weights` response.
- In `training_loop_test.exs`, start the application (`Application.ensure_all_started(:tinkex)`) so Finch, ETS tables, SessionManager, and supervisors are running before invoking ServiceClient.
- Ensure entire flow runs via real module interactions (ServiceClient → TrainingClient). No direct GenServer calls.
- Assert metrics reduction via the final `ForwardBackwardOutput`; queue-state behaviour is already covered by earlier future-polling tests and telemetry.

---

## 4. Constraints & Guidance

- Tests must be deterministic; use short `Process.sleep` only where necessary for tasks.
- Emphasize config isolation by using unique config per test (or multiple tests verifying separate ServiceClients).
- Provide documentation snippets describing the training workflow.
- Ensure `mix test test/integration/training_loop_test.exs` passes; also run full suite + dialyzer.

---

## 5. Acceptance Criteria

- [ ] Integration test covers entire training loop with mocked HTTP.
- [ ] Example/documentation updated showing vertical slice usage.
- [ ] Full suite + dialyzer clean.
- [ ] Summary describes performance measurement approach (even if mocked).

---

## 6. Execution Checklist

1. Load required docs/code.
2. Implement integration test + example docs.
3. Run targeted tests, full `mix test`, and `mix dialyzer`.
4. Summarize changes referencing file paths/lines.

**Reminder:** This prompt is standalone; include all relevant context in final output. Good luck!***
