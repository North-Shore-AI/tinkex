# Telemetry and Observability

**⚠️ NOTE:** This document remains largely unchanged from Round 3. For changes related to error categories and telemetry pool configuration, see 04_http_layer.md and 05_error_handling.md.

## Python Telemetry Implementation

The Tinker SDK includes built-in telemetry for tracking operations, errors, and performance metrics.

### Telemetry Architecture

```python
# lib/telemetry.py
class Telemetry:
    """Collects and sends telemetry data to server"""

    def __init__(self, session_id: str, holder: InternalClientHolder):
        self.session_id = session_id
        self.holder = holder
        self._events: list[TelemetryEvent] = []
        self._lock = threading.Lock()

    def log(
        self,
        event_name: str,
        *,
        event_data: dict[str, Any] | None = None,
        severity: str = "INFO",
    ) -> None:
        """Log a telemetry event"""
        event = TelemetryEvent(
            session_id=self.session_id,
            event_name=event_name,
            event_data=event_data or {},
            severity=severity,
            timestamp=time.time(),
        )

        with self._lock:
            self._events.append(event)

        # Send to server asynchronously
        self._maybe_flush()

    def _maybe_flush(self) -> None:
        """Flush events to server if threshold reached"""
        with self._lock:
            if len(self._events) >= FLUSH_THRESHOLD:
                events_to_send = self._events.copy()
                self._events.clear()

        if events_to_send:
            asyncio.run_coroutine_threadsafe(
                self._send_events(events_to_send),
                self.holder.get_loop()
            )

    async def _send_events(self, events: list[TelemetryEvent]) -> None:
        """Send events to telemetry endpoint"""
        try:
            with self.holder.aclient(ClientConnectionPoolType.SESSION) as client:
                await client.telemetry.send(events=events)
        except Exception as e:
            logger.debug(f"Failed to send telemetry: {e}")
```

### Captured Events

The SDK logs various events:

#### Request Lifecycle

```python
# Request start
telemetry.log(
    "request.start",
    event_data={
        "request_type": "ForwardBackward",
        "model_id": model_id,
        "data_size": len(data),
    }
)

# Request complete
telemetry.log(
    "request.complete",
    event_data={
        "request_type": "ForwardBackward",
        "duration_ms": duration,
        "status": "success",
    }
)

# Request error
telemetry.log(
    "request.error",
    event_data={
        "request_type": "ForwardBackward",
        "error": str(error),
        "is_user_error": is_user_error(error),
    },
    severity="ERROR"
)
```

#### Future Polling

```python
telemetry.log(
    "APIFuture.result_async.api_status_error",
    event_data={
        "request_id": request_id,
        "request_type": request_type,
        "status_code": e.status_code,
        "should_retry": should_retry,
        "iteration": iteration,
        "elapsed_time": elapsed,
    },
    severity="WARNING" if should_retry else "ERROR"
)
```

#### Queue State Changes

```python
def on_queue_state_change(self, queue_state: QueueState):
    if queue_state == QueueState.PAUSED_RATE_LIMIT:
        logger.warning(f"Training paused: rate limit hit for {self.model_id}")
        telemetry.log(
            "queue.paused",
            event_data={
                "model_id": self.model_id,
                "reason": "rate_limit",
            }
        )
```

### Exception Capture Decorator

```python
def capture_exceptions(fatal: bool = False):
    """Decorator to capture exceptions in telemetry"""

    def decorator(fn):
        @wraps(fn)
        def wrapper(self, *args, **kwargs):
            try:
                return fn(self, *args, **kwargs)
            except Exception as e:
                if telemetry := self.get_telemetry():
                    telemetry.log(
                        f"exception.{fn.__name__}",
                        event_data={
                            "exception_type": type(e).__name__,
                            "exception_message": str(e),
                            "traceback": traceback.format_exc(),
                        },
                        severity="ERROR"
                    )

                if fatal or not is_user_error(e):
                    # Re-raise non-user errors
                    raise

        return wrapper
    return decorator

# Usage
class TrainingClient:
    @capture_exceptions(fatal=True)
    def forward_backward(self, data, loss_fn):
        ...
```

