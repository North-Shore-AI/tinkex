# Agent Prompt: Tinkex Test Infrastructure Overhaul

## Objective

Refactor the Tinkex test infrastructure to eliminate all test flakiness by leveraging Supertester v0.4.0's global state isolation features.

**Success Criteria**:
- All tests pass
- 100 consecutive runs with random seeds pass
- Zero compilation warnings
- Zero dialyzer warnings
- `mix format` produces no changes
- All tests use `async: true`

**Prerequisites**:
- Supertester v0.4.0 must be implemented first (see `/home/home/p/g/n/supertester/docs/20251226/v0.4.0-spec/AGENT_PROMPT.md`)

---

## Required Reading

### Specification Documents (Read First)

Read these in order to understand what to implement:

1. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/00-overview.md`
2. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/01-root-cause-analysis.md`
3. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/02-future-test-refactor.md`
4. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/03-poll-test-refactor.md`
5. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/04-encode-test-refactor.md`
6. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/05-api-test-refactor.md`
7. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/06-http-case-refactor.md`
8. `/home/home/p/g/North-Shore-AI/tinkex/docs/20251226/test-infrastructure-overhaul/07-verification-plan.md`

### Supertester v0.4.0 Specs (Reference)

Read these to understand the new Supertester features being used:

1. `/home/home/p/g/n/supertester/docs/20251226/v0.4.0-spec/01-telemetry-helpers.md`
2. `/home/home/p/g/n/supertester/docs/20251226/v0.4.0-spec/02-logger-isolation.md`
3. `/home/home/p/g/n/supertester/docs/20251226/v0.4.0-spec/03-ets-isolation.md`
4. `/home/home/p/g/n/supertester/docs/20251226/v0.4.0-spec/06-api-reference.md`

### Source Files to Modify

Read these to understand current implementation:

1. `/home/home/p/g/North-Shore-AI/tinkex/test/support/http_case.ex`
2. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/future_test.exs`
3. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/future/poll_test.exs`
4. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/tokenizer/encode_test.exs`
5. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/api/api_test.exs`
6. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer.ex`
7. `/home/home/p/g/North-Shore-AI/tinkex/mix.exs`

### Additional Context Files

1. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/config.ex` (Config struct)
2. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex` (Future module)
3. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api.ex` (API module)

---

## Context

### Project Structure

```
/home/home/p/g/North-Shore-AI/tinkex/
├── lib/tinkex/
│   ├── api/
│   ├── config.ex
│   ├── future.ex
│   ├── tokenizer.ex
│   └── ...
├── test/
│   ├── support/
│   │   └── http_case.ex
│   └── tinkex/
│       ├── api/
│       │   └── api_test.exs
│       ├── future/
│       │   └── poll_test.exs
│       ├── tokenizer/
│       │   └── encode_test.exs
│       └── future_test.exs
└── mix.exs
```

### Current Issues

1. **poll_test.exs**: Telemetry cross-talk - receives events from other tests
2. **encode_test.exs**: Agent cleanup race + global ETS table mutation
3. **api_test.exs**: Global Logger.configure contamination
4. **future_test.exs**: Ad-hoc MockHTTPClient pattern, inconsistent with codebase

---

## Implementation Instructions

### Approach: Test-Driven Development

For each change:
1. Run the specific test file to confirm current state
2. Make the change
3. Run the test file to verify fix
4. Run full suite to verify no regressions
5. Run 20 times with random seeds to verify no flakiness

### Step 1: Update mix.exs

Upgrade Supertester dependency:

```elixir
defp deps do
  [
    {:supertester, "~> 0.4.0", only: :test},
    # ... other deps
  ]
