# Async Model and Futures Implementation

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202, 300-302, 400+. See response documents for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- **Training requests**: Clarified that requests are sent **sequentially** (one at a time), but polling is concurrent
- **Task patterns**: Emphasized Elixir's native concurrency advantages over Python's thread-based approach

**Key Corrections (Round 2 - Critiques 200-202):**
- **Race condition fixed**: GenServer must block during send phase, not spawn Task immediately
- **Sequencing guarantee**: All training operations share same `request_id_counter`
- **No parallel sends**: Requests sent synchronously inside `handle_call`, polling async

**Key Corrections (Round 3 - Critiques 300-302):**
- **Task error handling**: Added try/rescue wrappers to prevent infinite hangs when Task crashes
- **API consistency**: All public client methods return Tasks (not direct GenServer.call results)

**Key Corrections (Round 4 - Critique 400+):**
- **CRITICAL Task.start safety**: ALL Task.start bodies that call GenServer.reply MUST wrap in try/rescue
- **Failure modes**: Document what happens when Task crashes without proper error handling
- **API pattern**: Emphasize Task.t({:ok, ...} | {:error, ...}) return type consistency

**Key Corrections (Round 5 - Final):**
- **API consistency verified**: All public client methods consistently return Task.t({:ok, ...} | {:error, ...})
- **Blocking behavior documented**: TrainingClient handle_call blocking is a conscious tradeoff for request ordering
- No changes required - document already aligned with Round 5 recommendations

**Key Corrections (Round 9 - Final Implementation Gaps):**
- **Metric reduction**: Implemented `Tinkex.MetricsReduction` module with suffix-based reduction strategies (`:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`) matching Python's `chunked_fwdbwd_helpers._metrics_reduction` - prevents corruption of summed/extrema metrics
- **Queue state backpressure**: Added `TryAgainResponse` and `QueueState` handling in `Future.poll/2` for graceful degradation (`:paused_rate_limit`, `:paused_capacity`) before hard 429s
- **QueueStateObserver behaviour**: Added optional observer pattern for TrainingClient/SamplingClient to react to queue-level signals
- **Telemetry integration**: Queue state changes emit `:tinkex.queue.state_change` events

## Overview

The Tinker SDK implements a sophisticated futures-based async model that allows synchronous-looking code to perform async operations. This is one of the most complex parts of the SDK to port.

## Python Implementation

### 1. Future Types Hierarchy

```python
# Public interface
class APIFuture[T]:
    """Client-side future that auto-polls server for results"""

    def result(self, timeout: float | None = None) -> T:
        """Blocking call - waits for result"""
        ...

    async def result_async(self, timeout: float | None = None) -> T:
        """Async version"""
        ...

# Internal implementation
class _APIFuture[T](APIFuture[T]):
    def __init__(
        self,
        model_cls: Type[T],
        holder: InternalClientHolder,
        untyped_future: types.UntypedAPIFuture,  # Contains request_id
        request_start_time: float,
        request_type: str,
    ):
        self.untyped_future = untyped_future  # {request_id: "uuid"}
        self._cached_result = _UNCOMPUTED

        # Start async polling in background
        self._future = holder.run_coroutine_threadsafe(self._result_async())

    async def _result_async(self, timeout: float | None = None) -> T:
        """Poll server until result is ready"""
        iteration = 0
        while True:
            iteration += 1

            # Call /api/v1/future/retrieve with request_id
            response = await client.futures.retrieve(
                request_id=self.request_id
            )

            if response.status == "completed":
                # Parse and validate result
                result = validate_type(self.model_cls, response.result)
                self._cached_result = result
                return result

            elif response.status == "failed":
                raise RequestFailedError(response.error)

            elif response.status == "pending":
                # Wait and retry
                await asyncio.sleep(calculate_backoff(iteration))
                continue
```

### 2. Server-Side Future Flow

