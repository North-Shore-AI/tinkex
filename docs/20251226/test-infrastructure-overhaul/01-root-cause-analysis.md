# Root Cause Analysis

## Overview

This document provides detailed technical analysis of each test flakiness issue in the Tinkex test suite.

---

## Failure 1: Telemetry Cross-Talk

### Symptom

```
1) test poll/2 emits telemetry and returns retryable error on 410 expired promise (Tinkex.Future.PollTest)
   test/tinkex/future/poll_test.exs:168
   Assertion with == failed
   code:  assert metadata.request_id == "req-expired"
   left:  "test-request-id"
   right: "req-expired"
```

### Location

- **Test file**: `test/tinkex/future/poll_test.exs:168-186`
- **Support file**: `test/support/http_case.ex:137-157`

### Root Cause

The test uses `attach_telemetry/1` from HTTPCase which registers a global telemetry handler:

```elixir
# test/support/http_case.ex:137-153
def attach_telemetry(events) do
  handler_id = "test-handler-#{:erlang.unique_integer()}"
  parent = self()

  :telemetry.attach_many(
    handler_id,
    events,
    &__MODULE__.handle_event/4,
    parent
  )
  # ...
end

def handle_event(event, measurements, metadata, parent) do
  send(parent, {:telemetry, event, measurements, metadata})
end
```

The handler sends **all** matching telemetry events to the test process, regardless of which test emitted them.

When the test runs with `async: true`:

1. `poll_test.exs:168` attaches handler for `[:tinkex, :future, :api_error]`
2. `future_test.exs` (running concurrently) emits `[:tinkex, :future, :api_error]` with `request_id: "test-request-id"`
3. `poll_test.exs:183` receives `future_test.exs`'s event first
4. `poll_test.exs:184` asserts `metadata.request_id == "req-expired"` but got `"test-request-id"`

### Evidence

The `left` value `"test-request-id"` comes from `future_test.exs:120`:

```elixir
# test/tinkex/future_test.exs:120
config = Config.new(
  # ...
  request_id: "test-request-id",  # <- This is the source
  # ...
)
```

### Fix

Use `Supertester.TelemetryHelpers` with test-scoped filtering:

```elixir
# Instead of:
handler_id = attach_telemetry([[:tinkex, :future, :api_error]])
assert_receive {:telemetry, [:tinkex, :future, :api_error], measurements, metadata}
assert metadata.request_id == "req-expired"

# Use:
{:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])
TelemetryHelpers.assert_telemetry([:tinkex, :future, :api_error], %{request_id: "req-expired"})
```

Or with pattern matching in `assert_receive`:

```elixir
assert_receive {:telemetry, [:tinkex, :future, :api_error], _, %{request_id: "req-expired"} = metadata}
```

---

## Failure 2: Agent Cleanup Race

### Symptom

```
1) test encode/2 caches tokenizer after first successful encode (Tinkex.Tokenizer.EncodeTest)
   test/tinkex/tokenizer/encode_test.exs:48
   ** (exit) exited in: GenServer.stop(#PID<0.852.0>, :normal, :infinity)
       ** (EXIT) exited in: :sys.terminate(#PID<0.852.0>, :normal, :infinity)
           ** (EXIT) shutdown
```

### Location

- **Test file**: `test/tinkex/tokenizer/encode_test.exs:47-55`

### Root Cause

The test creates a linked Agent and attempts to stop it in `on_exit`:

```elixir
# test/tinkex/tokenizer/encode_test.exs:47-55
{:ok, counter} = Agent.start_link(fn -> 0 end)

on_exit(fn ->
  if Process.alive?(counter) do
    Agent.stop(counter)
  end
end)
```

The race condition:

1. Test completes
2. Test process begins termination
3. Agent (linked to test process) receives EXIT signal
4. Agent begins shutdown
5. `on_exit` callback runs
6. `Process.alive?(counter)` returns `true` (process exists but is shutting down)
7. `Agent.stop(counter)` called
8. `Agent.stop` sends `:normal` exit and waits
9. Agent is already shutting down, so `GenServer.stop` times out or gets `:shutdown`

### Evidence

The error message shows the Agent was in the process of shutting down:
- `** (EXIT) shutdown` indicates the process was terminating

### Secondary Issue: ETS Table Clearing

The same test file also clears a global ETS table in setup:

```elixir
# test/tinkex/tokenizer/encode_test.exs:8-11
setup do
  ensure_table()
  :ets.delete_all_objects(:tinkex_tokenizers)  # GLOBAL MUTATION
  # ...
end
```

This affects concurrent tests that may be reading from the same table.

### Fix

1. **Agent**: Use `start_supervised!` instead of manual Agent management:

```elixir
# Instead of:
{:ok, counter} = Agent.start_link(fn -> 0 end)
on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

# Use:
counter = start_supervised!({Agent, fn -> 0 end})
```

2. **ETS**: Use `Supertester.ETSIsolation` to mirror the table:

```elixir
# Instead of:
:ets.delete_all_objects(:tinkex_tokenizers)

# Use:
use Supertester.ExUnitFoundation,
  isolation: :full_isolation,
  ets_isolation: [:tinkex_tokenizers]
```

