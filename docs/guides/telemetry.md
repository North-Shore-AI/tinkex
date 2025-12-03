# Telemetry

The Tinkex telemetry system provides session-scoped event capture and reporting to the Tinker backend. It automatically tracks HTTP requests, queue state changes, exceptions, and custom application events with built-in batching, retries, and graceful shutdown semantics.

ServiceClient, TrainingClient, and SamplingClient wrap public entrypoints with the telemetry capture layer, so unhandled exceptions are logged automatically and fatal paths emit session-end events without additional instrumentation.

## Overview

Tinkex telemetry consists of two main components:

1. **Telemetry.Reporter** - A GenServer that batches events and ships them to `/api/v1/telemetry`
2. **Telemetry.Capture** - Macros for capturing exceptions in synchronous and async code

Key features:

- Automatic session lifecycle tracking (SESSION_START, SESSION_END)
- Batched event delivery (up to 100 events per request)
- Exponential backoff retry logic (up to 3 retries)
- Periodic and threshold-based flushing
- Wait-until-drained semantics for graceful shutdown
- Environment-based enable/disable (TINKER_TELEMETRY)

## Event Types

The telemetry reporter captures several event types:

- **SESSION_START** - Emitted when the reporter starts
- **SESSION_END** - Emitted during graceful shutdown
- **GENERIC_EVENT** - Custom application events with arbitrary data
- **UNHANDLED_EXCEPTION** - Captured exceptions with stacktraces
- **HTTP telemetry** - Automatic capture of `[:tinkex, :http, :request, :*]` events
- **Queue telemetry** - Automatic capture of `[:tinkex, :queue, :state_change]` events

## Setting Up the Reporter

The reporter is typically started automatically by `ServiceClient`, but you can start it manually:

```elixir
config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))

{:ok, reporter} =
  Tinkex.Telemetry.Reporter.start_link(
    config: config,
    session_id: "session-123",
    flush_interval_ms: 10_000,      # Flush every 10 seconds
    flush_threshold: 100,            # Flush when queue reaches 100 events
    http_timeout_ms: 5_000,          # HTTP request timeout
    max_retries: 3,                  # Retry failed sends up to 3 times
    retry_base_delay_ms: 1_000       # Base delay for exponential backoff
  )
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `:config` | *required* | `Tinkex.Config.t()` with API credentials |
| `:session_id` | *required* | Tinker session identifier |
| `:handler_id` | auto-generated | Telemetry handler ID |
| `:events` | HTTP + queue | List of telemetry events to capture |
| `:attach_events?` | `true` | Whether to attach telemetry handlers |
| `:flush_interval_ms` | `10_000` | Periodic flush interval (10 seconds) |
| `:flush_threshold` | `100` | Flush when queue reaches this size |
| `:flush_timeout_ms` | `30_000` | Max wait time for drain operations |
| `:http_timeout_ms` | `5_000` | HTTP request timeout |
| `:max_retries` | `3` | Max retries per batch |
| `:retry_base_delay_ms` | `1_000` | Base delay for exponential backoff |
| `:max_queue_size` | `10_000` | Drop events beyond this size |
| `:max_batch_size` | `100` | Events per POST request |
| `:enabled` | from env | Override `TINKER_TELEMETRY` env flag |

## Logging Custom Events

Use `Reporter.log/4` to emit generic application events:

```elixir
# Basic event
Reporter.log(reporter, "user.action", %{"button" => "submit"})

# With severity level
Reporter.log(reporter, "cache.miss", %{"key" => "user:123"}, :warning)

# Multiple data fields
Reporter.log(reporter, "request.processed", %{
  "duration_ms" => 250,
  "cache_hit" => true,
  "user_id" => 42
}, :info)
```

### Severity Levels

Supported severity levels (atoms or strings):

- `:debug` / `"DEBUG"`
- `:info` / `"INFO"`
- `:warning` / `"WARNING"`
- `:error` / `"ERROR"`
- `:critical` / `"CRITICAL"`

## Capturing Exceptions

### Non-Fatal Exceptions

Use `log_exception/3` to capture exceptions without blocking:

```elixir
try do
  risky_operation()
