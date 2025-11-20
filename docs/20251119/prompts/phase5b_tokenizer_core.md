# Phase 5B: Tokenizer ID Resolution & Caching - Agent Prompt

> **Target:** Implement `Tinkex.Tokenizer` core functionality: caching, tokenizer ID resolution (including Llama-3 workaround), and encode/decode helpers using the verified NIF behavior.  
> **Timebox:** Week 5 - Day 1 (afternoon)  
> **Location:** `S:\tinkex`  
> **Prerequisites:** Phase 5A completed (NIF safety verified or fallback decided).  
> **Next:** Phase 5C (ModelInput.from_text/2 helper + client integration).

---

## 1. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/02_client_architecture.md` | Tokenizer heuristics, Llama-3 hack | Lines 1237-1335 |
| `docs/20251119/port_research/07_porting_strategy.md` | Tokenizer caching strategy, ETS table usage | Tokenization section |
| `lib/tinkex/tokenizer.ex` | Scaffold from Phase 5A | Fill in functions |
| `lib/tinkex/service_client.ex` | Access to TrainingClient info for tokenizer_id | get_info usage |
| `lib/tinkex/training_client.ex` | Where tokenizer may be used | info calls |
| `lib/tinkex/types/model_input.ex` | Understand target API for from_text | field structure |

---

## 2. Implementation Scope

### 2.1 Modules/Files

```
lib/tinkex/tokenizer.ex                # implement functions
test/tinkex/tokenizer/encode_test.exs  # new tests for caching + ID resolution
```

### 2.2 Features

1. **Tokenizer ID Resolution**
   - `get_tokenizer_id(model_name, training_client \\ nil, opts \\ [])`:
     - If `training_client` provided, call an explicit info hook to fetch `model_data.tokenizer_id`.
       - Default: `info_fun = opts[:info_fun] || &TrainingClient.get_info/1` (define the function if missing).
       - Expected return shape: `{:ok, %{model_data: %{tokenizer_id: String.t()}}}`; handle `{:error, _}` cleanly.
       - Tests can inject `info_fun` to avoid coupling to a specific TrainingClient API.
     - Apply Llama-3 hack: if `model_name` contains "Llama-3", return `"baseten/Meta-Llama-3-tokenizer"`.
     - Fallback to `model_name`.
2. **Caching Strategy**
   - Use ETS table created in Phase 4A (`:tinkex_tokenizers`).
   - Key by resolved tokenizer ID (string). Value: tokenizer struct or process reference depending on Phase 5A result.
   - Do not assume the temp table from 5A exists; ensure `:tinkex_tokenizers` is present (start the app or create the table in tests with the same options).
   - Functions:
     - `get_or_load_tokenizer(tokenizer_id)`.
     - `encode(text, model_name, opts \\ [])` returning `{:ok, [integer()]}` or `{:error, Tinkex.Error.t()}` (be consistent; optionally add `encode!/3` to raise).
     - `decode(ids, model_name, opts \\ [])` mirroring the same return contract (or a stub if not needed yet).
3. **Thread Safety**
   - If NIF safe: store tokenizer struct directly in ETS.
   - If fallback needed: use `Tinkex.TokenizerServer` per ID, supervised under a `DynamicSupervisor` (e.g., `Tinkex.TokenizerSupervisor` started from `Tinkex.Application` or under `Tinkex.ClientSupervisor`). Provide a minimal API such as `TokenizerServer.start_child(id, tokenizer)` and `TokenizerServer.encode(server, text, opts)` that wraps `GenServer.call(server, {:encode, text, opts})`; ETS caches the pid/reference instead of the raw NIF handle.

---

## 3. Tests

`test/tinkex/tokenizer/encode_test.exs` should cover:
1. `get_tokenizer_id` uses training client info when available (supply stubbed `info_fun` or mock `TrainingClient.get_info/1`).
2. Llama-3 hack returns correct ID.
3. `encode/3` caches tokenizer (call twice, second time no new load) and returns `{:ok, tokens}`.
4. If fallback server used, ensure encode works via message passing.

Use Mox or simple stubs; for actual encoding prefer a local tokenizer fixture. If you must rely on `"gpt2"`/downloads, mark with `@tag :network` to keep CI offline-safe. Use `:persistent_term` or ETS cleanup in tests.

---

## 4. Constraints

- No `Application.get_env` inside encode; rely on opts/config.
- If NIF safe: ensure ETS operations use `:ets.insert_new` to avoid race.
- Provide `@doc` examples showing how to encode text for sampling/training.
- Handle errors consistently with the tuple contract (`{:ok, ids}` | `{:error, reason}`); add bang variants only if clearly documented.

---

## 5. Acceptance Criteria

- [ ] `Tinkex.Tokenizer` resolves tokenizer IDs via server info, Llama-3 hack, fallback.
- [ ] Tokenizer caching implemented per Phase 5A outcome.
- [ ] `encode/3` returns `{:ok, [integer()]}` and caches tokenizer handles (or uses fallback servers transparently).
- [ ] Tests under `test/tinkex/tokenizer/encode_test.exs` pass.
- [ ] `mix test` + `mix dialyzer` clean.

---

## 6. Execution Checklist

1. Load required docs + files.
2. Implement tokenizer functions + caching.
3. Write tests (mocking TrainingClient info as needed).
4. Run targeted tests, full test suite, dialyzer.
5. Summarize changes referencing file paths/lines.

**Reminder:** Each prompt is independent—include all necessary context in your final response. Good luck!***
