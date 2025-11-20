# Phase 5A: Tokenizer Verification & NIF Safety - Agent Prompt

> **Target:** Verify HuggingFace `tokenizers` NIF safety, establish ETS caching strategy, and scaffold the `Tinkex.Tokenizer` module.  
> **Timebox:** Week 5 - Day 1 (morning)  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 1‑4 completed (types, HTTP, clients).  
> **Next:** Phase 5B (Tokenizer ID resolution + caching), Phase 5C (ModelInput helpers).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Tokenizer notes, Llama-3 hack | Lines 1237-1335 |
| `docs/20251119/port_research/07_porting_strategy.md` | Tokenizer plan, NIF safety checklist | Sections on tokenization |
| `lib/tinkex/types/model_input.ex` | Current ModelInput struct | Understand how tokens stored |
| `mix.exs` (deps) | Ensure `:tokenizers` dep present | Check version |

---

## 2. Scope for Phase 5A

### 2.1 Modules/Files

```
lib/tinkex/tokenizer.ex                # new module scaffold
test/tinkex/tokenizer/nif_safety_test.exs  # new test verifying ETS sharing
```

### 2.2 Deliverables

1. **NIF Safety Test**
   - Write the exact test from spec: create tokenizer, store in ETS, use from another task; fail test if unsafe.
   - If test passes, document result (safe to cache handles). If it fails, update prompt output with fallback plan (GenServer) and skip caching until Phase 5B.
2. **Tokenizer Module Skeleton**
   - Define module with `@moduledoc` describing responsibilities.
   - Stub functions: `get_tokenizer_id/2`, `encode/3`, `decode/3` (if needed), but leave implementations for 5B/5C.
   - Include TODO notes referencing upcoming phases.

---

## 3. Tests

Add `test/tinkex/tokenizer/nif_safety_test.exs` containing the verification test. Use `:ets.new/2` with `:named_table, :public` and clean up afterward.

If the test fails due to NIF limitations:
1. Document the failure in the final summary.
2. Implement fallback plan: `Tinkex.TokenizerServer` owning tokenizers per key (just scaffold; full implementation deferred).

---

## 4. Constraints

- Ensure the `:tokenizers` dependency is compiled (mix deps.get / compile).
- Tests must be deterministic; wrap ETS cleanup in `on_exit`.
- If NIF is safe, note that caching will use ETS table (created in Phase 4A).

---

## 5. Acceptance Criteria

- [ ] NIF safety test implemented and passing (or fallback path documented if failing).
- [ ] `Tinkex.Tokenizer` module scaffolding exists with docstrings explaining next steps.
- [ ] No changes to behavior yet (no encoding logic).
- [ ] Tests (`mix test test/tinkex/tokenizer/nif_safety_test.exs`) pass; dialyzer still clean.

---

## 6. Execution Checklist

1. Load required docs/files.
2. Implement test + module scaffold.
3. Run `mix test test/tinkex/tokenizer/nif_safety_test.exs`.
4. If safe, note in summary; if not, outline fallback.
5. Provide final summary referencing files/lines.

**Reminder:** Each prompt runs in a standalone context; include all necessary instructions/output. Good luck!
