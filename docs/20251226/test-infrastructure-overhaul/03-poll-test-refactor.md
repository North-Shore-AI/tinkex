# Refactoring poll_test.exs

## Current State

`test/tinkex/future/poll_test.exs` uses:
- `Tinkex.HTTPCase` (good)
- Manual telemetry handler attachment via `attach_telemetry/1`
- `assert_receive` without test-scoped filtering

The telemetry assertions fail intermittently because events from concurrent tests are received.

---

## Target State

Update telemetry assertions to use `TelemetryHelpers` with proper isolation, either:
1. Pattern matching in `assert_receive` for immediate fix
2. `TelemetryHelpers.assert_telemetry` for full isolation

---

## Changes Required

### Location: Lines 168-186

**Before**:
```elixir
test "emits telemetry and returns retryable error on 410 expired promise", %{
  bypass: bypass,
  config: config
} do
  Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
    resp(conn, 410, %{"message" => "promise expired", "category" => "server"})
  end)

  handler_id = attach_telemetry([[:tinkex, :future, :api_error]])

  task = Future.poll("req-expired", config: config)

  assert {:error, %Error{status: 410, category: :server} = error} = Task.await(task, 1_000)
  assert error.message =~ "expired"

  assert_receive {:telemetry, [:tinkex, :future, :api_error], measurements, metadata}
  assert metadata.request_id == "req-expired"  # <- FLAKY
  assert metadata.status == 410
  assert is_integer(measurements.latency_ms)

  :telemetry.detach(handler_id)
end
```

**After (Option 1 - Pattern Matching)**:
```elixir
test "emits telemetry and returns retryable error on 410 expired promise", %{
  bypass: bypass,
  config: config
} do
  Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
    resp(conn, 410, %{"message" => "promise expired", "category" => "server"})
  end)

  handler_id = attach_telemetry([[:tinkex, :future, :api_error]])

  task = Future.poll("req-expired", config: config)

  assert {:error, %Error{status: 410, category: :server} = error} = Task.await(task, 1_000)
  assert error.message =~ "expired"

  # Pattern match on request_id to filter concurrent test events
  assert_receive {:telemetry, [:tinkex, :future, :api_error], measurements,
                  %{request_id: "req-expired"} = metadata}
  assert metadata.status == 410
  assert is_integer(measurements.latency_ms)

  :telemetry.detach(handler_id)
end
```

**After (Option 2 - TelemetryHelpers)**:
```elixir
test "emits telemetry and returns retryable error on 410 expired promise", %{
  bypass: bypass,
  config: config
} do
  Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
    resp(conn, 410, %{"message" => "promise expired", "category" => "server"})
  end)

  {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])

  task = Future.poll("req-expired", config: config)

  assert {:error, %Error{status: 410, category: :server} = error} = Task.await(task, 1_000)
  assert error.message =~ "expired"

  {:telemetry, _, measurements, metadata} =
    TelemetryHelpers.assert_telemetry([:tinkex, :future, :api_error], %{request_id: "req-expired"})

  assert metadata.status == 410
  assert is_integer(measurements.latency_ms)

  # No manual detach needed - automatic cleanup
end
```

---

## All Telemetry Tests in poll_test.exs

The following tests need the same pattern applied:

### Line 168: "emits telemetry and returns retryable error on 410 expired promise"

See changes above.

### Line 188: "emits telemetry on try_again response"

**Before**:
```elixir
handler_id = attach_telemetry([[:tinkex, :future, :poll, :retry]])
# ...
assert_receive {:telemetry, [:tinkex, :future, :poll, :retry], measurements, metadata}
assert metadata.request_id == "req-retry"
```

**After**:
```elixir
{:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :poll, :retry])
# ...
TelemetryHelpers.assert_telemetry([:tinkex, :future, :poll, :retry], %{request_id: "req-retry"})
```

### Line 211: "emits telemetry on timeout"

