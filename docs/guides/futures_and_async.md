# Futures and Async Operations

This guide covers asynchronous request handling in Tinkex using the `Future` module. Learn how to start polling operations, await results, handle queue states, and implement custom observers for production workloads.

## Overview

Tinkex follows an async-by-default design where long-running operations (sampling, training, checkpoint creation) return immediately with a request ID, then poll the server until completion. The `Future` module provides the client-side polling abstraction that:

- Returns `Task.t()` so you can integrate with your concurrency model
- Implements exponential backoff with configurable timeouts
- Emits telemetry events for queue state transitions
- Supports custom observers via the `QueueStateObserver` behaviour

This approach decouples request initiation from result retrieval, enabling concurrent operations without blocking your application.

## How Futures Work

When you call a Tinkex API that creates a long-running request (e.g., `SamplingClient.sample/4` or `TrainingClient.forward_backward/3`), the server returns a request ID immediately. The client then polls `/api/v1/retrieve_future` until the request completes, fails, or times out.

**Server-side polling flow:**

1. Client calls `Future.poll/2` with request ID and config
2. Returns a `Task.t()` that repeatedly calls `retrieve_future`
3. Server responds with one of:
   - `%FutureCompletedResponse{}` → poll returns `{:ok, result}`
   - `%FuturePendingResponse{}` → sleep with exponential backoff, retry
   - `%FutureFailedResponse{}` → categorize error, retry or fail
   - `%TryAgainResponse{}` → emit queue state telemetry, sleep, retry
4. Client awaits the task to get the final result

**Backoff strategy:**

- Initial backoff: 1 second
- Max backoff: 30 seconds
- Formula: `min(2^iteration * 1000ms, 30000ms)`
- `TryAgainResponse` may provide `retry_after_ms` to override

## Starting a Poll Operation

Use `Future.poll/2` to begin polling a server-side future. It returns a `Task.t()` immediately, allowing you to await the result later or run multiple polls concurrently.

```elixir
alias Tinkex.Future

# Poll a request by ID
task = Future.poll("req-abc123", config: config)

# Poll from a response map
response = %{"request_id" => "req-abc123", "status" => "pending"}
task = Future.poll(response, config: config)

# With custom timeouts
task = Future.poll("req-abc123",
  config: config,
  timeout: 60_000,        # overall polling deadline (60s)
  http_timeout: 5_000     # per-request HTTP timeout (5s)
)
```

**Options:**

- `:config` (required) — `Tinkex.Config.t()` with API credentials
- `:timeout` — polling deadline in milliseconds (default: `:infinity`)
- `:http_timeout` — per-request timeout (default: `config.timeout`)
- `:queue_state_observer` — module implementing `QueueStateObserver` behaviour
- `:telemetry_metadata` — additional metadata for telemetry events
- `:sleep_fun` — custom sleep function for testing (default: `&Process.sleep/1`)

## Awaiting a Single Future

Use `Future.await/2` to block until a polling task completes. This wraps `Task.await/2` but converts exits and timeouts into `{:error, %Tinkex.Error{type: :api_timeout}}` tuples instead of raising.

```elixir
# Basic await
task = Future.poll("req-abc123", config: config)
case Future.await(task, 30_000) do
  {:ok, result} ->
    IO.inspect(result, label: "success")

  {:error, %Tinkex.Error{type: :api_timeout} = error} ->
    IO.puts("Timed out: #{error.message}")

  {:error, %Tinkex.Error{} = error} ->
    IO.puts("Failed: #{error.message}")
end
```

**Timeout semantics:**

- `Future.poll/2`'s `:timeout` — controls how long the polling loop runs
- `Future.await/2`'s timeout — controls how long the caller waits on the task
- These are independent: set both if you want strict deadlines

```elixir
# Poll for max 60s, but caller will wait max 70s
task = Future.poll("req-abc123", config: config, timeout: 60_000)
Future.await(task, 70_000)
```