```
Client                                          Server
  |                                              |
  |-- POST /api/v1/forward_backward ----------->|
  |                                              | (queues request)
  |<-- 200 {request_id: "abc123"} --------------|
  |                                              |
  |-- POST /api/v1/future/retrieve ------------>|
  |    {request_id: "abc123"}                    | (checking...)
  |<-- 200 {status: "pending"} -----------------|
  |                                              |
  | (wait 1 second)                              |
  |                                              |
  |-- POST /api/v1/future/retrieve ------------>|
  |    {request_id: "abc123"}                    | (still processing...)
  |<-- 200 {status: "pending"} -----------------|
  |                                              |
  | (wait 2 seconds)                             |
  |                                              |
  |-- POST /api/v1/future/retrieve ------------>|
  |    {request_id: "abc123"}                    | (done!)
  |<-- 200 {status: "completed", --------------|
  |         result: {...}} --------------------|
```

### 3. Combined Futures

For chunked requests, results are combined:

```python
class _CombinedAPIFuture[T](APIFuture[T]):
    """Combines multiple futures into one"""

    def __init__(
        self,
        futures: List[APIFuture[U]],
        combiner: Callable[[List[U]], T],
        holder: InternalClientHolder,
    ):
        self.futures = futures
        self.combiner = combiner

        # Start async combination
        self._future = holder.run_coroutine_threadsafe(self._result_async())

    async def _result_async(self) -> T:
        # Wait for all futures
        results = []
        for future in self.futures:
            result = await future.result_async()
            results.append(result)

        # Combine results
        return self.combiner(results)
```

Example combiner:

```python
def combine_fwd_bwd_output_results(
    results: List[types.ForwardBackwardOutput]
) -> types.ForwardBackwardOutput:
    """Combine results from multiple chunks"""
    return types.ForwardBackwardOutput(
        loss=sum(r.loss for r in results) / len(results),  # Average loss
        loss_fn_outputs=[out for r in results for out in r.loss_fn_outputs],  # Flatten
        metrics=merge_metrics([r.metrics for r in results]),  # Merge metrics
    )
```

### 4. Threading Model

Python SDK uses a **background thread with dedicated event loop**:

```python
class InternalClientHolderThreadSingleton:
    """Global singleton for background async thread"""

    def __init__(self):
        self._loop = None
        self._thread = None

    def _ensure_started(self):
        if not self._started:
            self._loop = asyncio.new_event_loop()
            self._thread = threading.Thread(
                target=lambda: self._loop.run_forever(),
                daemon=True
            )
            self._thread.start()

    def run_coroutine_threadsafe(self, coro):
        """Submit coroutine to background loop"""
        return asyncio.run_coroutine_threadsafe(coro, self._loop)
```

**Usage:**
```python
# Synchronous client code
def forward_backward(self, data, loss_fn):
    # This function is synchronous, but launches async operation

    async def _forward_backward_async():
        # This runs in background thread's event loop
        response = await client.training.forward_backward(...)
        return await _APIFuture(...).result_async()

    # Submit to background loop, return future
    return self.holder.run_coroutine_threadsafe(_forward_backward_async())
```

## Elixir Port Strategy

Elixir's concurrency model makes this **significantly simpler**!

### 1. Use Elixir Tasks

Tasks are the natural equivalent of futures:

```elixir
defmodule Tinkex.Future do
  @moduledoc """
  Client-side future that polls server for results.
  Built on Elixir Task.
  """

  @type t(result) :: Task.t(result)

  @doc """
  Create a future that polls for a server-side result.

  Returns a Task that will eventually resolve to the result.
  """
  @spec poll(String.t(), keyword()) :: t(any())
  def poll(request_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout)
    pool = Keyword.get(opts, :pool, Tinkex.HTTP.Pool)

    Task.async(fn ->
      poll_until_ready(request_id, pool, timeout)
    end)
  end

  @doc """
  Wait for future to complete and return result.
  """
  @spec await(t(result), timeout()) :: result when result: any()
  def await(task, timeout \\ :infinity) do
    Task.await(task, timeout)
  end

  ## Private

  defp poll_until_ready(request_id, pool, timeout) do
    start_time = System.monotonic_time(:millisecond)
    iteration = 0

    poll_loop(request_id, pool, timeout, start_time, iteration)
  end

  defp poll_loop(request_id, pool, timeout, start_time, iteration) do
    # Check timeout
    if timeout do
      elapsed = System.monotonic_time(:millisecond) - start_time
      if elapsed > timeout do
        raise TimeoutError, "Timeout after #{elapsed}ms waiting for #{request_id}"
      end
    end

    # Poll server
    headers = [
      {"X-Tinker-Request-Iteration", to_string(iteration)},
      {"X-Tinker-Request-Type", "FutureRetrieve"}
    ]

    request = %Tinkex.Types.FutureRetrieveRequest{request_id: request_id}

    case Tinkex.API.Futures.retrieve(request, pool, headers: headers) do
      {:ok, %{status: "completed", result: result}} ->
        # Success!
        {:ok, result}

      {:ok, %{status: "failed", error: error}} ->
        {:error, error}

      {:ok, %{status: "pending"}} ->
        # Wait and retry with exponential backoff
        backoff = calculate_backoff(iteration)
        Process.sleep(backoff)
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      # ⚠️ CRITICAL (Round 9): Handle TryAgainResponse with queue_state
      # Python SDK responds to queue-level signals (paused_rate_limit, paused_capacity)
      # before hard 429s occur. We must respect these to avoid unnecessary load.
      {:ok, %{status: "try_again", queue_state: queue_state}} ->
        # Notify observers (for logging/monitoring)
        notify_queue_state_change(queue_state)

        # Back off based on queue state
        backoff = case queue_state do
          "paused_rate_limit" -> 1000  # 1 second
          "paused_capacity"   -> 1000  # 1 second
          _                   -> calculate_backoff(iteration)
        end

        Process.sleep(backoff)
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      {:error, %{status: 408}} ->
        # Timeout, retry immediately
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      {:error, error} when is_retryable(error) ->
        # Transient error, retry with backoff
        backoff = calculate_backoff(iteration)
        Process.sleep(backoff)
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      {:error, error} ->
        # Fatal error
        {:error, error}
    end
  end

  defp calculate_backoff(iteration) do
    # Exponential backoff: 1s, 2s, 4s, 8s, max 30s
    min(1000 * :math.pow(2, iteration), 30_000)
    |> round()
  end

  defp is_retryable(%{status: status}) when status >= 500, do: true
  defp is_retryable(_), do: false

  # ⚠️ NEW (Round 9): Queue state notification
  defp notify_queue_state_change(queue_state) do
    # Emit telemetry event for queue state changes
    :telemetry.execute(
      [:tinkex, :queue, :state_change],
      %{timestamp: System.system_time(:millisecond)},
      %{queue_state: queue_state}
    )

    # Log for visibility
    case queue_state do
      "paused_rate_limit" ->
        require Logger
        Logger.warning("Queue paused due to rate limit")

      "paused_capacity" ->
        require Logger
        Logger.warning("Queue paused due to capacity constraints")

      _ ->
        :ok
    end
  end
end
```

### Queue State Handling ⚠️ NEW (Round 9)

**Critical Addition:** The Python SDK includes a `QueueState` enum and `TryAgainResponse` mechanism that signals queue-level backpressure *before* hard 429 rate limits occur.

**Why This Matters:**
- Server sends `TryAgainResponse` with `queue_state` when worker queue is paused
- Clients should respect these signals to avoid unnecessary load
- Enables graceful degradation before hitting hard rate limits

**Queue State Types:**

```elixir
# In types/queue_state.ex
defmodule Tinkex.Types.QueueState do
  @type t :: :active | :paused_rate_limit | :paused_capacity | :unknown

  def parse("active"), do: :active
  def parse("paused_rate_limit"), do: :paused_rate_limit
  def parse("paused_capacity"), do: :paused_capacity
  def parse(_), do: :unknown
end
```

**TryAgainResponse Type:**

```elixir
# In types/try_again_response.ex
defmodule Tinkex.Types.TryAgainResponse do
  @derive Jason.Encoder
  defstruct [:status, :queue_state, :retry_after_ms]

  @type t :: %__MODULE__{
    status: String.t(),           # "try_again"
    queue_state: String.t(),      # "active" | "paused_rate_limit" | "paused_capacity"
    retry_after_ms: integer() | nil
  }
end
```

**Integration Points:**