end
```

```bash
mix deps.update supertester
mix compile
```

### Step 2: Update http_case.ex

Update `/home/home/p/g/North-Shore-AI/tinkex/test/support/http_case.ex`:

Per specification in `06-http-case-refactor.md`:
1. Add `use Supertester.ExUnitFoundation` with isolation options
2. Enable `telemetry_isolation: true`
3. Enable `logger_isolation: true`
4. Inject telemetry test ID into config
5. Deprecate `attach_telemetry/1`
6. Add `TelemetryHelpers` and `LoggerIsolation` aliases

**Verify**:
```bash
mix test test/tinkex/future/poll_test.exs
```

### Step 3: Fix poll_test.exs

Update `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/future/poll_test.exs`:

Per specification in `03-poll-test-refactor.md`:
1. Replace `attach_telemetry/1` with `TelemetryHelpers.attach_isolated/1`
2. Replace `assert_receive {:telemetry, ...}` with pattern matching OR `TelemetryHelpers.assert_telemetry/2`
3. Remove manual `:telemetry.detach/1` calls
4. Fix TestObserver to use process-local storage

**Verify**:
```bash
mix test test/tinkex/future/poll_test.exs
for i in {1..20}; do mix test test/tinkex/future/poll_test.exs --seed $RANDOM || exit 1; done
```

### Step 4: Fix encode_test.exs

Update `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/tokenizer/encode_test.exs`:

Per specification in `04-encode-test-refactor.md`:
1. Add `use Supertester.ExUnitFoundation` with `ets_isolation: [:tinkex_tokenizers]`
2. Remove `:ets.delete_all_objects(:tinkex_tokenizers)` from setup
3. Replace `Agent.start_link` + `on_exit` with `start_supervised!`
4. Use isolated cache table from context

**Also update** `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer.ex`:
1. Add `cache_table/0` function that checks for override
2. Add `__supertester_set_table__/2` for injection support
3. Update ETS operations to use `cache_table()`

**Verify**:
```bash
mix test test/tinkex/tokenizer/encode_test.exs
for i in {1..20}; do mix test test/tinkex/tokenizer/encode_test.exs --seed $RANDOM || exit 1; done
```

### Step 5: Fix api_test.exs

Update `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/api/api_test.exs`:

Per specification in `05-api-test-refactor.md`:
1. Replace `Logger.configure/1` with `LoggerIsolation.isolate_level/1`
2. Replace manual save/restore with `LoggerIsolation.capture_isolated!/2`
3. Remove `previous_level = Logger.level()` pattern

**Verify**:
```bash
mix test test/tinkex/api/api_test.exs
for i in {1..20}; do mix test test/tinkex/api/api_test.exs --seed $RANDOM || exit 1; done
```

### Step 6: Rewrite future_test.exs

Update `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/future_test.exs`:

Per specification in `02-future-test-refactor.md`:
1. Delete the entire `MockHTTPClient` module (lines ~18-106)
2. Change `use ExUnit.Case` to `use Tinkex.HTTPCase`
3. Update `setup` to use `%{bypass: bypass, config: config}` from HTTPCase
4. Replace `MockHTTPClient.set_responses` with `stub_sequence/2`
5. Replace call count checks with Erlang counters or Bypass expectations
6. Add telemetry tests using `TelemetryHelpers`

**Verify**:
```bash
mix test test/tinkex/future_test.exs
for i in {1..20}; do mix test test/tinkex/future_test.exs --seed $RANDOM || exit 1; done
```

### Step 7: Update Application Telemetry (Optional but Recommended)

To enable full telemetry isolation, update telemetry emission points in lib/ to include `config.user_metadata` in event metadata.

Example in `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex`:
```elixir
defp emit_telemetry(event, measurements, config, additional \\ %{}) do
  metadata = %{request_id: config.request_id}
  metadata = Map.merge(metadata, config.user_metadata || %{})
  metadata = Map.merge(metadata, additional)
  :telemetry.execute([:tinkex, :future | event], measurements, metadata)
end
```

---

## Verification Commands

Run after each step:

```bash
# Compile with warnings as errors
mix compile --warnings-as-errors

# Run specific test
mix test <test_file>

# Run full suite
mix test

# Format check
mix format --check-formatted

# Dialyzer
mix dialyzer
```

---

## Final Verification

Per specification in `07-verification-plan.md`:

```bash
# All quality checks pass
mix compile --warnings-as-errors && \
mix format --check-formatted && \
mix dialyzer && \
mix test

# Run 100 times to verify zero flakiness
for i in {1..100}; do
  echo "Run $i/100"
  mix test --seed $RANDOM || exit 1
done
echo "All 100 runs passed!"

# Run problematic files together
for i in {1..20}; do
  mix test \
    test/tinkex/future_test.exs \
    test/tinkex/future/poll_test.exs \
    test/tinkex/tokenizer/encode_test.exs \
    test/tinkex/api/api_test.exs \
    --seed $RANDOM || exit 1
done
```

---

## Files to Modify

| File | Change |
|------|--------|
| `mix.exs` | Upgrade supertester to ~> 0.4.0 |
| `test/support/http_case.ex` | Add Supertester integration, deprecate attach_telemetry |
| `test/tinkex/future/poll_test.exs` | Use TelemetryHelpers for assertions |
| `test/tinkex/tokenizer/encode_test.exs` | Use start_supervised!, ETSIsolation |
| `test/tinkex/api/api_test.exs` | Use LoggerIsolation |
| `test/tinkex/future_test.exs` | Complete rewrite to use HTTPCase |
| `lib/tinkex/tokenizer.ex` | Add cache_table injection support |

---

## Do Not

- Do NOT change production code behavior (only add test injection support)
- Do NOT change public API
- Do NOT remove test coverage
- Do NOT use `async: false` as a fix (find proper isolation)
- Do NOT add Process.sleep for timing fixes
- Do NOT create new documentation files (specs already written)

---

## Troubleshooting

### If tests still fail after changes:

1. Check that Supertester v0.4.0 is properly installed: `mix deps | grep supertester`
2. Ensure telemetry test ID is propagating through config.user_metadata
3. Verify `TelemetryHelpers.setup_telemetry_isolation/0` was called (check HTTPCase setup)
4. Look for other global state mutations not covered in specs

### If dialyzer fails:

1. Check type specs on new Supertester modules
2. Ensure IsolationContext struct fields have proper types
3. Run `mix dialyzer --format dialyxir` for clearer errors

### If 100-run verification fails:

1. Identify which test failed: check output logs
2. Run that specific test 50 times in isolation
3. If it passes in isolation, there's still cross-test pollution
4. Check for remaining global state: Logger, ETS, telemetry, persistent_term
