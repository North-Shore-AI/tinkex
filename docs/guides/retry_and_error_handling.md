# Retry and Error Handling

Tinkex provides sophisticated retry mechanisms and error categorization to build resilient applications that gracefully handle transient failures, rate limits, and network issues. This guide covers the error model, retry strategies, telemetry integration, and production best practices.

## Overview

Tinkex's error handling system distinguishes between **user errors** (permanent failures that should not be retried) and **transient errors** (temporary failures that may succeed on retry). The retry mechanism uses exponential backoff with jitter and integrates with telemetry for observability.

Key components:
- `Tinkex.Error` - Structured error type with categorization
- Tinkex.Retry - Retry orchestration with telemetry
- Tinkex.RetryHandler - Configurable retry policy and timing
- `Tinkex.RateLimiter` - Shared backoff state for rate limit coordination
- `Tinkex.RetryConfig` - User-facing sampling retry configuration (max retries, jitter, progress timeout, connection limit)

## Sampling retry configuration

`SamplingClient` now accepts an optional `:retry_config`, letting you tune high-level retries and bound concurrent attempts per client. Defaults match the Python SDK: base delay 500ms, max delay 10s, ±25% jitter, 120-minute progress timeout, unbounded retries until the progress timeout elapses, and 100 max_connections.

```elixir
# Custom retry profile
retry_config =
  Tinkex.RetryConfig.new(
    max_retries: :infinity,
    base_delay_ms: 750,
    max_delay_ms: 15_000,
    jitter_pct: 0.25,
    max_connections: 20
  )

{:ok, sampler} =
  Tinkex.ServiceClient.create_sampling_client(service,
    base_model: "meta-llama/Llama-3.1-8B",
    retry_config: retry_config
  )

# Disable retries for a specific client
{:ok, sampler} =
  Tinkex.ServiceClient.create_sampling_client(service,
    base_model: "meta-llama/Llama-3.1-8B",
    retry_config: [enable_retry_logic: false]
  )
```

Notes:
- Retry logic runs at the SamplingClient layer; HTTP sampling calls still default to 0 low-level retries.
- `max_connections` gates concurrent sampling attempts using a semaphore to protect pools under load.
- `progress_timeout_ms` aborts a retry loop if no forward progress is observed within the window.

## The Error Model

### Tinkex.Error Structure

All Tinkex operations return `{:ok, result}` or `{:error, %Tinkex.Error{}}` tuples:

```elixir
%Tinkex.Error{
  message: "Rate limit exceeded",
  type: :api_status,
  status: 429,
  category: :transient,
  data: %{"retry_after_ms" => 5000},
  retry_after_ms: 5000
}
```

**Fields:**
- `message` - Human-readable error description
- `type` - Error classification (`:api_connection`, `:api_timeout`, `:api_status`, `:request_failed`, `:validation`)
- `status` - HTTP status code (if applicable)
- `category` - Request error category (`:user`, `:transient`, `:system`)
- `data` - Additional error context from the API
- `retry_after_ms` - Server-requested retry delay

### Error Types

**`:api_connection`**
Network connectivity failures (DNS resolution, connection refused, TLS errors). Always retryable.

**`:api_timeout`**
Request exceeded configured timeout or progress timeout. Retryable unless caused by user input.

**`:api_status`**
HTTP error status codes. Retryability depends on the status code and category.

**`:request_failed`**
General request failures including exceptions during execution. Retryability depends on context.

**`:validation`**
Client-side validation errors (invalid parameters, missing required fields). Never retryable.

### User Errors vs Transient Errors

The `Error.user_error?/1` function determines if an error is permanent:

```elixir
# User errors (NOT retryable)
Error.user_error?(%Error{category: :user})  # => true
Error.user_error?(%Error{status: 400})      # => true (bad request)
Error.user_error?(%Error{status: 401})      # => true (unauthorized)
Error.user_error?(%Error{status: 403})      # => true (forbidden)
Error.user_error?(%Error{status: 404})      # => true (not found)

# Transient errors (retryable)
Error.user_error?(%Error{status: 408})      # => false (request timeout)
Error.user_error?(%Error{status: 429})      # => false (rate limit)
Error.user_error?(%Error{status: 500})      # => false (server error)
Error.user_error?(%Error{status: 502})      # => false (bad gateway)
Error.user_error?(%Error{status: 503})      # => false (service unavailable)
```

