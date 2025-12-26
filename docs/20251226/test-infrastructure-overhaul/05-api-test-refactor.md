# Refactoring api_test.exs

## Current State

`test/tinkex/api/api_test.exs` at line 370-382 uses `Logger.configure/1` to set the global Logger level, causing interference with concurrent tests.

---

## Target State

Use `LoggerIsolation.capture_isolated!` for per-process Logger level management without global side effects.

---

## Problem Analysis

### Current Code (Lines 370-382)

```elixir
test "headers and redaction redacts secrets when dumping headers", %{bypass: bypass} do
  config = Config.new(
    base_url: "http://localhost:#{bypass.port}",
    api_key: "test-api-key-12345",
    log_level: :debug
  )

  Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
    resp(conn, 200, %{"ok" => true})
  end)

  previous_level = Logger.level()

  log =
    capture_log([level: :debug], fn ->
      Logger.configure(level: :debug)  # GLOBAL CHANGE
      assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
    end)

  Logger.configure(level: previous_level)  # Restore (but race condition if test fails)

  assert log =~ "[REDACTED]"
  assert log =~ "api_key"
  refute log =~ "test-api-key-12345"
end
```

### Problems

1. **Global mutation**: `Logger.configure(level: :debug)` affects all processes in the VM
2. **Race condition**: If the test fails before `Logger.configure(level: previous_level)`, the level is never restored
3. **Cross-test interference**: Other async tests may have their log capture affected by this level change
4. **Wrong log content**: The captured log shows messages from other tests because Logger is global

### Evidence

The failure showed:
```
left:  "\e[22m\n14:52:43.190 [info] training loop completed in 14ms (integration test)\n\e[0m"
right: "[REDACTED]"
```

The log message "training loop completed in 14ms (integration test)" is from a different test entirely. The global Logger state allowed cross-test log contamination.

---

## Fix

### Option 1: LoggerIsolation (Recommended)

Use `LoggerIsolation.capture_isolated!` which:
1. Sets level per-process only
2. Automatically restores on completion
3. Never affects other processes

```elixir
test "headers and redaction redacts secrets when dumping headers", %{bypass: bypass} do
  config = Config.new(
    base_url: "http://localhost:#{bypass.port}",
    api_key: "test-api-key-12345",
    log_level: :debug
  )

  Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
    resp(conn, 200, %{"ok" => true})
  end)

  log = LoggerIsolation.capture_isolated!(:debug, fn ->
    assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
  end)

  assert log =~ "[REDACTED]"
  assert log =~ "api_key"
  refute log =~ "test-api-key-12345"
end
```

### Option 2: Remove Global Logger.configure

Simply remove the `Logger.configure/1` call and rely on `capture_log`'s level option:

```elixir
test "headers and redaction redacts secrets when dumping headers", %{bypass: bypass} do
  config = Config.new(
    base_url: "http://localhost:#{bypass.port}",
    api_key: "test-api-key-12345",
    log_level: :debug
  )

  Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
    resp(conn, 200, %{"ok" => true})
  end)

  log = capture_log([level: :debug], fn ->
    # No global Logger.configure call
    assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
  end)

  assert log =~ "[REDACTED]"
  assert log =~ "api_key"
  refute log =~ "test-api-key-12345"
end
```

**Note**: This may not work if the application code doesn't emit debug logs unless the Logger level is set. The `capture_log` level option controls what's captured, not what's emitted.

### Option 3: Tag-Based Level with LoggerIsolation

If the test file uses `Supertester.ExUnitFoundation` with `logger_isolation: true`:

```elixir
@tag logger_level: :debug
test "headers and redaction redacts secrets when dumping headers", %{bypass: bypass} do
  config = Config.new(
    base_url: "http://localhost:#{bypass.port}",
    api_key: "test-api-key-12345",
    log_level: :debug
  )

  Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
    resp(conn, 200, %{"ok" => true})
  end)

  log = capture_log(fn ->
    assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
  end)

  assert log =~ "[REDACTED]"
  assert log =~ "api_key"
  refute log =~ "test-api-key-12345"
end
```

---

## HTTPCase/Test File Update

If using `Tinkex.HTTPCase`, add `logger_isolation: true`:

```elixir
# test/support/http_case.ex
defmodule Tinkex.HTTPCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Supertester.ExUnitFoundation,
        isolation: :full_isolation,
        telemetry_isolation: true,
        logger_isolation: true  # NEW

      import Tinkex.HTTPCase
      import ExUnit.CaptureLog  # Keep for compatibility

      alias Supertester.TelemetryHelpers
      alias Supertester.LoggerIsolation
    end
  end
end
```

Or for standalone tests not using HTTPCase:

```elixir
defmodule Tinkex.APITest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    logger_isolation: true

  # ...
end
```

---

## Other Logger Tests in api_test.exs

Search for other `Logger.configure` calls or log level manipulation:

```bash
grep -n "Logger.configure\|Logger.level\|capture_log" test/tinkex/api/api_test.exs
```

Apply the same fix pattern to any other occurrences.

---

## Complete Refactored Test

```elixir
describe "headers and redaction" do
  test "redacts secrets when dumping headers", %{bypass: bypass} do
    config = Config.new(
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test-api-key-12345",
      log_level: :debug
    )

    Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
      resp(conn, 200, %{"ok" => true})
    end)

    # Use LoggerIsolation for safe, per-process level setting
    log = LoggerIsolation.capture_isolated!(:debug, fn ->
      assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
    end)

    # Verify redaction
    assert log =~ "[REDACTED]"
    assert log =~ "api_key"
    refute log =~ "test-api-key-12345"

    # Verify other sensitive headers are redacted
    refute log =~ "sk-"  # API key prefix
    refute log =~ "Bearer"  # Auth token
  end
end
```

---

## Migration Checklist

- [ ] Add `logger_isolation: true` to HTTPCase or test module
- [ ] Replace `Logger.configure/1` calls with `LoggerIsolation.isolate_level/1`
- [ ] Replace manual level save/restore with `LoggerIsolation.capture_isolated!/2`
- [ ] Remove `previous_level = Logger.level()` pattern
- [ ] Verify test passes: `mix test test/tinkex/api/api_test.exs`
- [ ] Run 20 times to verify no flakiness

---

## Before/After Summary

### Before

```elixir
previous_level = Logger.level()

log = capture_log([level: :debug], fn ->
  Logger.configure(level: :debug)  # Global!
  do_work()
end)

Logger.configure(level: previous_level)  # May not run if test fails
```

### After

```elixir
log = LoggerIsolation.capture_isolated!(:debug, fn ->
  do_work()
end)
# Level automatically restored, no global mutation
```

---

## Testing the Fix

```bash
# Single run
mix test test/tinkex/api/api_test.exs

# Concurrent test to verify isolation
mix test test/tinkex/api/api_test.exs test/tinkex/future_test.exs --seed $RANDOM

# Multiple runs
for i in {1..20}; do
  mix test test/tinkex/api/api_test.exs --seed $RANDOM || echo "FAILED on run $i"
done
```

All runs should pass without log capture issues.