rescue
  exception ->
    Reporter.log_exception(reporter, exception, :error)
    # Exception is logged, async flush triggered
    reraise exception, __STACKTRACE__
end
```

### Fatal Exceptions

Use `log_fatal_exception/3` for fatal errors that require immediate flushing:

```elixir
try do
  critical_operation()
rescue
  exception ->
    Reporter.log_fatal_exception(reporter, exception, :critical)
    # Emits SESSION_END, flushes synchronously, waits until drained
    reraise exception, __STACKTRACE__
end
```

**Fatal exception behavior:**
1. Logs the exception as UNHANDLED_EXCEPTION
2. Enqueues a SESSION_END event
3. Flushes all pending events synchronously
4. Waits until all batches are sent (up to `flush_timeout_ms`)
5. Logs the session ID for debugging

## Using Capture Macros

The Tinkex.Telemetry.Capture module provides macros for automatic exception capture.

### Synchronous Code

Wrap synchronous code with `capture_exceptions/2`:

```elixir
import Tinkex.Telemetry.Capture

capture_exceptions reporter: reporter do
  perform_risky_operation()
end

# With options
capture_exceptions reporter: reporter, fatal?: true, severity: :critical do
  critical_operation()
end
```

The macro automatically:
- Catches all exceptions and errors
- Logs them to the reporter
- Re-raises the original exception

### Async Tasks

Wrap async operations with `async_capture/2`:

```elixir
import Tinkex.Telemetry.Capture

task = async_capture reporter: reporter do
  expensive_computation()
end

result = Task.await(task, 10_000)
```

This wraps `Task.async/1` and captures any exceptions that occur in the task process.

**Options for both macros:**
- `:reporter` - Reporter pid or `nil` (no-op when `nil`)
- `:fatal?` - When `true`, calls `log_fatal_exception/3` (default: `false`)
- `:severity` - Severity level for the exception (default: `:error`)

## Automatic Telemetry Events

The reporter automatically captures standard `:telemetry` events when `:attach_events?` is `true` (default).

### HTTP Request Events

All HTTP requests emit three events:

```elixir
# Start of request
[:tinkex, :http, :request, :start]
# measurements: %{system_time: integer()}
# metadata: %{session_id: string(), method: atom(), path: string()}

# Successful completion
[:tinkex, :http, :request, :stop]
# measurements: %{duration: integer()}
# metadata: %{session_id: string(), status: integer()}

# Exception during request
[:tinkex, :http, :request, :exception]
# measurements: %{duration: integer()}
# metadata: %{session_id: string(), kind: atom(), reason: term()}
```

### Queue State Changes

Queue state transitions emit:

```elixir
[:tinkex, :queue, :state_change]
# measurements: %{queue_depth: integer()}
# metadata: %{session_id: string(), from: atom(), to: atom()}
```

### Session-Scoped Filtering

Only events with matching `:session_id` metadata are captured and forwarded to the backend. This prevents cross-session contamination when multiple sessions run concurrently.

## Batching and Flush Semantics

The reporter uses intelligent batching to optimize network usage:

### Automatic Flushing

Events are flushed automatically when:

1. **Periodic interval** - Every `flush_interval_ms` (default: 10 seconds)
2. **Threshold reached** - When queue size reaches `flush_threshold` (default: 100 events)
3. **Exception logged** - Non-fatal exceptions trigger an async flush
4. **Fatal exception** - Synchronous flush with wait-until-drained

### Manual Flushing

Force a flush with `Reporter.flush/2`:

```elixir
# Async flush (returns immediately)
Reporter.flush(reporter)