**Truth table:**
- `category == :user` → **User error** (never retry)
- Status `4xx` (except `408`, `429`) → **User error** (never retry)
- Everything else → **Transient error** (retry allowed)

## Basic Retry Usage

### Simple Retry

Wrap any operation returning `{:ok, value}` or `{:error, error}`:

```elixir
alias Tinkex.Retry

result = Retry.with_retry(fn ->
  # Your operation here
  SamplingClient.sample(sampler, prompt, params)
end)

case result do
  {:ok, response} ->
    IO.puts("Success: #{inspect(response)}")

  {:error, error} ->
    IO.puts("Failed after retries: #{Error.format(error)}")
end
```

### Custom Retry Configuration

Configure retry behavior with `RetryHandler`:

```elixir
alias Tinkex.{Retry, RetryHandler}

handler = RetryHandler.new(
  max_retries: :infinity,            # Time-bounded by progress_timeout_ms (default)
  base_delay_ms: 1000,               # Start with 1s delay (default: 500ms)
  max_delay_ms: 30_000,              # Cap at 30s (default: 10s)
  jitter_pct: 1.0,                   # Full jitter (default: 0.25)
  progress_timeout_ms: 60_000        # Abort if no progress for 60s (default: 120m)
)

result = Retry.with_retry(&my_operation/0, handler: handler)
```

### Exponential Backoff with Jitter

Delays grow exponentially: `base_delay_ms * 2^attempt`, capped at `max_delay_ms`, with randomized jitter to prevent thundering herd:

```elixir
# With base_delay_ms: 500, max_delay_ms: 8000, jitter_pct: 1.0
# Attempt 0: 0-500ms    (500 * 2^0 * random)
# Attempt 1: 0-1000ms   (500 * 2^1 * random)
# Attempt 2: 0-2000ms   (500 * 2^2 * random)
# Attempt 3: 0-4000ms   (500 * 2^3 * random)
# Attempt 4: 0-8000ms   (capped at max_delay_ms)
```

**Disable jitter** (for testing or deterministic delays):

```elixir
handler = RetryHandler.new(jitter_pct: 0.0)
```

## Progress Timeout

The progress timeout prevents infinite retry loops when operations make no forward progress:

```elixir
handler = RetryHandler.new(
  max_retries: :infinity,        # Time-bounded instead of attempt-bounded
  progress_timeout_ms: 30_000    # Abort if stuck for 30s
)
```

Progress is measured from the last recorded progress event (initially the start of the retry loop). Because retries no longer reset this timer, loops are bounded by `progress_timeout_ms` (default: 120 minutes) unless you explicitly call `RetryHandler.record_progress/1` when real work is happening between attempts. If the elapsed time exceeds `progress_timeout_ms`, the retry loop aborts with:

```elixir
{:error, %Error{type: :api_timeout, message: "Progress timeout exceeded"}}
```

This is critical for long-running operations where individual attempts may hang or repeatedly fail without making progress.

## Rate Limiting and Backoff Windows

`Tinkex.RateLimiter` provides shared backoff state per `{base_url, api_key}` combination. When the server returns `429 Too Many Requests` with `retry_after_ms`, the limiter blocks all requests to that endpoint until the backoff window expires.

### How It Works

```elixir
alias Tinkex.RateLimiter

# Get limiter for an API key + base URL
limiter = RateLimiter.for_key({"https://api.example.com", "key-123"})

# Check if currently in backoff
RateLimiter.should_backoff?(limiter)  # => false

# Set a 5-second backoff window
RateLimiter.set_backoff(limiter, 5000)

# Now backoff is active
RateLimiter.should_backoff?(limiter)  # => true

# Block until backoff expires
RateLimiter.wait_for_backoff(limiter)  # Sleeps in 100ms intervals

# Or clear it manually
RateLimiter.clear_backoff(limiter)
```

### Automatic Integration

When `SamplingClient`, `TrainingClient`, or `RestClient` receive a `429` error with `retry_after_ms`, they automatically:

1. Extract the limiter for the current endpoint
2. Set the backoff window
3. Wait before the next retry

This ensures **all concurrent requests** to the same API key respect rate limits, not just the individual operation being retried.

## Telemetry Events

The retry mechanism emits four telemetry events for observability:

### Event Reference

**`[:tinkex, :retry, :attempt, :start]`**
Fired when an attempt begins.

