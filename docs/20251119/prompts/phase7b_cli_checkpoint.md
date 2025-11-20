# Phase 7B: CLI Checkpoint Command - Agent Prompt

> **Target:** Implement the `tinkex checkpoint` CLI command, which saves model weights (and optionally downloads checkpoints) by invoking the SDK’s Service/Training clients.  
> **Timebox:** Week 7 - Day 2  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 7A (CLI scaffold) complete; Service/Training clients working (Phases 4-6).  
> **Next:** Phase 7C (CLI run command) and 7D (version info & packaging).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Training client save_weights flow | Save weights section |
| `docs/20251119/port_research/07_porting_strategy.md` | CLI deliverables | CLI details |
| `lib/tinkex/cli.ex` | Scaffold from Phase 7A | Add command implementation |
| `lib/tinkex/service_client.ex` | Access to TrainingClient creation | ensuring APIs |
| `lib/tinkex/training_client.ex` | Save weights API | needed function |
| `README.md` / docs | usage instructions | update CLI section |

---

## 2. Scope

### 2.1 Features

1. **Checkpoint Command Implementation**
   - CLI syntax (example):  
     ```
     tinkex checkpoint --base-model Qwen/Qwen2.5-7B --output ./weights.bin \
         --rank 32 --api-key ... [other options]
     ```
   - Flow:
     1. Parse CLI options → build `Tinkex.Config`.
     2. Start `Tinkex.ServiceClient`.
     3. Create TrainingClient (with base_model/lora options).
     4. Run `save_weights_for_sampler/2` or equivalent.
     5. Write checkpoint metadata/output to specified path.
   - Support flags: `--base-model`, `--model-path`, `--output`, `--rank`, `--seed`, `--train-mlp`, `--train-attn`, `--train-unembed`, `--api-key`, `--base-url`, `--timeout`.
2. **Progress/Logging**
   - Print progress messages (starting session, training client, saving weights).
   - Handle errors with friendly messages (user vs server).
3. **Tests**
   - `test/tinkex/cli_checkpoint_test.exs` mocking ServiceClient/TrainingClient via Mox or simple stub modules.
   - Ensure CLI command with `--help` shows usage.

---

## 3. Constraints & Guidance

- CLI must exit with status 0 on success, non-zero on failure.
- Avoid global env lookups; use CLI options + defaults from `Tinkex.Config`.
- For tests, avoid hitting network (mock clients).
- Document command usage in README (CLI section).

---

## 4. Acceptance Criteria

- [ ] `tinkex checkpoint` command implemented with required flags.
- [ ] Command invokes ServiceClient/TrainingClient flows and writes output.
- [ ] Tests covering parsing, success, error cases.
- [ ] README/docs updated with usage example.
- [ ] `mix test`, `mix dialyzer`, `mix credo`, `mix format --check-formatted` clean.

---

## 5. Execution Checklist

1. Load required docs/code.
2. Implement command + tests + docs.
3. Run CLI tests and QA commands (test/dialyzer/credo/format).
4. Summarize changes referencing specific files/lines.

**Reminder:** Each Phase 7 prompt is standalone—include all relevant context/results in final response. Good luck!***
