# Phase 7E: Documentation Suite (ExDoc, Guides, Troubleshooting) - Agent Prompt

> **Target:** Produce user-facing documentation: ExDoc module docs, getting started guide, API reference overview, troubleshooting guide, and ensure README reflects CLI + QA steps.  
> **Timebox:** Week 7 - Days 5-6 (end of Phase 7).  
> **Location:** `S:\tinkex`  
> **Prerequisites:** CLI commands implemented (7A–7D), all previous phases complete.  
> **Objective:** Deliver polished docs matching Python SDK behavior and QA strategy.

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/07_porting_strategy.md` | Documentation expectations | Getting started, troubleshooting |
| `README.md` | Current project overview | update sections |
| `lib/tinkex/*.ex` | Module docs for ExDoc | ensure @moduledoc present |
| `mix.exs` | ExDoc config (`docs/0` function) | set up extras |
| Phase 6 integration tests/examples | reference for guides | usage patterns |

---

## 2. Scope

### 2.1 Deliverables

1. **ExDoc Configuration**
   - Configure `mix.exs` with `docs: [...]` (extras for guides, README).
   - Ensure public-facing modules and functions that make up the user API have `@moduledoc`/`@doc`; mark internal helpers `@doc false` as appropriate.
2. **Guides**
   - `docs/guides/getting_started.md`: installation, config, running CLI.
   - `docs/guides/api_reference.md`: overview of modules (ServiceClient, TrainingClient, SamplingClient, Tokenizer).
   - `docs/guides/troubleshooting.md`: common issues (timeouts, 429, NIF, CLI errors) + resolutions referencing docs.
3. **README Updates**
   - Include CLI usage summary, QA commands (`mix test`, `mix dialyzer`, `mix credo`, `mix format --check-formatted`).
   - Link to guides and ExDoc site.
4. **Behavioral Parity Note**
   - Document how to compare Elixir vs Python results (test template snippet) using the same base model, prompt, and sampling params; emphasize checking for similar outputs/logprobs rather than bit-identical text.
5. **Automated Checks**
   - Add `mix docs` to CI or Makefile instructions, noting it may require dev-only deps and should not run in production environments.

---

## 3. Tests

- Run `mix docs` to ensure docs build.
- `mix test`, `mix dialyzer`, `mix credo`, `mix format --check-formatted` to verify code comments/docs didn’t break standards.

---

## 4. Acceptance Criteria

- [ ] ExDoc builds with new guides/extras.
- [ ] README references guides and QA commands.
- [ ] Guides cover CLI commands, integration flows, troubleshooting, parity tests.
- [ ] All QA commands pass.

---

## 5. Execution Checklist

1. Load relevant docs + code.
2. Add guides, update module docs + README, configure ExDoc.
3. Run `mix docs`, QA commands.
4. Summarize changes referencing guides + README sections + mix.exs updates.

**Reminder:** Each Phase 7 prompt is standalone—include all necessary context/instructions in final output. Good luck!***
