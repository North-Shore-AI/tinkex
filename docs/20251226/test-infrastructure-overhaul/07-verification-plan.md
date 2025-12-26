# Verification Plan

## Overview

This document describes how to verify that the test infrastructure changes eliminate all flakiness.

---

## Pre-Verification: Establish Baseline

Before making changes, document the current flakiness rate:

```bash
#!/bin/bash
# scripts/measure_flakiness.sh

echo "Measuring flakiness baseline..."
mkdir -p tmp/flakiness

for i in {1..100}; do
  echo "Run $i/100"
  if mix test --seed $RANDOM 2>&1 | tee "tmp/flakiness/run_$i.log" | grep -q "0 failures"; then
    echo "  PASS"
  else
    echo "  FAIL"
    echo "$i" >> tmp/flakiness/failures.txt
  fi
done

total_failures=$(wc -l < tmp/flakiness/failures.txt 2>/dev/null || echo 0)
echo ""
echo "Baseline flakiness: $total_failures/100 failures"
```

Expected baseline: Some runs fail (current state).

---

## Implementation Order

Execute changes in this order, verifying after each step:

### Step 1: Upgrade Supertester

```elixir
# mix.exs
defp deps do
  [
    {:supertester, "~> 0.4.0", only: :test},
    # ...
  ]
end
```

```bash
mix deps.update supertester
mix compile
mix test  # Should pass (no behavioral changes yet)
```

### Step 2: Update HTTPCase

Apply changes from `06-http-case-refactor.md`.

```bash
mix test test/tinkex/future/poll_test.exs  # May see deprecation warnings
mix test  # Full suite should pass
```

### Step 3: Fix poll_test.exs

Apply changes from `03-poll-test-refactor.md`.

```bash
mix test test/tinkex/future/poll_test.exs

# Flakiness check
for i in {1..20}; do
  mix test test/tinkex/future/poll_test.exs --seed $RANDOM || echo "FAIL $i"
done
```

### Step 4: Fix encode_test.exs

Apply changes from `04-encode-test-refactor.md`.

```bash
mix test test/tinkex/tokenizer/encode_test.exs

# Flakiness check
for i in {1..20}; do
  mix test test/tinkex/tokenizer/encode_test.exs --seed $RANDOM || echo "FAIL $i"
done
```

### Step 5: Fix api_test.exs

Apply changes from `05-api-test-refactor.md`.

```bash
mix test test/tinkex/api/api_test.exs

# Flakiness check
for i in {1..20}; do
  mix test test/tinkex/api/api_test.exs --seed $RANDOM || echo "FAIL $i"
done
```

### Step 6: Rewrite future_test.exs

Apply changes from `02-future-test-refactor.md`.

```bash
mix test test/tinkex/future_test.exs

# Flakiness check
for i in {1..20}; do
  mix test test/tinkex/future_test.exs --seed $RANDOM || echo "FAIL $i"
done
```

### Step 7: Full Suite Verification

```bash
# Full suite, multiple runs
for i in {1..100}; do
  echo "Full suite run $i/100"
  if mix test --seed $RANDOM 2>&1 | grep -q "0 failures"; then
    echo "  PASS"
  else
    echo "  FAIL"
    exit 1
  fi
done

echo "All 100 runs passed!"
```

---

## Verification Scripts

### Single File Flakiness Check

```bash
#!/bin/bash
# scripts/check_file_flakiness.sh

FILE=$1
RUNS=${2:-20}

if [ -z "$FILE" ]; then
  echo "Usage: $0 <test_file> [runs]"
  exit 1
fi

failures=0
for i in $(seq 1 $RUNS); do
  echo -n "Run $i/$RUNS: "
  if mix test "$FILE" --seed $RANDOM 2>&1 | grep -q "0 failures"; then
    echo "PASS"
  else
    echo "FAIL"
    ((failures++))
  fi
done

echo ""
echo "Results: $((RUNS - failures))/$RUNS passed"
if [ $failures -gt 0 ]; then
  exit 1
fi
```

### Full Suite Flakiness Check

```bash
#!/bin/bash
# scripts/check_suite_flakiness.sh

RUNS=${1:-100}

failures=0
for i in $(seq 1 $RUNS); do
  echo -n "Run $i/$RUNS: "
  if mix test --seed $RANDOM 2>&1 | grep -q "0 failures"; then
    echo "PASS"
  else
    echo "FAIL"
    ((failures++))
  fi
done

echo ""
echo "Results: $((RUNS - failures))/$RUNS passed"
if [ $failures -gt 0 ]; then
  echo "FLAKINESS DETECTED"
  exit 1
else
  echo "NO FLAKINESS DETECTED"
fi
```

### Parallel Execution Check

Test that async tests don't interfere:

```bash
#!/bin/bash
# scripts/check_parallel.sh

# Run problematic tests together
mix test \
  test/tinkex/future_test.exs \
  test/tinkex/future/poll_test.exs \
  test/tinkex/tokenizer/encode_test.exs \
  test/tinkex/api/api_test.exs \
  --seed $RANDOM

# Run multiple times
for i in {1..20}; do
  echo -n "Parallel run $i: "
  if mix test \
    test/tinkex/future_test.exs \
    test/tinkex/future/poll_test.exs \
    test/tinkex/tokenizer/encode_test.exs \
    test/tinkex/api/api_test.exs \
    --seed $RANDOM 2>&1 | grep -q "0 failures"; then
    echo "PASS"
  else
    echo "FAIL"
    exit 1
  fi
done
```

---

## Verification Checklist

### Per-File Verification

| File | Single Run | 20 Runs | Notes |
|------|------------|---------|-------|
| poll_test.exs | [ ] Pass | [ ] 20/20 | Telemetry isolation |
| encode_test.exs | [ ] Pass | [ ] 20/20 | Agent cleanup, ETS isolation |
| api_test.exs | [ ] Pass | [ ] 20/20 | Logger isolation |
| future_test.exs | [ ] Pass | [ ] 20/20 | HTTPCase rewrite |

### Suite Verification

| Check | Result |
|-------|--------|
| Full suite single run | [ ] Pass |
| Full suite 20 runs | [ ] 20/20 |
| Full suite 100 runs | [ ] 100/100 |
| Parallel problem files | [ ] 20/20 |

### Code Quality

| Check | Result |
|-------|--------|
| No deprecation warnings | [ ] |
| No compilation warnings | [ ] |
| `mix format` clean | [ ] |
| `mix credo --strict` clean | [ ] |

---

## Expected Outcomes

### Before Changes

```
Run 1: PASS
Run 2: FAIL (poll_test.exs - telemetry)
Run 3: PASS
Run 4: FAIL (encode_test.exs - Agent)
Run 5: PASS
Run 6: FAIL (api_test.exs - Logger)
...
Flakiness rate: ~15-25%
```

### After Changes

```
Run 1: PASS
Run 2: PASS
Run 3: PASS
...
Run 100: PASS
Flakiness rate: 0%
```

---

## Rollback Plan

If issues arise after changes:

1. **Revert specific file**: `git checkout HEAD~1 -- <file>`
2. **Revert all changes**: `git reset --hard HEAD~N`
3. **Keep old function**: Don't delete deprecated `attach_telemetry/1` until stable

---

## CI Integration

Add flakiness check to CI:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'

      - run: mix deps.get
      - run: mix compile --warnings-as-errors

      # Standard test run
      - run: mix test

      # Flakiness check (optional, longer)
      - name: Flakiness Check
        run: |
          for i in {1..10}; do
            mix test --seed $RANDOM || exit 1
          done
```

---

## Monitoring

After deployment, monitor for flakiness:

1. **CI failure rate**: Track test failures in CI over time
2. **Seed logging**: Log random seeds for failed runs to reproduce
3. **Periodic deep check**: Run 100-run check weekly

```bash
# Add to CI artifacts on failure
echo "Failed with seed: $RANDOM_SEED" >> test_failure.log
```

---

## Success Criteria

The infrastructure overhaul is complete when:

1. **100 consecutive runs pass** with random seeds
2. **All tests use async: true** (or have documented reason not to)
3. **No global state mutations** in test setup
4. **Consistent patterns** across all test files
5. **No deprecation warnings** (after migration complete)
6. **CI flakiness rate drops to 0%** over 2 weeks

---

## Final Report Template

After verification, document results:

```markdown
# Test Infrastructure Overhaul - Completion Report

## Summary

- **Date completed**: YYYY-MM-DD
- **Flakiness before**: X% (Y/100 failures)
- **Flakiness after**: 0% (0/100 failures)

## Changes Made

1. Upgraded Supertester to v0.4.0
2. Updated HTTPCase with isolation options
3. Fixed telemetry assertions in poll_test.exs
4. Fixed Agent cleanup in encode_test.exs
5. Fixed Logger isolation in api_test.exs
6. Rewrote future_test.exs to use HTTPCase

## Verification Results

| Check | Before | After |
|-------|--------|-------|
| Single run | Intermittent | PASS |
| 20 runs | ~15 failures | 0 failures |
| 100 runs | ~20 failures | 0 failures |

## Files Changed

- mix.exs (dependency)
- test/support/http_case.ex
- test/tinkex/future_test.exs
- test/tinkex/future/poll_test.exs
- test/tinkex/tokenizer/encode_test.exs
- test/tinkex/api/api_test.exs
- lib/tinkex/tokenizer.ex (table injection support)

## Recommendations

1. Continue using TelemetryHelpers for all telemetry testing
2. Always use start_supervised! for test processes
3. Never use Logger.configure/1 in tests
4. Mirror ETS tables instead of clearing them
```