```elixir
# Measurements
%{system_time: integer()}

# Metadata
%{attempt: 0, operation: "sample"}
```

**`[:tinkex, :retry, :attempt, :stop]`**
Fired when an attempt succeeds.

```elixir
# Measurements
%{duration: integer()}  # Nanoseconds

# Metadata
%{attempt: 2, result: :ok}
```

**`[:tinkex, :retry, :attempt, :retry]`**
Fired when an attempt fails with a retryable error.

```elixir
# Measurements
%{duration: integer(), delay_ms: integer()}

# Metadata
%{
  attempt: 1,
  error: %Error{type: :api_status, status: 500},
  operation: "sample"
}
```

**`[:tinkex, :retry, :attempt, :failed]`**
Fired when all retries are exhausted or a non-retryable error occurs.

```elixir
# Measurements
%{duration: integer()}

# Metadata
%{
  attempt: 3,
  result: :failed,
  error: %Error{type: :validation, message: "Invalid parameter"}
}
```

### Attaching Telemetry Handlers

Log retry events to understand application behavior:

```elixir
:telemetry.attach_many(
  "tinkex-retry-logger",
  [
    [:tinkex, :retry, :attempt, :start],
    [:tinkex, :retry, :attempt, :retry],
    [:tinkex, :retry, :attempt, :stop],
    [:tinkex, :retry, :attempt, :failed]
  ],
  &handle_retry_event/4,
  nil
)

def handle_retry_event(event, measurements, metadata, _config) do
  case event do
    [:tinkex, :retry, :attempt, :start] ->
      Logger.info("Retry attempt #{metadata.attempt} starting")

    [:tinkex, :retry, :attempt, :retry] ->
      Logger.warning(
        "Retry attempt #{metadata.attempt} failed, " <>
        "retrying after #{measurements.delay_ms}ms: #{Error.format(metadata.error)}"
      )

    [:tinkex, :retry, :attempt, :stop] ->
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      Logger.info("Retry attempt #{metadata.attempt} succeeded in #{duration_ms}ms")

    [:tinkex, :retry, :attempt, :failed] ->
      Logger.error(
        "All retries exhausted at attempt #{metadata.attempt}: #{Error.format(metadata.error)}"
      )
  end
end
```

## Complete Example

From `examples/retry_and_capture.exs`:

```elixir
alias Tinkex.{Error, Retry, RetryHandler}

# Simulate a flaky operation that fails twice then succeeds
defp flaky_operation do
  attempt = Process.get(:retry_demo_attempt, 0) + 1
  Process.put(:retry_demo_attempt, attempt)

  case attempt do
    n when n < 3 ->
      {:error, Error.new(:api_status, "synthetic 500 for retry demo", status: 500)}

    _ ->
      {:ok, "succeeded on attempt #{attempt}"}
  end
end

# Configure retry handler
handler = RetryHandler.new(
  base_delay_ms: 200,
  jitter_pct: 0.0,      # Deterministic delays for demo
  max_retries: 2        # Override the default (:infinity) to keep the demo short
)

# Execute with retry
result = Retry.with_retry(
  &flaky_operation/0,
  handler: handler,
  telemetry_metadata: %{operation: "retry_demo"}
)

case result do
  {:ok, value} ->
    IO.puts("Success: #{value}")

  {:error, error} ->
    IO.puts("Failed: #{Error.format(error)}")
end
```

**Output with telemetry attached:**

```
[retry start] attempt=0
[retry retry] attempt=0 delay=200ms duration=1ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=1
[retry retry] attempt=1 delay=400ms duration=0ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=2
[retry stop] attempt=2 duration=0ms result=ok
Success: succeeded on attempt 3
```

## Best Practices for Production

### 1. Configure Timeouts Appropriately

Balance responsiveness with operation duration:

```elixir
# For fast APIs (< 5s expected)
handler = RetryHandler.new(
  base_delay_ms: 500,
  max_delay_ms: 8_000,
  progress_timeout_ms: 30_000
)

# For slow operations (training, large downloads)
handler = RetryHandler.new(
  base_delay_ms: 2000,
  max_delay_ms: 60_000,
  progress_timeout_ms: 300_000  # 5 minutes
)
```

### 2. Use Full Jitter in Production

Prevent thundering herd when many clients retry simultaneously:

```elixir
# Good (default)
handler = RetryHandler.new(jitter_pct: 1.0)

# Only disable for testing
handler = RetryHandler.new(jitter_pct: 0.0)
```