1. **Future.poll/2** - Detects `TryAgainResponse` and backs off accordingly (implemented above)
2. **TrainingClient/SamplingClient** - Can implement optional `QueueStateObserver` behaviour for custom handling
3. **Telemetry** - Emits `:tinkex.queue.state_change` events for monitoring

**Optional QueueStateObserver Behaviour:**

```elixir
defmodule Tinkex.QueueStateObserver do
  @moduledoc """
  Behaviour for observing queue state changes.

  TrainingClient and SamplingClient can implement this to react
  to queue-level backpressure signals from the server.
  """

  @callback on_queue_state_change(Tinkex.Types.QueueState.t()) :: any()
end
```

**Example Implementation in TrainingClient:**

```elixir
defmodule Tinkex.TrainingClient do
  @behaviour Tinkex.QueueStateObserver

  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state) do
    require Logger

    case queue_state do
      :paused_rate_limit ->
        Logger.warning("Training paused: rate limit hit for model #{inspect(self())}")

      :paused_capacity ->
        Logger.warning("Training paused: capacity constraints for model #{inspect(self())}")

      :active ->
        Logger.info("Training queue resumed")

      :unknown ->
        :ok
    end
  end
end
```

### 2. Combined Futures

```elixir
defmodule Tinkex.Future.Combiner do
  @moduledoc """
  Utilities for combining multiple futures.
  """

  @doc """
  Await multiple futures and combine their results.
  """
  def await_and_combine(futures, combiner_fn, timeout \\ :infinity) do
    Task.async(fn ->
      results = Task.await_many(futures, timeout)
      combiner_fn.(results)
    end)
  end
end
```

