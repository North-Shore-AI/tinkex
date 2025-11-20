# Phase 5C: ModelInput Helpers & Client Integration - Agent Prompt

> **Target:** Implement `ModelInput.from_text/2` (and related helpers), wire tokenizer usage into Training/Sampling flows, and add user-facing docs/tests.  
> **Timebox:** Week 5 - Day 2  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 5A (NIF verification) & 5B (Tokenizer core) complete.  
> **Next:** Phase 6 integration tests.

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | ModelInput usage, tokenization expectations | Tokenization section |
| `docs/20251119/port_research/07_porting_strategy.md` | Wording for user responsibilities (no chat templates) | Tokenizer scope |
| `lib/tinkex/types/model_input.ex` | Target file for helper | Understand chunk structure |
| `lib/tinkex/tokenizer.ex` | Implemented in Phase 5B | encode/decoder entry points |
| `lib/tinkex/training_client.ex` | Where ModelInput gets used | ensure compatibility |
| `lib/tinkex/sampling_client.ex` | For prompt encoding | determine integration |
| Tests in `test/tinkex/types` | Patterns for new tests | e.g., ModelInput tests |

---

## 2. Implementation Scope

### 2.1 Files

```
lib/tinkex/types/model_input.ex
lib/tinkex/tokenizer.ex          # add user-facing API docs/examples
test/tinkex/types/model_input_from_text_test.exs
test/tinkex/tokenizer/integration_test.exs (optional)
docs/guides/tokenization.md      # short guide (or equivalent README section)
```

### 2.2 Features

1. **ModelInput.from_text/2**
   - Accepts `text` (string) and `opts` with tokenizer info (`model_name`, `training_client`, etc.).
   - Uses `Tinkex.Tokenizer.encode/3` (tuple contract) to get tokens; propagate `{:error, reason}` or offer a clearly documented `from_text!/2` that raises. The tuple-returning `from_text/2` is intentional even though many Elixir helpers default to raising.
   - Returns `{:ok, %ModelInput{chunks: [%EncodedTextChunk{type: "encoded_text", tokens: ids}]}}` on success.
   - Provide `@doc` explaining that chat templates must be applied externally.
2. **Tokenization Helpers**
   - Expose `Tinkex.Tokenizer.encode_text/2` (alias to encode) if needed.
   - Document how to use for prompts vs training data.
3. **Client Integration**
   - Update `TrainingClient` and `SamplingClient` docs to mention from_text helper (documentation-only integration).
   - Ensure `ModelInput.length/1` still correct.

---

## 3. Tests

1. `ModelInput.from_text/2` test:
   - Prefer a local tokenizer fixture; if using `"gpt2"`/downloads, tag the test (e.g., `@tag :network`) for offline CI.
   - Ensure resulting ModelInput matches expected tokens (or at least length > 0) and returns `{:ok, model_input}`.
2. Optional integration test verifying `encode` + `from_text` produce consistent outputs.

Since tokenizer downloads may take time, consider using `:persistent_term` or skip decode check; focus on functionality.

---

## 4. Constraints

- Keep helper pure; no `Application.get_env`.
- Be consistent about error-handling: primary API returns `{:ok, ModelInput.t()}` / `{:error, reason}`; only add bang versions if clearly documented.
- Ensure tests clean ETS entries (using `on_exit`).
- Provide a short guide snippet on using the helper (in `docs/guides/tokenization.md` or README).

---

## 5. Acceptance Criteria

- [ ] `ModelInput.from_text/2` implemented with documentation and examples.
- [ ] Tokenizer module exposes user-facing encode helper (if not just alias) and documents tuple/bang contracts.
- [ ] Tests for `from_text/2` pass (mark network-dependent ones).
- [ ] User guide snippet added (README or docs/guides/tokenization.md).
- [ ] `mix test` + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load required docs/source.
2. Implement ModelInput helper + documentation updates.
3. Add tests (and optional guide).
4. Run targeted tests, full suite, dialyzer.
5. Summarize changes referencing file paths/lines.

**Reminder:** Provide a complete, self-contained answer (each prompt runs isolated). Good luck!***