### 3. Respect Server-Requested Delays

The retry mechanism automatically honors `retry_after_ms` from API responses. Don't override this with shorter delays.

### 4. Monitor Retry Metrics

Track retry rates to identify systemic issues:

```elixir
defmodule MyApp.RetryMetrics do
  def init do
    :telemetry.attach_many(
      "retry-metrics",
      [
        [:tinkex, :retry, :attempt, :retry],
        [:tinkex, :retry, :attempt, :failed]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:tinkex, :retry, :attempt, :retry], _measurements, metadata, _config) do
    :telemetry.execute(
      [:my_app, :retry, :count],
      %{count: 1},
      %{status: metadata.error.status}
    )
  end

  def handle_event([:tinkex, :retry, :attempt, :failed], _measurements, metadata, _config) do
    :telemetry.execute(
      [:my_app, :retry, :exhausted],
      %{count: 1},
      %{error_type: metadata.error.type}
    )
  end
end
```

### 5. Tune Retry Bounds

Balance reliability with latency by adjusting `progress_timeout_ms` and optionally capping attempts:

```elixir
# For interactive applications (< 30s total)
handler = RetryHandler.new(max_retries: 3, progress_timeout_ms: 30_000)

# For background jobs (tolerate longer delays)
handler = RetryHandler.new(max_retries: 8, progress_timeout_ms: 120_000)

# For critical operations (time-bounded, no attempt cap)
handler = RetryHandler.new(max_retries: :infinity, progress_timeout_ms: 600_000)
```

### 6. Handle Non-Retryable Errors Explicitly

Don't retry user errors:

```elixir
case Retry.with_retry(&my_operation/0) do
  {:ok, result} ->
    {:ok, result}

  {:error, %Error{} = error} ->
    if Error.user_error?(error) do
      # Permanent failure - log and notify user
      Logger.error("User error: #{Error.format(error)}")
      {:error, :invalid_request}
    else
      # Transient failure exhausted retries - maybe queue for later
      Logger.warning("Transient error exhausted retries: #{Error.format(error)}")
      {:error, :service_unavailable}
    end
end
```

### 7. Use Telemetry Capture for Exception Safety

Wrap retry operations in `Telemetry.Capture` to ensure exceptions are logged:

```elixir
alias Tinkex.Telemetry.Capture
require Capture

Capture.capture_exceptions reporter: my_reporter do
  Retry.with_retry(&potentially_raising_operation/0)
  |> case do
    {:ok, value} -> value
    {:error, error} -> raise "Operation failed: #{Error.format(error)}"
  end
end
```

## Error Formatting

Format errors for logs or user display:

```elixir
error = Error.new(:api_status, "Rate limit exceeded", status: 429)

# Via Error.format/1
Error.format(error)
# => "[api_status (429)] Rate limit exceeded"

# Via String.Chars protocol
to_string(error)
# => "[api_status (429)] Rate limit exceeded"

# Direct interpolation
"Error occurred: #{error}"
# => "Error occurred: [api_status (429)] Rate limit exceeded"
```

## Advanced: Custom Retry Logic

For specialized retry needs, implement your own retry loop:

```elixir
defmodule MyApp.CustomRetry do
  alias Tinkex.{Error, RetryHandler}

  def retry_with_circuit_breaker(fun, opts \\ []) do
    handler = Keyword.get(opts, :handler, RetryHandler.new())
    circuit = Keyword.get(opts, :circuit_breaker)

    if circuit_open?(circuit) do
      {:error, Error.new(:api_connection, "Circuit breaker open")}
    else
      do_retry(fun, handler, circuit)
    end
  end

  defp do_retry(fun, handler, circuit) do
    case fun.() do
      {:ok, value} ->
        record_success(circuit)
        {:ok, value}

      {:error, error} ->
        record_failure(circuit)

        if RetryHandler.retry?(handler, error) do
          Process.sleep(RetryHandler.next_delay(handler))
          do_retry(fun, RetryHandler.increment_attempt(handler), circuit)
        else
          {:error, error}
        end
    end
  end

  # Circuit breaker implementation...
end
```

## Related Resources

- API reference: `docs/guides/api_reference.md`
- Troubleshooting: `docs/guides/troubleshooting.md`
- Telemetry guide: `docs/guides/telemetry.md` (if available)
- Examples: `examples/retry_and_capture.exs`