# Sync flush (waits for batches to be sent)
Reporter.flush(reporter, sync?: true)

# Sync flush with drain wait (waits until all events are acknowledged)
Reporter.flush(reporter, sync?: true, wait_drained?: true)
```

### Batching Behavior

- Events are grouped into batches of up to `max_batch_size` (default: 100)
- Multiple batches are sent sequentially
- Each batch includes session metadata (session_id, platform, SDK version)

Example batch structure:

```elixir
%{
  session_id: "session-abc123",
  platform: "unix/linux",
  sdk_version: "0.1.2",
  events: [
    %{
      event: "GENERIC_EVENT",
      event_id: "a1b2c3...",
      event_session_index: 5,
      severity: "INFO",
      timestamp: "2025-11-26T10:30:45Z",
      event_name: "user.action",
      event_data: %{"button" => "submit"}
    },
    # ... up to 100 events
  ]
}
```

## Retry Behavior

Failed sends are retried with exponential backoff:

1. **First attempt** - Immediate send
2. **Retry 1** - Wait ~1000ms (base_delay)
3. **Retry 2** - Wait ~2000ms (base_delay * 2)
4. **Retry 3** - Wait ~4000ms (base_delay * 4)
5. **Give up** - Log warning and drop batch

The backoff delay includes 10% random jitter to prevent thundering herd effects.

**Example:**
```elixir
{:ok, reporter} =
  Tinkex.Telemetry.Reporter.start_link(
    config: config,
    session_id: session_id,
    max_retries: 5,              # Try up to 5 times
    retry_base_delay_ms: 500     # Start with 500ms delay
  )
```

## Wait-Until-Drained

For graceful shutdown, use `wait_until_drained/2` to block until all queued events are sent:

```elixir
# Queue some events
Reporter.log(reporter, "shutdown.starting", %{})

# Wait up to 30 seconds for all events to be sent
drained = Reporter.wait_until_drained(reporter, 30_000)

case drained do
  true -> IO.puts("All telemetry sent successfully")
  false -> IO.puts("Timeout waiting for telemetry drain")
end
```

**Internal counters:**
- `push_counter` - Incremented when events are enqueued
- `flush_counter` - Incremented when events are sent
- Drained when `flush_counter >= push_counter`

This is automatically used during graceful shutdown with `Reporter.stop/2`.

## Graceful Shutdown

Stop the reporter gracefully with `Reporter.stop/2`:

```elixir
Reporter.stop(reporter, 5_000)
```

This performs the following steps:
1. Enqueues a SESSION_END event (if not already emitted)
2. Flushes all pending events synchronously
3. Waits until all batches are sent (up to timeout)
4. Stops the GenServer

The reporter also implements `terminate/2`, so if the process is terminated normally, it will perform the same graceful shutdown sequence.

## Disabling Telemetry

Telemetry can be disabled via the `TINKER_TELEMETRY` environment variable:

```bash
# Disable telemetry
export TINKER_TELEMETRY=0
# or
export TINKER_TELEMETRY=false
# or
export TINKER_TELEMETRY=no

# Enable telemetry (default)
export TINKER_TELEMETRY=1
# or
export TINKER_TELEMETRY=true
# or
export TINKER_TELEMETRY=yes
```

When disabled:
- `Reporter.start_link/1` returns `:ignore`
- All reporter functions become no-ops (return `false` or `:ok`)
- No network requests are made
- No events are logged

You can also override the environment variable per-reporter:

```elixir
# Force enable, even if TINKER_TELEMETRY=0
{:ok, reporter} =
  Tinkex.Telemetry.Reporter.start_link(
    config: config,
    session_id: session_id,
    enabled: true
  )

# Force disable, even if TINKER_TELEMETRY=1
reporter =
  case Tinkex.Telemetry.Reporter.start_link(
    config: config,
    session_id: session_id,
    enabled: false
  ) do
    {:ok, pid} -> pid
    :ignore -> nil
  end