## Awaiting Multiple Futures

Use `Future.await_many/2` to await multiple polling tasks in parallel. Results are returned in input order, with each entry being `{:ok, result}` or `{:error, %Tinkex.Error{}}`.

```elixir
# Start multiple polls concurrently
tasks = [
  Future.poll("req-1", config: config),
  Future.poll("req-2", config: config),
  Future.poll("req-3", config: config)
]

# Await all (blocks until all complete or time out)
results = Future.await_many(tasks, 30_000)

# Process results in order
Enum.zip(["req-1", "req-2", "req-3"], results)
|> Enum.each(fn {id, result} ->
  case result do
    {:ok, data} -> IO.puts("#{id} succeeded: #{inspect(data)}")
    {:error, error} -> IO.puts("#{id} failed: #{error.message}")
  end
end)
```

**Key behavior:**

- All tasks are awaited independently (no short-circuit on first failure)
- Order is preserved: `results[i]` corresponds to `tasks[i]`
- Exits or timeouts are converted to `{:error, %Tinkex.Error{type: :api_timeout}}`
- Non-raising: you always get a list of results, never an exception

**Practical example: concurrent client creation**

```elixir
# Create multiple sampling clients in parallel
checkpoint_paths = [
  "tinker://run-1/weights/0010",
  "tinker://run-2/weights/0020",
  "tinker://run-3/weights/0030"
]

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

tasks =
  Enum.map(checkpoint_paths, fn path ->
    Tinkex.SamplingClient.create_async(service, model_path: path)
  end)

results = Task.await_many(tasks, 60_000)

clients =
  results
  |> Enum.zip(checkpoint_paths)
  |> Enum.map(fn {result, path} ->
    case result do
      {:ok, pid} ->
        IO.puts("✓ #{path} -> #{inspect(pid)}")
        pid

      {:error, error} ->
        IO.puts("✗ #{path} failed: #{error.message}")
        nil
    end
  end)
  |> Enum.reject(&is_nil/1)
```

**Training client async creation:**

```elixir
# Create training clients asynchronously
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

# Async LoRA training client
task = Tinkex.ServiceClient.create_lora_training_client_async(
  service,
  "meta-llama/Llama-3.1-8B",
  rank: 32
)
{:ok, training_client} = Task.await(task, 30_000)

# Async training client from checkpoint
task = Tinkex.ServiceClient.create_training_client_from_state_async(
  service,
  "tinker://run-123/weights/0001"
)
{:ok, restored_client} = Task.await(task, 60_000)

# Async training client from checkpoint (weights + optimizer)
task = Tinkex.ServiceClient.create_training_client_from_state_with_optimizer_async(
  service,
  "tinker://run-123/weights/0001"
)
{:ok, restored_with_opt} = Task.await(task, 60_000)
```

See `examples/async_client_creation.exs` for a complete runnable example.

## Queue State Telemetry

The polling loop emits `[:tinkex, :queue, :state_change]` telemetry events whenever the server sends a `TryAgainResponse` with a queue state transition. Metadata always includes `%{queue_state: atom, request_id: binary}`.

**Queue states:**

- `:active` — request is actively processing
- `:paused_rate_limit` — server is rate-limiting the request
- `:paused_capacity` — server lacks capacity (GPU slots full)
- `:unknown` — unrecognized state from server

**Example telemetry handler:**

```elixir
:telemetry.attach(
  "tinkex-queue-logger",
  [:tinkex, :queue, :state_change],
  fn _event, _measurements, metadata, _config ->
    IO.puts("Queue state: #{metadata.queue_state} (request: #{metadata.request_id})")
  end,
  nil
)

# Now poll a request
task = Future.poll("req-abc123", config: config)
Future.await(task, 30_000)

# Telemetry handler will print state changes during polling
```

**Custom metadata:**

