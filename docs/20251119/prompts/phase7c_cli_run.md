# Phase 7C: CLI Run Command (Sampling) - Agent Prompt

> **Target:** Implement the `tinkex run` CLI command that loads a sampling client (existing or saved weights) and performs text generation with configurable parameters.  
> **Timebox:** Week 7 - Day 3  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 7A scaffold + 7B checkpoint command. Sampling workflow verified in Phase 6B.  
> **Next:** Phase 7D (version command + packaging) and 7E (documentation suite).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | SamplingClient usage | Sampling section |
| `docs/20251119/port_research/07_porting_strategy.md` | CLI deliverables | CLI + docs |
| `lib/tinkex/cli.ex` | CLI routing | add run command |
| `lib/tinkex/service_client.ex` | create_sampling_client | API usage |
| `lib/tinkex/sampling_client.ex` | `sample/4` API | ensures return type |
| `lib/tinkex/tokenizer.ex`, `ModelInput` | prompt encoding | from_text helper |

---

## 2. Scope

### 2.1 Features

1. **Command Behavior**
   - CLI syntax example:  
     ```
     tinkex run --base-model Qwen/Qwen2.5-7B --prompt "Hello" \
         --max-tokens 128 --temperature 0.7 --api-key ...
     ```
   - Steps:
     1. Parse options (model info, prompt text/file, sampling params, output format).
     2. Create ServiceClient + SamplingClient (optionally from saved checkpoint).
     3. Use `ModelInput.from_text/2` to encode prompt (or accept token file).
     4. Call `SamplingClient.sample/4`, await the returned task with `Tinkex.Future.await/2` or `Task.await/2`, and print sequences/logprobs.
     5. Support output to stdout or file (JSON).
2. **Options**
      - `--base-model` or `--model-path`
      - `--prompt` (string) or `--prompt-file` (if both provided, either prefer `--prompt` with a warning or treat as an error—pick a consistent policy)
      - Sampling params: `--max-tokens`, `--temperature`, `--top-k`, `--top-p`, `--num-samples`
      - `--api-key`, `--base-url`, `--timeout`, `--http-pool`
3. **Error Handling**
   - Distinguish user errors (400) vs server errors (retry/backoff message).
   - Treat tokenizer failures (e.g., `ModelInput.from_text/2` returning an error) as user errors and print a clear message like “Failed to load tokenizer <id>: ...”.
4. **Tests**
   - `test/tinkex/cli_run_test.exs` mocking ServiceClient/SamplingClient.
   - Validate option parsing, prompts from file, output formatting.

---

## 3. Constraints

- Keep CLI responsive: print succinct progress like “Starting sampling...” then await the task (`Tinkex.Future.await/2` or `Task.await/2`) and print a completion line; avoid spinners/long loops that complicate tests.
- Reuse existing config threading; no global env lookups except as defaults.
- Document command usage in README (CLI section).
- Avoid actual network calls in tests; use Mox/stubs.

---

## 4. Acceptance Criteria

- [ ] `tinkex run` implemented with options + sample invocation.
- [ ] Output formatting (JSON/plain) supported.
- [ ] Tests cover argument parsing, success, error handling.
- [ ] Documentation updated with usage example.
- [ ] QA commands (test/dialyzer/credo/format) pass.

---

## 5. Execution Checklist

1. Load required docs/code.
2. Implement run command, output formatting, tests.
3. Run targeted tests + QA commands.
4. Summarize work referencing file paths/lines.

**Reminder:** Each Phase 7 prompt is standalone—include all necessary context in final output. Good luck!***