### User Error Detection

```python
def is_user_error(error: Exception) -> bool:
    """Determine if error is user-caused (vs SDK/server issue)"""

    if isinstance(error, RequestFailedError):
        return error.error_category == RequestErrorCategory.USER_ERROR

    if isinstance(error, APIStatusError):
        # 4xx errors (except 408, 429) are user errors
        return 400 <= error.status_code < 500 and error.status_code not in (408, 429)

    if isinstance(error, (APIConnectionError, APITimeoutError)):
        return False

    # Default: assume user error
    return True
```

## Elixir Telemetry Implementation

Elixir has **first-class telemetry support** via the `:telemetry` library!

### Setup

```elixir
# mix.exs
{:telemetry, "~> 1.2"},
{:telemetry_metrics, "~> 0.6"},
{:telemetry_poller, "~> 1.0"}
```

### Event Execution

Use `:telemetry.execute/3` to emit events:

```elixir
defmodule Tinkex.API do
  def post(path, body, pool, opts) do
    start_time = System.monotonic_time()

    metadata = %{
      path: path,
      method: :post,
      pool: pool
    }

    # Emit start event
    :telemetry.execute(
      [:tinkex, :http, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result = do_post(path, body, pool, opts)

    duration = System.monotonic_time() - start_time

    # Emit stop event
    measurements = %{
      duration: duration,
      monotonic_time: System.monotonic_time()
    }

    metadata = case result do
      {:ok, _} ->
        Map.put(metadata, :status, :success)

      {:error, error} ->
        Map.merge(metadata, %{status: :error, error: error})
    end

    :telemetry.execute(
      [:tinkex, :http, :request, :stop],
      measurements,
      metadata
    )

    result
  end
end
```

### Telemetry Span

For automatic start/stop events:

```elixir
defmodule Tinkex.TrainingClient do
  def forward_backward(client, data, loss_fn, opts) do
    metadata = %{
      client: client,
      data_size: length(data),
      loss_fn: loss_fn
    }

    :telemetry.span(
      [:tinkex, :training, :forward_backward],
      metadata,
      fn ->
        result = GenServer.call(client, {:forward_backward, data, loss_fn, opts})
        {result, metadata}
      end
    )
  end
end
```

This automatically emits:
- `[:tinkex, :training, :forward_backward, :start]`
- `[:tinkex, :training, :forward_backward, :stop]` or `:exception`

### Event Handler

Attach handlers to process events:

```elixir
defmodule Tinkex.Telemetry do
  require Logger

  def setup do
    events = [
      [:tinkex, :http, :request, :start],
      [:tinkex, :http, :request, :stop],
      [:tinkex, :http, :request, :exception],

      [:tinkex, :training, :forward_backward, :start],
      [:tinkex, :training, :forward_backward, :stop],
      [:tinkex, :training, :forward_backward, :exception],

      [:tinkex, :sampling, :sample, :start],
      [:tinkex, :sampling, :sample, :stop],
      [:tinkex, :sampling, :sample, :exception],

      [:tinkex, :future, :poll, :start],
      [:tinkex, :future, :poll, :stop],
      [:tinkex, :future, :poll, :exception],

      [:tinkex, :retry],
    ]

    :telemetry.attach_many(
      "tinkex-telemetry-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:tinkex, :http, :request, :stop], measurements, metadata, _config) do
    Logger.info(
      "HTTP request completed",
      method: metadata.method,
      path: metadata.path,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond),
      status: metadata.status
    )

    # Could also send to external service (DataDog, Prometheus, etc.)
  end

  def handle_event([:tinkex, :http, :request, :exception], measurements, metadata, _config) do
    Logger.error(
      "HTTP request failed",
      method: metadata.method,
      path: metadata.path,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond),
      error: inspect(metadata.error),
      stacktrace: metadata.stacktrace
    )
  end

  def handle_event([:tinkex, :retry], measurements, metadata, _config) do
    Logger.warning(
      "Retrying request",
      attempt: measurements.attempt,
      delay_ms: measurements.delay,
      error: inspect(metadata.error)
    )
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
```

### Metrics