Add your own metadata via `:telemetry_metadata` to correlate events with your application context:

```elixir
task = Future.poll("req-abc123",
  config: config,
  telemetry_metadata: %{
    user_id: "user-123",
    experiment_id: "exp-456"
  }
)
```

Telemetry events will include both your custom metadata and `request_id`.

## QueueStateObserver Behaviour

For more control than telemetry, implement the `Tinkex.QueueStateObserver` behaviour to receive direct callbacks on queue state transitions. This is useful for backpressure tracking or adaptive request scheduling.

**Behaviour definition:**

```elixir
@callback on_queue_state_change(QueueState.t()) :: any()
```

**Example observer:**

```elixir
defmodule MyApp.QueueObserver do
  @behaviour Tinkex.QueueStateObserver
  require Logger

  @impl true
  def on_queue_state_change(queue_state) do
    case queue_state do
      :paused_rate_limit ->
        Logger.warning("Rate limited, backing off new requests")
        MyApp.RequestScheduler.pause()

      :paused_capacity ->
        Logger.warning("Capacity exhausted, waiting for GPU slots")
        MyApp.RequestScheduler.pause()

      :active ->
        Logger.info("Queue active again, resuming requests")
        MyApp.RequestScheduler.resume()

      _ ->
        :ok
    end
  end
end
```

**Using the observer:**

```elixir
task = Future.poll("req-abc123",
  config: config,
  queue_state_observer: MyApp.QueueObserver
)

Future.await(task, 30_000)
```

The observer receives callbacks alongside telemetry events. If the callback crashes, a warning is logged but polling continues.

**Internal usage:**

`SamplingClient` and `TrainingClient` can accept a `:queue_state_observer` option and forward it to `Future.poll/2`. This allows downstream applications to react to queue state changes without modifying client code.

## Timeout Handling

Tinkex provides two levels of timeout control for fine-grained deadline management:

### Poll Timeout

The `:timeout` option in `Future.poll/2` controls the overall polling deadline — how long the polling loop will run before giving up. When exceeded, the task returns `{:error, %Tinkex.Error{type: :api_timeout}}`.

```elixir
# Poll for max 60 seconds
task = Future.poll("req-abc123", config: config, timeout: 60_000)

# If polling exceeds 60s, you get an error
case Future.await(task, :infinity) do
  {:error, %Tinkex.Error{type: :api_timeout, message: msg}} ->
    IO.puts("Poll timeout: #{msg}")
end
```

**Default:** `:infinity` (poll forever)

### Await Timeout

The timeout argument to `Future.await/2` controls how long the caller is willing to wait on the task process. This is independent from the polling timeout and useful for request prioritization.

```elixir
task = Future.poll("req-abc123", config: config)

# Caller waits max 10 seconds
case Future.await(task, 10_000) do
  {:error, %Tinkex.Error{type: :api_timeout}} ->
    IO.puts("Caller gave up after 10s")
end
```

When the await timeout is exceeded, the task is killed with `:brutal_kill` and the caller receives `{:error, %Tinkex.Error{type: :api_timeout}}`.

**Default:** `:infinity` (wait forever)

### HTTP Timeout

The `:http_timeout` option controls the timeout for each individual HTTP request to `retrieve_future`. Defaults to `config.timeout` (typically 60 seconds).

```elixir
task = Future.poll("req-abc123",
  config: config,
  http_timeout: 5_000  # Each HTTP call times out after 5s
)
```

### Combining Timeouts

For production workloads, set all three to enforce strict SLAs:

```elixir
task = Future.poll("req-abc123",
  config: config,
  timeout: 120_000,      # Poll for max 2 minutes
  http_timeout: 10_000   # Each HTTP request times out after 10s
)

case Future.await(task, 150_000) do  # Caller waits max 2.5 minutes
  {:ok, result} -> handle_success(result)
  {:error, error} -> handle_timeout(error)
end
```

