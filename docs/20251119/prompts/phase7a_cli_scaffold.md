# Phase 7A: CLI Scaffold & Command Routing - Agent Prompt

> **Target:** Build the basic Tinkex CLI executable (escript/Mix task) with command routing for `checkpoint`, `run`, and `version`.  
> **Timebox:** Week 7 - Day 1  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phases 1‑6 complete (SDK functionality verified).  
> **Next:** Phase 7B/7C/7D (individual command implementations) and 7E (documentation).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/07_porting_strategy.md` | Phase 7 requirements, CLI overview | CLI & documentation sections |
| `mix.exs` | Ensure escript config / CLI deps | `project/0` + deps |
| `README.md` | Current user instructions | Will update later |
| `lib/tinkex/service_client.ex` etc. | Command targets | Understand operations |

---

## 2. Scope

### 2.1 Deliverables

1. **CLI Entry Point**
   - Create `lib/tinkex/cli.ex` (or `tinkex_cli` module) with `main/1`.
   - Configure `mix.exs` for escript (`escript: [main_module: Tinkex.CLI]`) or Mix task alias.
2. **Command Routing**
   - Parse arguments into subcommands `checkpoint`, `run`, `version`.
   - For now, commands can stub out (`IO.puts` placeholders) but parse required options.
3. **Option Parsing**
   - Use `OptionParser` or CLI library (Optimus, NimbleOptions, etc.).
   - Each command should have help text accessible via `--help`.
4. **Tests**
   - Add `test/tinkex/cli_test.exs` covering parsing + help output.
5. **Build Scripts**
   - Document how to build CLI (`mix escript.build`) and where binary lands (`./tinkex`).

---

## 3. Constraints & Guidance

- Keep CLI independent of Mix (no `Mix.*` modules at runtime).
- Provide `--help` and `--version`.
- Make routing extensible (Phase 7B-D will fill command bodies).
- Tests should not call actual network; just verify parsing/output.

---

## 4. Acceptance Criteria

- [ ] `lib/tinkex/cli.ex` implements `main/1` with subcommand routing.
- [ ] `mix escript.build` (or equivalent) works.
- [ ] `test/tinkex/cli_test.exs` passes.
- [ ] `mix test`, `mix dialyzer`, `mix credo`, `mix format --check-formatted` clean.
- [ ] Document build/run instructions in README placeholder section.

---

## 5. Execution Checklist

1. Load required docs & files.
2. Implement CLI scaffold + tests.
3. Run CLI-specific tests + full suite + QA commands.
4. Summarize changes referencing files/lines.

**Reminder:** Each Phase 7 prompt is standalone; include complete instructions/results in final response. Good luck!***