**Before**:
```elixir
handler_id = attach_telemetry([[:tinkex, :future, :poll, :timeout]])
# ...
assert_receive {:telemetry, [:tinkex, :future, :poll, :timeout], measurements, metadata}
assert metadata.request_id == "req-timeout"
```

**After**:
```elixir
{:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :poll, :timeout])
# ...
TelemetryHelpers.assert_telemetry([:tinkex, :future, :poll, :timeout], %{request_id: "req-timeout"})
```

---

## HTTPCase Update Required

For `TelemetryHelpers` to work, HTTPCase must enable telemetry isolation. Update `test/support/http_case.ex`:

```elixir
defmodule Tinkex.HTTPCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Supertester.ExUnitFoundation,
        isolation: :full_isolation,
        telemetry_isolation: true  # NEW

      import Tinkex.HTTPCase
      alias Supertester.TelemetryHelpers  # NEW - make available to tests
    end
  end

  # ... rest of module
end
```

---

## TestObserver Concern

`poll_test.exs` also defines a `TestObserver` module that uses `:persistent_term`:

```elixir
defmodule TestObserver do
  def register(pid) when is_pid(pid) do
    :persistent_term.put({__MODULE__, :pid}, pid)
  end

  def unregister do
    :persistent_term.erase({__MODULE__, :pid})
  end

  def maybe_send(message) do
    case :persistent_term.get({__MODULE__, :pid}, nil) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end
```

This is **single-slot global state**. If two tests run concurrently using `TestObserver.register/1`, they overwrite each other.

### Fix

Make TestObserver key include the test PID or use process dictionary:

```elixir
defmodule TestObserver do
  def register(pid) when is_pid(pid) do
    # Use calling process as key
    Process.put(:test_observer_pid, pid)
  end

  def unregister do
    Process.delete(:test_observer_pid)
  end

  def maybe_send(message) do
    case Process.get(:test_observer_pid) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end
```

Or pass the observer PID through the config/metadata instead of global state.

---

## Complete Refactored Test (Example)

```elixir
describe "telemetry emission" do
  test "emits telemetry and returns retryable error on 410 expired promise", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
      resp(conn, 410, %{"message" => "promise expired", "category" => "server"})
    end)

    # Use TelemetryHelpers for isolated handler
    {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])

    task = Future.poll("req-expired", config: config)

    assert {:error, %Error{status: 410, category: :server} = error} = Task.await(task, 1_000)
    assert error.message =~ "expired"

    # Use assert_telemetry with pattern matching
    {:telemetry, _, measurements, metadata} =
      TelemetryHelpers.assert_telemetry(
        [:tinkex, :future, :api_error],
        %{request_id: "req-expired", status: 410}
      )

    assert is_integer(measurements.latency_ms)

    # No manual detach - automatic cleanup via on_exit
  end
end
```

---

## Migration Checklist

- [ ] Update HTTPCase to enable `telemetry_isolation: true`
- [ ] Replace `attach_telemetry/1` calls with `TelemetryHelpers.attach_isolated/1`
- [ ] Replace `assert_receive {:telemetry, ...}` with pattern matching OR `TelemetryHelpers.assert_telemetry/2`
- [ ] Remove manual `:telemetry.detach/1` calls
- [ ] Fix TestObserver to use process-local storage
- [ ] Run tests 20 times to verify no flakiness

---

## Quick Fix vs Full Fix

### Quick Fix (Pattern Matching Only)

If you just want to stop the flakiness without updating HTTPCase:

```elixir
# Change:
assert_receive {:telemetry, [:tinkex, :future, :api_error], measurements, metadata}
assert metadata.request_id == "req-expired"

# To:
assert_receive {:telemetry, [:tinkex, :future, :api_error], measurements,
                %{request_id: "req-expired"} = metadata}
```

This filters events in the receive pattern, so wrong-ID events are not matched.

### Full Fix (TelemetryHelpers)

Requires HTTPCase update but provides:
- Automatic handler cleanup
- Consistent pattern across all tests
- Better error messages on failure
- Integration with Supertester telemetry events