## Error Handling

`Future.poll/2` categorizes errors and applies appropriate retry logic:

### User Errors (fail immediately)

When the server returns `%FutureFailedResponse{}` with `category: "user"`, the polling loop fails immediately without retrying. This indicates a permanent error like invalid input.

```elixir
task = Future.poll("req-bad-input", config: config)

case Future.await(task, 30_000) do
  {:error, %Tinkex.Error{type: :request_failed, category: :user, message: msg}} ->
    IO.puts("User error: #{msg}")
    # Don't retry — fix the input and resubmit
end
```

### Server Errors (retry until timeout)

When `category` is `"server"` or `"provider"`, the polling loop retries with exponential backoff until the poll timeout is exceeded. The last error encountered is returned.

```elixir
task = Future.poll("req-flaky", config: config, timeout: 30_000)

case Future.await(task, :infinity) do
  {:error, %Tinkex.Error{type: :request_failed, category: :server, message: msg}} ->
    IO.puts("Server error after retries: #{msg}")
    # Consider exponential backoff before resubmitting
end
```

### Network Errors

HTTP-level errors (connection refused, DNS failure, etc.) are returned as `{:error, %Tinkex.Error{type: :network}}` and do not automatically retry. Handle these at the call site.

### Task Exits

If the polling task crashes or exits unexpectedly, `Future.await/2` converts the exit into `{:error, %Tinkex.Error{type: :api_timeout}}` with the exit reason in the data field.

```elixir
case Future.await(task, 30_000) do
  {:error, %Tinkex.Error{type: :api_timeout, data: %{exit_reason: reason}}} ->
    IO.puts("Task crashed: #{Exception.format_exit(reason)}")
end
```

## Best Practices

### 1. Always Use Futures for Concurrent Operations

Don't block on each request sequentially — start multiple polls and await them in parallel:

```elixir
# Bad: sequential awaits
results =
  Enum.map(request_ids, fn id ->
    task = Future.poll(id, config: config)
    Future.await(task, 30_000)
  end)

# Good: parallel awaits
tasks = Enum.map(request_ids, &Future.poll(&1, config: config))
results = Future.await_many(tasks, 30_000)
```

### 2. Set Explicit Timeouts in Production

Default `:infinity` timeouts are fine for development but can cause resource leaks in production. Always set explicit deadlines:

```elixir
task = Future.poll(request_id,
  config: config,
  timeout: Application.get_env(:my_app, :poll_timeout, 120_000),
  http_timeout: Application.get_env(:my_app, :http_timeout, 10_000)
)

Future.await(task, Application.get_env(:my_app, :await_timeout, 150_000))
```

### 3. Monitor Queue States for Capacity Planning

Use telemetry or custom observers to track `:paused_capacity` events. Frequent capacity pauses indicate you need more GPU slots or should reduce request rate:

```elixir
:telemetry.attach(
  "capacity-alerter",
  [:tinkex, :queue, :state_change],
  fn _event, _measurements, %{queue_state: :paused_capacity}, _config ->
    MyApp.Metrics.increment("tinkex.capacity_pause")
    # Alert if pauses exceed threshold
  end,
  nil
)
```

### 4. Handle Both Success and Failure

Always pattern match on both `{:ok, result}` and `{:error, error}` — network failures and server errors are common in distributed systems:

```elixir
case Future.await(task, 30_000) do
  {:ok, result} ->
    handle_success(result)

  {:error, %Tinkex.Error{type: :request_failed, category: :user} = error} ->
    handle_user_error(error)

  {:error, %Tinkex.Error{} = error} ->
    handle_transient_error(error)
end
```

### 5. Use Task Supervision for Long-Lived Polls

If you need to poll for minutes or hours, supervise the task to ensure it doesn't leak on process crashes:

```elixir
{:ok, task_supervisor} = Task.Supervisor.start_link()

task =
  Task.Supervisor.async_nolink(task_supervisor, fn ->
    poll_task = Future.poll(request_id, config: config, timeout: 3_600_000)
    Future.await(poll_task, :infinity)
  end)

# Task is supervised — if the parent crashes, cleanup happens automatically
```

### 6. Test with Custom Sleep Functions

Inject a no-op sleep function in tests to avoid actual delays:

```elixir
# In test
sleep_fun = fn _ms -> :ok end
task = Future.poll(request_id, config: config, sleep_fun: sleep_fun)

# Polling completes instantly without sleeping
```

## Complete Example

Here's a full example demonstrating futures, async operations, queue state monitoring, and error handling:

```elixir
defmodule MyApp.AsyncSampling do
  alias Tinkex.{ServiceClient, SamplingClient, Future, Config}
  require Logger

  defmodule QueueMonitor do
    @behaviour Tinkex.QueueStateObserver

    @impl true
    def on_queue_state_change(queue_state) do
      Logger.metadata(tinker_queue_state: queue_state)

      case queue_state do
        :paused_rate_limit ->
          Logger.warning("Rate limited — consider reducing request rate")
        :paused_capacity ->
          Logger.warning("Capacity exhausted — GPU slots full")
        :active ->
          Logger.info("Queue active")
        _ ->
          :ok
      end
    end
  end

  def run_concurrent_samples(prompts, opts \\ []) do
    config = Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))

    {:ok, service} = ServiceClient.start_link(config: config)
    {:ok, sampler} =
      ServiceClient.create_sampling_client(service,
        base_model: "meta-llama/Llama-3.1-8B"
      )

    # Attach telemetry
    :telemetry.attach(
      "queue-logger",
      [:tinkex, :queue, :state_change],
      &log_queue_event/4,
      nil
    )

    try do
      # Start all samples concurrently
      tasks =
        Enum.map(prompts, fn prompt ->
          {:ok, model_input} =
            Tinkex.Types.ModelInput.from_text(prompt,
              model_name: "meta-llama/Llama-3.1-8B"
            )

          params = %Tinkex.Types.SamplingParams{max_tokens: 64}

          # Returns Task.t() immediately
          {:ok, task} =
            SamplingClient.sample(sampler, model_input, params,
              num_samples: 1,
              queue_state_observer: QueueMonitor,
              timeout: Keyword.get(opts, :timeout, 120_000),
              await_timeout: Keyword.get(opts, :await_timeout, 150_000)
            )

          task
        end)

      # Await all in parallel
      results = Task.await_many(tasks, Keyword.get(opts, :await_timeout, 150_000))

      # Process results
      Enum.zip(prompts, results)
      |> Enum.map(fn {prompt, result} ->
        case result do
          {:ok, response} ->
            text = hd(response.sequences).tokens
            Logger.info("Prompt: #{prompt}\nResponse: #{text}")
            {:ok, text}

          {:error, error} ->
            Logger.error("Failed: #{prompt}\nError: #{error.message}")
            {:error, error}
        end
      end)
    after
      :telemetry.detach("queue-logger")
      GenServer.stop(sampler)
      GenServer.stop(service)
    end
  end

  defp log_queue_event(_event, _measurements, metadata, _config) do
    Logger.info("Queue state changed",
      request_id: metadata.request_id,
      queue_state: metadata.queue_state
    )
  end
end

# Run it
prompts = [
  "Explain async programming in Elixir",
  "What are the benefits of OTP?",
  "How does Task.async work?"
]

MyApp.AsyncSampling.run_concurrent_samples(prompts,
  timeout: 60_000,
  await_timeout: 90_000
)
```

## What to Read Next

- API overview: `docs/guides/api_reference.md`
- Training loop patterns: `docs/guides/training_loop.md`
- Troubleshooting timeout issues: `docs/guides/troubleshooting.md`
- Getting started with the SDK: `docs/guides/getting_started.md`