**Usage:**
```elixir
# ⚠️ UPDATED (Round 3): Public API returns Task for consistency
def forward_backward(client, data, loss_fn, opts \\ []) do
  Task.async(fn ->
    GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
  end)
end

# In GenServer handle_call ⚠️ CORRECTED (Round 2 + 3)
def handle_call({:forward_backward, data, loss_fn, _opts}, from, state) do
  # Chunk data
  chunks = chunk_data(data)

  # Allocate request IDs upfront
  {request_ids, new_counter} = allocate_request_ids(length(chunks), state.request_id_counter)

  # ⚠️ CRITICAL: Send ALL requests SYNCHRONOUSLY (blocks GenServer)
  untyped_futures = Enum.zip(request_ids, chunks)
  |> Enum.map(fn {req_id, chunk} ->
    send_forward_backward_chunk(chunk, loss_fn, req_id, state)
  end)

  # ⚠️ CRITICAL (Round 4): Spawn background task with mandatory error handling
  # Without try/rescue: If polling task crashes → GenServer.reply never called → caller hangs FOREVER
  Task.start(fn ->
    result = try do
      # Poll all futures concurrently
      polling_tasks = Enum.map(untyped_futures, fn future ->
        Tinkex.Future.poll(future.request_id, state.http_pool)
      end)

      results = Task.await_many(polling_tasks, :infinity)
      combined = combine_forward_backward_results(results)
      {:ok, combined}
    rescue
      e ->
        # ALWAYS reply, even on failure, to prevent infinite hang
        {:error, %Tinkex.Error{
          message: "Polling failed: #{Exception.message(e)}",
          type: :request_failed,
          data: %{exception: e, stacktrace: __STACKTRACE__}
        }}
    end

    # ALWAYS call GenServer.reply, whether success or failure
    GenServer.reply(from, result)
  end)

  new_state = %{state | request_id_counter: new_counter}
  {:noreply, new_state}
end

defp send_forward_backward_chunk(chunk, loss_fn, req_id, state) do
  request = %Tinkex.Types.ForwardBackwardRequest{
    forward_backward_input: %{data: chunk, loss_fn: loss_fn},
    model_id: state.model_id,
    seq_id: req_id
  }

  # SYNCHRONOUS send (blocks until sent to server)
  {:ok, untyped_future} = Tinkex.API.Training.forward_backward(
    request,
    state.http_pool
  )

  untyped_future  # Return future for polling
end

# ═══════════════════════════════════════════════════════════════════════
# ⚠️ CRITICAL (Round 9): Metrics Reduction Module
# ═══════════════════════════════════════════════════════════════════════
#
# Python SDK uses chunked_fwdbwd_helpers._metrics_reduction with suffix-based
# reduction strategies. Using naive average corrupts metrics that must be
# summed (tokens_processed:sum), tracked by extrema (max_grad_norm:max), etc.
#
# This module mirrors Python's REDUCE_MAP logic:
# - Keys ending ":mean" → weighted mean
# - Keys ending ":sum" → sum
# - Keys ending ":min" → min
# - Keys ending ":max" → max
# - Keys ending ":slack" → special slack reduction
# - Keys ending ":unique" → identity/unique behavior
# ═══════════════════════════════════════════════════════════════════════

defmodule Tinkex.MetricsReduction do
  @moduledoc """
  Metric reduction for chunked forward/backward results.

  Mirrors Python SDK's chunked_fwdbwd_helpers._metrics_reduction logic.
  Reduces metrics based on suffix after last ':' in metric name.
  """

  @type metrics :: %{String.t() => float()}
  @type result :: %{metrics: metrics(), loss_fn_outputs: list()}

  @doc """
  Reduce metrics from multiple chunk results using suffix-based strategies.

  Weights are computed based on number of loss_fn_outputs per result.
  """
  @spec reduce([result()]) :: metrics()
  def reduce(results) do
    # 1. Compute weights based on number of loss_fn_outputs
    weights = Enum.map(results, fn r -> length(r.loss_fn_outputs) end)
    total_weight = Enum.sum(weights)

    # 2. Collect all unique metric keys across results
    keys =
      results
      |> Enum.flat_map(fn r -> Map.keys(r.metrics) end)
      |> Enum.uniq()

    # 3. Reduce each metric using suffix-based strategy
    Enum.into(keys, %{}, fn key ->
      values = Enum.map(results, &Map.get(&1.metrics, key, 0.0))

      reducer =
        key
        |> String.split(":")
        |> List.last()
        |> reduction_fun()

      {key, reducer.(values, weights, total_weight)}
    end)
  end

  # Dispatch based on suffix (matches Python REDUCE_MAP)
  defp reduction_fun("sum"), do: &reduce_sum/3
  defp reduction_fun("min"), do: &reduce_min/3
  defp reduction_fun("max"), do: &reduce_max/3
  defp reduction_fun("mean"), do: &reduce_mean/3
  defp reduction_fun("slack"), do: &reduce_slack/3
  defp reduction_fun("unique"), do: &reduce_unique/3

  # Default: weighted mean (matches Python's fallback behavior)
  defp reduction_fun(_), do: &reduce_mean/3

  # Sum reduction
  defp reduce_sum(values, _weights, _total_weight) do
    Enum.sum(values)
  end

  # Min reduction
  defp reduce_min(values, _weights, _total_weight) do
    Enum.min(values)
  end

  # Max reduction
  defp reduce_max(values, _weights, _total_weight) do
    Enum.max(values)
  end

  # Weighted mean reduction
  defp reduce_mean(values, weights, total_weight) do
    weighted_sum =
      values
      |> Enum.zip(weights)
      |> Enum.map(fn {v, w} -> v * w end)
      |> Enum.sum()

    # Avoid division by zero
    if total_weight > 0 do
      weighted_sum / total_weight
    else
      0.0
    end
  end

  # Slack reduction (matches Python: max - mean)
  # Python's `_slack` computes np.max(xs) - np.average(xs, weights=weights)
  defp reduce_slack(values, weights, total_weight) do
    max_val = Enum.max(values)
    mean_val = reduce_mean(values, weights, total_weight)
    max_val - mean_val
  end

  # Unique reduction (identity-ish behavior for unique values)
  # For v1.0, return first value. Python expands key space; we simplify.
  defp reduce_unique(values, _weights, _total_weight) do
    List.first(values) || 0.0
  end
end

defp combine_forward_backward_results(results) do
  # Flatten outputs
  all_outputs = Enum.flat_map(results, & &1.loss_fn_outputs)

  # ⚠️ CRITICAL (Round 9): Use suffix-based metric reduction to match Python SDK
  # Python uses chunked_fwdbwd_helpers._metrics_reduction with weighted reduction
  # based on metric name suffix (:mean, :sum, :min, :max, :slack, :unique)
  merged_metrics = Tinkex.MetricsReduction.reduce(results)

  # Use loss_fn_output_type from first result (should be same for all)
  loss_fn_output_type = hd(results).loss_fn_output_type

  %Tinkex.Types.ForwardBackwardOutput{
    loss_fn_output_type: loss_fn_output_type,
    loss_fn_outputs: all_outputs,
    metrics: merged_metrics  # loss is metrics["loss"]
  }
end
```