---

## Failure 3: Logger Level Contamination

### Symptom

```
1) test headers and redaction redacts secrets when dumping headers (Tinkex.APITest)
   test/tinkex/api/api_test.exs:356
   Assertion with =~ failed
   code:  assert log =~ "[REDACTED]"
   left:  "\e[22m\n14:52:43.190 [info] training loop completed in 14ms (integration test)\n\e[0m"
   right: "[REDACTED]"
```

### Location

- **Test file**: `test/tinkex/api/api_test.exs:370-382`
- **Redaction code**: `lib/tinkex/api/headers.ex`

### Root Cause

The test modifies the global Logger level:

```elixir
# test/tinkex/api/api_test.exs:370-378
previous_level = Logger.level()

log =
  capture_log([level: :debug], fn ->
    Logger.configure(level: :debug)  # GLOBAL CHANGE
    assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
  end)

Logger.configure(level: previous_level)  # Restoration (if test doesn't fail)
```

The race condition:

1. Test A calls `Logger.configure(level: :debug)` (global)
2. Test B (concurrent) starts and expects default `:info` level
3. Test B captures logs expecting only `:info` and above
4. Test A's `:debug` setting affects Test B's Logger behavior
5. OR: Test B changes level during Test A's capture window
6. Result: Log capture contains wrong messages or missing expected messages

### Evidence

The `left` value shows a log message from a completely different test:
- `"training loop completed in 14ms (integration test)"` is not from `api_test.exs`
- This message leaked in because global Logger state was contaminated

### Fix

Use `Supertester.LoggerIsolation` for per-process level management:

```elixir
# Instead of:
previous_level = Logger.level()
log = capture_log([level: :debug], fn ->
  Logger.configure(level: :debug)
  # ...
end)
Logger.configure(level: previous_level)

# Use:
log = LoggerIsolation.capture_isolated!(:debug, fn ->
  # ...
end)
```

---

## Failure 4: MockHTTPClient Pattern (Structural Issue)

### Description

While not causing the specific failures above, `test/tinkex/future_test.exs` was recently modified to use an ad-hoc `MockHTTPClient` pattern that is inconsistent with the codebase.

### Location

- **Test file**: `test/tinkex/future_test.exs:18-106`

### Current Pattern

```elixir
defmodule MockHTTPClient do
  @behaviour Tinkex.HTTPClient

  def start_link(opts \\ []) do
    initial_state = %{responses: %{}, call_counts: %{}}
    Agent.start_link(fn -> Keyword.get(opts, :state, initial_state) end, name: __MODULE__)
  end

  def ensure_started do
    case start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  # ... mock implementation with mock_id partitioning
end
```

### Issues

1. **Inconsistency**: Other tests use `Tinkex.HTTPCase` with Bypass
2. **Global Agent**: Uses `name: __MODULE__` for a globally-named Agent
3. **Complex State Management**: Manual `mock_id` partitioning to achieve isolation
4. **Not Using Supertester**: Doesn't leverage existing isolation infrastructure

### Fix

Rewrite to use `Tinkex.HTTPCase` and Bypass:

```elixir
defmodule Tinkex.FutureTest do
  use Tinkex.HTTPCase, async: true

  test "408 handling", %{bypass: bypass, config: config} do
    stub_sequence(bypass, [
      fn conn -> resp(conn, 408, %{"message" => "timeout"}) end,
      fn conn -> resp(conn, 200, %{"result" => "success"}) end
    ])

    # Test implementation
  end
end
```

---

## Summary Table

| Issue | Type | Root Cause | Fix |
|-------|------|------------|-----|
| Telemetry cross-talk | Race condition | Global telemetry handlers | TelemetryHelpers.attach_isolated |
| Agent cleanup crash | Race condition | Linked process termination order | start_supervised! |
| ETS table clearing | Global mutation | :ets.delete_all_objects on shared table | ETSIsolation |
| Logger contamination | Global mutation | Logger.configure/1 | LoggerIsolation |
| MockHTTPClient | Structural | Inconsistent pattern, global Agent | HTTPCase + Bypass |

---

## Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                     Root Causes                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ Global        │     │ Global        │     │ Global        │
│ Telemetry     │     │ Logger        │     │ ETS           │
│ Handlers      │     │ Level         │     │ Tables        │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ poll_test.exs │     │ api_test.exs  │     │ encode_test   │
│ future_test   │     │               │     │ (+ cleanup)   │
└───────────────┘     └───────────────┘     └───────────────┘
```

All issues stem from the same fundamental problem: **async tests sharing global mutable state**.

---

## Test Files Requiring Changes

| File | Changes Needed |
|------|----------------|
| `test/support/http_case.ex` | Update `attach_telemetry/1` to use TelemetryHelpers |
| `test/tinkex/future/poll_test.exs` | Use TelemetryHelpers assertions |
| `test/tinkex/tokenizer/encode_test.exs` | Use start_supervised!, ETSIsolation |
| `test/tinkex/api/api_test.exs` | Use LoggerIsolation |
| `test/tinkex/future_test.exs` | Complete rewrite to use HTTPCase |
