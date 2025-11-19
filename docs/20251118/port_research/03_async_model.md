# Async Model and Futures Implementation

**⚠️ UPDATED:** This document has been corrected based on critiques 100, 101, 102. See `103_claude_sonnet_response_to_critiques.md` for details.

**Key Corrections:**
- **Training requests**: Clarified that requests are sent **sequentially** (one at a time), but polling is concurrent
- **Task patterns**: Emphasized Elixir's native concurrency advantages over Python's thread-based approach

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
# In TrainingClient

def forward_backward(client, data, loss_fn, opts) do
  GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
end

# In GenServer handle_call
def handle_call({:forward_backward, data, loss_fn, _opts}, from, state) do
  # Chunk data
  chunks = chunk_data(data)

  # Spawn process to send chunks SEQUENTIALLY, then poll CONCURRENTLY
  Task.start(fn ->
    # Enum.map executes sequentially - sends requests one at a time
    polling_tasks = Enum.map(chunks, fn chunk ->
      send_forward_backward_chunk(chunk, loss_fn, state)
    end)

    # Now poll all futures concurrently
    results = Task.await_many(polling_tasks, :infinity)
    combined = combine_forward_backward_results(results)
    GenServer.reply(from, {:ok, combined})
  end)

  {:noreply, state}
end

defp send_forward_backward_chunk(chunk, loss_fn, state) do
  request_id = state.request_id_counter

  request = %Tinkex.Types.ForwardBackwardRequest{
    forward_backward_input: %{data: chunk, loss_fn: loss_fn},
    model_id: state.model_id,
    seq_id: request_id
  }

  # Send request synchronously (blocks until sent)
  {:ok, untyped_future} = Tinkex.API.Training.forward_backward(
    request,
    state.http_pool
  )

  # Start polling asynchronously (returns Task)
  Tinkex.Future.poll(untyped_future.request_id, pool: state.http_pool)
end

defp combine_forward_backward_results(results) do
  # Average loss across chunks
  avg_loss = Enum.sum(Enum.map(results, & &1.loss)) / length(results)

  # Flatten outputs
  all_outputs = Enum.flat_map(results, & &1.loss_fn_outputs)

  # Merge metrics
  merged_metrics = Enum.reduce(results, %{}, fn result, acc ->
    Map.merge(acc, result.metrics, fn _k, v1, v2 -> (v1 + v2) / 2 end)
  end)

  %Tinkex.Types.ForwardBackwardOutput{
    loss: avg_loss,
    loss_fn_outputs: all_outputs,
    metrics: merged_metrics
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