### 3. No Background Thread Needed!

Unlike Python, Elixir doesn't need a background thread:

- **Python**: Main thread is blocking, needs separate thread for async I/O
- **Elixir**: Lightweight processes (actors) handle concurrency natively

**Python approach:**
```python
# Blocking main thread, async in background
future = training_client.forward_backward(data, "cross_entropy")
result = future.result()  # Blocks until complete
```

**Elixir approach:**
```elixir
# Non-blocking, concurrent by default
task = TrainingClient.forward_backward(client, data, :cross_entropy)
result = Task.await(task)  # Blocks THIS process, others continue
```

### 4. Simplified API Surface

The Elixir API can be cleaner:

**Python** (dual API):
```python
# Sync version
result = training_client.forward_backward(data, "cross_entropy").result()

# Async version
result = await training_client.forward_backward_async(data, "cross_entropy")
```

**Elixir** (single API):
```elixir
# Returns Task - caller decides sync or async
task = TrainingClient.forward_backward(client, data, :cross_entropy)

# Caller can use it synchronously:
result = Task.await(task)

# Or asynchronously in an async function:
result = await task  # (hypothetical with async/await macro)
# Or more idiomatically:
receive do
  {^task_ref, result} -> result
end
```

## Comparison Summary

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Concurrency Primitive** | Thread + asyncio.Future | Process + Task |
| **Blocking Model** | Main thread blocks, bg thread async | Any process can block |
| **API Complexity** | Dual (sync + async versions) | Single (Task-based) |
| **Pooling** | Complex server-side future polling | Simple Task.await |
| **Combining** | Custom _CombinedAPIFuture | Task.await_many + combiner |
| **Error Handling** | Try/catch in async/sync contexts | Standard {:ok, result} tuples |

## Recommended Implementation

```elixir
defmodule Tinkex.TrainingClient do
  @moduledoc """
  Client for ML model training operations.

  All methods return `Task.t()` which can be awaited:

      task = TrainingClient.forward_backward(client, data, :cross_entropy)
      {:ok, result} = Task.await(task)
  """

  @type t :: pid()

  # All public APIs return Task
  @spec forward_backward(t(), [Datum.t()], atom(), keyword()) ::
    Task.t({:ok, ForwardBackwardOutput.t()} | {:error, term()})
  def forward_backward(client, data, loss_fn, opts \\ []) do
    Task.async(fn ->
      GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
    end)
  end

  @spec optim_step(t(), AdamParams.t()) ::
    Task.t({:ok, OptimStepResponse.t()} | {:error, term()})
  def optim_step(client, adam_params) do
    Task.async(fn ->
      GenServer.call(client, {:optim_step, adam_params}, :infinity)
    end)
  end
end
```

**Usage:**
```elixir
# Create clients
{:ok, service} = Tinkex.ServiceClient.start_link()
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(
  service,
  base_model: "Qwen/Qwen2.5-7B"
)

# Submit forward-backward (returns Task)
fwd_task = Tinkex.TrainingClient.forward_backward(training, data, :cross_entropy)

# Submit optimizer step (returns Task)
opt_task = Tinkex.TrainingClient.optim_step(training, adam_params)

# Can await sequentially
{:ok, fwd_result} = Task.await(fwd_task)
{:ok, opt_result} = Task.await(opt_task)

# Or concurrently
[{:ok, fwd_result}, {:ok, opt_result}] = Task.await_many([fwd_task, opt_task])
```

## Next Steps

See `04_http_layer.md` for HTTP/2 client implementation details.