```

## Complete Example

Here's a complete example showing all major features:

```elixir
import Tinkex.Telemetry.Capture

{:ok, _} = Application.ensure_all_started(:tinkex)

config = Tinkex.Config.new(
  api_key: System.fetch_env!("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod"
)

# Start service client (includes telemetry reporter)
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

# Get the reporter
{:ok, reporter} =
  case Tinkex.ServiceClient.telemetry_reporter(service) do
    {:ok, pid} -> {:ok, pid}
    {:error, :disabled} ->
      IO.puts("Telemetry disabled, exiting")
      System.halt(0)
  end

# Log application start
Reporter.log(reporter, "app.started", %{
  "environment" => "production",
  "version" => "1.0.0"
})

# Perform sampling with automatic HTTP telemetry
{:ok, sampler} =
  Tinkex.ServiceClient.create_sampling_client(service,
    base_model: "meta-llama/Llama-3.1-8B"
  )

{:ok, prompt} =
  Tinkex.Types.ModelInput.from_text("Hello there",
    model_name: "meta-llama/Llama-3.1-8B"
  )

params = %Tinkex.Types.SamplingParams{max_tokens: 32, temperature: 0.7}

# Wrap in exception capture
capture_exceptions reporter: reporter do
  {:ok, task} =
    Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 1)

  {:ok, response} = Task.await(task, 10_000)

  Reporter.log(reporter, "sampling.complete", %{
    "tokens" => length(List.first(response.sequences, %{tokens: []}).tokens)
  })
end

# Async task with exception capture
task = async_capture reporter: reporter do
  Process.sleep(1_000)
  :expensive_result
end

result = Task.await(task)

# Log completion and shutdown gracefully
Reporter.log(reporter, "app.stopping", %{"result" => inspect(result)})
Reporter.stop(reporter, 10_000)  # Wait up to 10s for drain

IO.puts("All telemetry sent, goodbye!")
```

## Debugging

### Enable Logger

Attach a logger to see telemetry events in real-time:

```elixir
logger_id = Tinkex.Telemetry.attach_logger(level: :info)

# ... run your code ...

Tinkex.Telemetry.detach(logger_id)
```

### Check Reporter State

Inspect the reporter state for debugging:

```elixir
state = :sys.get_state(reporter)

IO.inspect(state.queue_size, label: "Queue size")
IO.inspect(state.push_counter, label: "Pushed events")
IO.inspect(state.flush_counter, label: "Flushed events")
IO.inspect(state.session_ended?, label: "Session ended")
```

### Common Issues

**Queue full warnings:**
```
Telemetry queue full (10000), dropping event
```
Solution: Increase `max_queue_size` or reduce `flush_threshold` for more frequent flushing.

**Retry failures:**
```
Telemetry send failed after 3 retries: {:error, :timeout}
```
Solution: Increase `http_timeout_ms` or `max_retries`, check network connectivity.

**Drain timeout:**
```
false = Reporter.wait_until_drained(reporter, 5_000)
```
Solution: Increase timeout or check for network issues preventing batch delivery.

## Best Practices

1. **Use ServiceClient's built-in reporter** - It's automatically scoped to the session
2. **Capture exceptions at boundaries** - Wrap top-level operations with `capture_exceptions`
3. **Use severity levels appropriately** - Reserve `:critical` for fatal errors
4. **Flush before shutdown** - Always call `Reporter.stop/2` or `wait_until_drained/2`
5. **Monitor queue size** - Watch for "queue full" warnings in production
6. **Test with telemetry disabled** - Ensure your app works with `TINKER_TELEMETRY=0`
7. **Structure event data consistently** - Use the same keys across similar events

## What to Read Next

- API overview: `docs/guides/api_reference.md`
- Getting started: `docs/guides/getting_started.md`
- Troubleshooting tips: `docs/guides/troubleshooting.md`
