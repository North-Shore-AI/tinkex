# Phase 7D: CLI Version Command & Packaging - Agent Prompt

> **Target:** Implement the `tinkex version` command, finalize CLI packaging (escript release instructions), and ensure continuous verification commands documented.  
> **Timebox:** Week 7 - Day 4  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 7A scaffold, 7B checkpoint, 7C run command.  
> **Next:** Phase 7E (ExDoc + guides).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `mix.exs` | Version info, escript config | `project/0`, `application/0` |
| `lib/tinkex/cli.ex` | Existing commands | add `version` |
| `README.md` | Build instructions section | update with CLI packaging |
| `docs/20251119/port_research/07_porting_strategy.md` | QA strategy | Continuous verification |

---

## 2. Scope

### 2.1 Features

1. **Version Command**
   - `tinkex version` prints current version + git commit (if available).
   - `--json` flag outputs JSON payload (e.g., `{"version":"0.1.0","commit":"abc123"}`).
   - Optionally show dependency versions (`--deps`).
2. **Packaging**
   - Ensure `mix escript.build` works; add `mix release` instructions if desired.
   - Provide `Makefile` or script snippet for QA commands.
3. **Continuous Verification Docs**
   - Document QA commands (mix test/dialyzer/credo/format) in README or CONTRIBUTING.
   - Possibly add `mix credo` config if not already present.
4. **Tests**
   - `test/tinkex/cli_version_test.exs` verifying output for default and JSON modes.

---

## 3. Constraints & Guidance

- Do not use Mix modules at runtime (use `Application.spec(:tinkex, :vsn)` etc.).
- For git commit, use `System.cmd("git", ["rev-parse", "--short", "HEAD"])` guarded so CLI runs even outside repo.
- Documentation should detail how to build CLI, run QA commands, and what outputs to expect.

---

## 4. Acceptance Criteria

- [ ] `tinkex version` implemented with options described.
- [ ] Packaging instructions (README or docs) updated.
- [ ] QA command list documented per spec.
- [ ] Tests covering version command behavior.
- [ ] `mix test`, `mix dialyzer`, `mix credo`, `mix format --check-formatted`, `mix escript.build` all succeed.

---

## 5. Execution Checklist

1. Load required files.
2. Implement version command + packaging docs.
3. Add tests; run QA commands.
4. Summarize changes referencing file paths/lines.

**Reminder:** Each Phase 7 prompt is standalone—include all context/results. Good luck!***