Define metrics for monitoring:

```elixir
defmodule Tinkex.Telemetry.Metrics do
  use Supervisor
  import Telemetry.Metrics

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # Reporter (e.g., Prometheus, StatsD)
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # HTTP request metrics
      counter("tinkex.http.request.count",
        tags: [:method, :path, :status]
      ),

      distribution("tinkex.http.request.duration",
        unit: {:native, :millisecond},
        tags: [:method, :path],
        reporter_options: [buckets: [10, 100, 500, 1000, 5000, 10000]]
      ),

      # Training metrics
      counter("tinkex.training.forward_backward.count",
        tags: [:loss_fn]
      ),

      distribution("tinkex.training.forward_backward.duration",
        unit: {:native, :millisecond},
        tags: [:loss_fn]
      ),

      # Sampling metrics
      counter("tinkex.sampling.sample.count"),

      distribution("tinkex.sampling.sample.duration",
        unit: {:native, :millisecond}
      ),

      # Future polling metrics
      counter("tinkex.future.poll.count",
        tags: [:status]
      ),

      distribution("tinkex.future.poll.iterations",
        description: "Number of polling iterations until completion"
      ),

      # Retry metrics
      counter("tinkex.retry.count",
        tags: [:error_type]
      ),

      # Process metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :dispatch_vm_metrics, []}
    ]
  end

  def dispatch_vm_metrics do
    :telemetry.execute([:vm, :memory], :erlang.memory(), %{})
    :telemetry.execute([:vm, :total_run_queue_lengths], :erlang.statistics(:total_run_queue_lengths), %{})
  end
end
```

### Server-Side Telemetry

Send events to Tinker server:

```elixir
defmodule Tinkex.Telemetry.Reporter do
  use GenServer

  @flush_threshold 100
  @flush_interval 60_000  # 1 minute

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Attach telemetry handler
    :telemetry.attach_many(
      "tinkex-server-reporter",
      telemetry_events(),
      &handle_telemetry_event/4,
      self()
    )

    # Schedule periodic flush
    schedule_flush()

    state = %{
      session_id: opts[:session_id],
      events: [],
      http_pool: opts[:http_pool]
    }

    {:ok, state}
  end

  def handle_telemetry_event(event_name, measurements, metadata, reporter_pid) do
    event = %{
      event_name: Enum.join(event_name, "."),
      measurements: measurements,
      metadata: metadata,
      timestamp: System.system_time(:millisecond)
    }

    GenServer.cast(reporter_pid, {:log_event, event})
  end

  def handle_cast({:log_event, event}, state) do
    events = [event | state.events]

    if length(events) >= @flush_threshold do
      send(self(), :flush)
      {:noreply, %{state | events: events}}
    else
      {:noreply, %{state | events: events}}
    end
  end

  def handle_info(:flush, state) do
    # Send events to server
    if state.events != [] do
      Task.start(fn ->
        send_to_server(state.events, state.session_id, state.http_pool)
      end)
    end

    schedule_flush()
    {:noreply, %{state | events: []}}
  end

  defp send_to_server(events, session_id, pool) do
    request = %{
      session_id: session_id,
      events: events
    }

    # Fire and forget
    Tinkex.API.Telemetry.send(request, pool)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp telemetry_events do
    [
      [:tinkex, :http, :request, :stop],
      [:tinkex, :http, :request, :exception],
      [:tinkex, :training, :forward_backward, :stop],
      [:tinkex, :sampling, :sample, :stop],
      [:tinkex, :future, :poll, :stop],
      [:tinkex, :retry]
    ]
  end
end
```

## Comparison Summary

| Feature | Python | Elixir |
|---------|--------|--------|
| **Telemetry Library** | Custom | Built-in `:telemetry` |
| **Event Collection** | Manual logging | Automatic via handlers |
| **Metrics** | Custom implementation | `telemetry_metrics` |
| **Integration** | Decorator-based | Function-based |
| **Reporting** | Async tasks | GenServer + Task |

Elixir's telemetry is **more idiomatic and powerful** out of the box!

## Next Steps

See `07_porting_strategy.md` for the complete implementation roadmap.
