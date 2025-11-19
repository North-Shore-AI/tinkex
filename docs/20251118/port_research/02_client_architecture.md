# Client Architecture Analysis

## Overview

The Tinker SDK uses a hierarchical client architecture with three main client types, each backed by a shared `InternalClientHolder` for connection management.

## Client Hierarchy

```
ServiceClient (Entry Point)
    ├── TrainingClient (per model instance)
    │   └── SamplingClient (from saved weights)
    ├── SamplingClient (standalone inference)
    └── RestClient (low-level API operations)
```

## 1. ServiceClient

**Purpose**: Main entry point for SDK. Creates other client instances.

### Python Implementation

```python
class ServiceClient(TelemetryProvider):
    def __init__(self, user_metadata: dict[str, str] | None = None, **kwargs):
        # Create internal client holder
        self.holder = InternalClientHolder(
            user_metadata=user_metadata,
            **kwargs
        )
        # Session is created immediately

    def create_lora_training_client(
        self,
        base_model: str,
        rank: int = 32,
        seed: int | None = None,
        train_mlp: bool = True,
        train_attn: bool = True,
        train_unembed: bool = True,
        user_metadata: dict[str, str] | None = None,
    ) -> TrainingClient:
        # 1. Allocate model_seq_id
        # 2. Send CreateModelRequest to server
        # 3. Return TrainingClient with model_id
        ...

    def create_sampling_client(
        self,
        model_path: str | None = None,
        base_model: str | None = None,
        retry_config: RetryConfig | None = None,
    ) -> SamplingClient:
        # Create sampling session
        # Return SamplingClient
        ...

    def create_rest_client(self) -> RestClient:
        return RestClient(self.holder)
```

### Key Responsibilities
1. Session lifecycle management
2. Client instance creation
3. Resource allocation (model_seq_id, sampling_session_id)
4. Shared connection pool via `InternalClientHolder`

### Elixir Port Strategy

Use a **GenServer** for ServiceClient with supervised initialization:

```elixir
defmodule Tinkex.ServiceClient do
  use GenServer

  @type t :: pid()

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec create_lora_training_client(t(), keyword()) ::
    {:ok, Tinkex.TrainingClient.t()} | {:error, term()}
  def create_lora_training_client(service_client, opts) do
    GenServer.call(service_client, {:create_training_client, opts})
  end

  @spec create_sampling_client(t(), keyword()) ::
    {:ok, Tinkex.SamplingClient.t()} | {:error, term()}
  def create_sampling_client(service_client, opts) do
    GenServer.call(service_client, {:create_sampling_client, opts})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Initialize HTTP client pool (Finch)
    # Create session on server
    # Start heartbeat process
    with {:ok, session_id} <- create_session(opts),
         :ok <- start_heartbeat(session_id) do
      state = %{
        session_id: session_id,
        training_client_counter: 0,
        sampling_client_counter: 0,
        http_pool: Tinkex.HTTP.Pool,
        opts: opts
      }
      {:ok, state}
    end
  end

  @impl true
  def handle_call({:create_training_client, opts}, _from, state) do
    model_seq_id = state.training_client_counter

    # Send CreateModelRequest
    request = %Tinkex.Types.CreateModelRequest{
      session_id: state.session_id,
      model_seq_id: model_seq_id,
      base_model: opts[:base_model],
      lora_config: build_lora_config(opts)
    }

    case Tinkex.API.Models.create(request, state.http_pool) do
      {:ok, response} ->
        # Start supervised TrainingClient GenServer
        {:ok, pid} = Tinkex.TrainingClientSupervisor.start_child(
          model_id: response.model_id,
          model_seq_id: model_seq_id,
          http_pool: state.http_pool
        )

        new_state = %{state | training_client_counter: model_seq_id + 1}
        {:reply, {:ok, pid}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end
end
```

## 2. TrainingClient

**Purpose**: Manages model training operations for a specific model instance.

### Python Implementation

```python
class TrainingClient(TelemetryProvider, QueueStateObserver):
    def __init__(self, holder: InternalClientHolder,
                 model_seq_id: int, model_id: types.ModelID):
        self.holder = holder
        self.model_id = model_id
        self._training_client_id = model_seq_id

        # Request sequencing
        self._request_id_lock = threading.Lock()
        self._request_id_counter = 0

        # Turn-taking for sequential operations
        self._turn_counter = 0
        self._turn_waiters: dict[int, asyncio.Event] = {}

    def forward_backward(
        self,
        data: List[types.Datum],
        loss_fn: types.LossFnType,
        loss_fn_config: Dict[str, float] | None = None,
    ) -> APIFuture[types.ForwardBackwardOutput]:
        # 1. Chunk data if needed (max 128 examples per chunk)
        # 2. Allocate request IDs
        # 3. Submit requests in order with turn-taking
        # 4. Return combined future
        ...

    def optim_step(self, adam_params: types.AdamParams) -> APIFuture[types.OptimStepResponse]:
        # Submit optimization step
        # Returns future
        ...

    def save_weights_and_get_sampling_client(
        self,
        name: str | None = None,
        retry_config: RetryConfig | None = None
    ) -> SamplingClient:
        # 1. Save model weights for inference
        # 2. Create and return SamplingClient
        ...
```

### Critical Features

#### Request Sequencing
Operations must execute in request ID order:

```python
async def _take_turn(self, request_id: int):
    # Wait for previous requests to complete
    if self._turn_counter < request_id:
        event = asyncio.Event()
        self._turn_waiters[request_id] = event
        await event.wait()

    # Execute request
    yield

    # Signal next request can proceed
    self._turn_counter += 1
    if self._turn_counter in self._turn_waiters:
        self._turn_waiters[self._turn_counter].set()
```

#### Data Chunking
Large batches are split into chunks:

```python
MAX_CHUNK_LEN = 128
MAX_CHUNK_NUMBER_COUNT = 500000

def _chunked_requests_generator(self, data: List[types.Datum]):
    current_chunk = []
    current_chunk_number_count = 0

    for datum in data:
        estimated_numbers = self._estimate_number_count(datum)

        if (len(current_chunk) >= MAX_CHUNK_LEN or
            current_chunk_number_count + estimated_numbers > MAX_CHUNK_NUMBER_COUNT):
            yield current_chunk
            current_chunk = []
            current_chunk_number_count = 0

        current_chunk.append(datum)
        current_chunk_number_count += estimated_numbers

    if current_chunk:
        yield current_chunk
```

### Elixir Port Strategy

Use **GenServer** with message queue for sequencing:

```elixir
defmodule Tinkex.TrainingClient do
  use GenServer

  @max_chunk_len 128
  @max_chunk_number_count 500_000

  ## Client API

  def forward_backward(client, data, loss_fn, opts \\ []) do
    GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
  end

  def optim_step(client, adam_params) do
    GenServer.call(client, {:optim_step, adam_params})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      model_id: opts[:model_id],
      model_seq_id: opts[:model_seq_id],
      http_pool: opts[:http_pool],
      request_id_counter: 0,
      pending_operations: :queue.new()
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:forward_backward, data, loss_fn, opts}, from, state) do
    # Chunk the data
    chunks = chunk_data(data)

    # Allocate request IDs
    {request_ids, new_counter} = allocate_request_ids(
      length(chunks),
      state.request_id_counter
    )

    # Create async tasks for each chunk
    tasks = Enum.zip(request_ids, chunks)
    |> Enum.map(fn {req_id, chunk} ->
      Task.async(fn ->
        send_forward_backward_request(
          chunk,
          loss_fn,
          state.model_id,
          req_id,
          state.http_pool
        )
      end)
    end)

    # Spawn a process to await all tasks and combine results
    Task.start(fn ->
      results = Task.await_many(tasks, :infinity)
      combined = combine_forward_backward_results(results)
      GenServer.reply(from, {:ok, combined})
    end)

    new_state = %{state | request_id_counter: new_counter}
    {:noreply, new_state}
  end

  defp chunk_data(data) do
    data
    |> Enum.chunk_while(
      {[], 0},
      fn datum, {chunk, count} ->
        estimated = estimate_number_count(datum)

        cond do
          length(chunk) >= @max_chunk_len ->
            {:cont, chunk, {[datum], estimated}}

          count + estimated > @max_chunk_number_count ->
            {:cont, chunk, {[datum], estimated}}

          true ->
            {:cont, {chunk ++ [datum], count + estimated}}
        end
      end,
      fn
        {[], 0} -> {:cont, []}
        {chunk, _count} -> {:cont, chunk, {[], 0}}
      end
    )
  end
end
```

**Key Differences:**
- Elixir's GenServer message queue provides natural sequencing
- Use `Task.async/await` for concurrent chunk processing
- No need for explicit turn-taking (mailbox handles it)

## 3. SamplingClient

**Purpose**: Text generation and inference operations.

### Python Implementation

```python
class SamplingClient(TelemetryProvider, QueueStateObserver):
    def __init__(
        self,
        holder: InternalClientHolder,
        *,
        model_path: str | None = None,
        base_model: str | None = None,
        sampling_session_id: str | None = None,
        retry_config: RetryConfig | None = None,
    ):
        self.holder = holder
        self.model_path = model_path
        self.base_model = base_model

        # Create retry handler with config
        self.retry_handler = RetryHandler(...)

        # Create sampling session
        self._sampling_session_id = (
            sampling_session_id or
            holder.create_sampling_session(model_path, base_model)
        )

        self._request_id_counter = 0

    def sample(
        self,
        prompt: types.ModelInput,
        num_samples: int,
        sampling_params: types.SamplingParams,
        include_prompt_logprobs: bool = False,
        topk_prompt_logprobs: int = 0,
    ) -> ConcurrentFuture[types.SampleResponse]:
        # Submit sampling request with retry logic
        # Return future
        ...
```

### Backpressure Handling

The SamplingClient implements client-side backpressure:

```python
async def _sample_async_impl(self, ...):
    async with self.holder._sample_dispatch_semaphore:
        while True:
            # Check backoff
            if (self.holder._sample_backoff_until and
                time.time() < self.holder._sample_backoff_until):
                await asyncio.sleep(1)
                continue

            # Try to send request
            future = await send_request(...)
            if future is not None:
                break

            # Got 429, back off
            self.holder._sample_backoff_until = time.time() + 1
```

### Elixir Port Strategy

```elixir
defmodule Tinkex.SamplingClient do
  use GenServer

  ## Client API

  def sample(client, prompt, num_samples, sampling_params, opts \\ []) do
    # Returns a Task that resolves to the result
    Task.async(fn ->
      GenServer.call(client, {:sample, prompt, num_samples, sampling_params, opts}, :infinity)
    end)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Create sampling session
    {:ok, session_id} = create_sampling_session(opts)

    state = %{
      sampling_session_id: session_id,
      model_path: opts[:model_path],
      base_model: opts[:base_model],
      http_pool: opts[:http_pool],
      request_id_counter: 0,
      backoff_until: nil,
      # Rate limiting with semaphore
      max_concurrent: 400
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:sample, prompt, num_samples, params, opts}, from, state) do
    # Check backpressure
    now = System.monotonic_time(:millisecond)
    state = case state.backoff_until do
      nil -> state
      backoff_time when backoff_time > now ->
        Process.sleep(backoff_time - now)
        %{state | backoff_until: nil}
      _ ->
        %{state | backoff_until: nil}
    end

    # Send request with retry
    request = build_sample_request(
      state.sampling_session_id,
      state.request_id_counter,
      prompt,
      num_samples,
      params,
      opts
    )

    case send_with_retry(request, state.http_pool) do
      {:ok, response} ->
        new_state = %{state | request_id_counter: state.request_id_counter + 1}
        {:reply, {:ok, response}, new_state}

      {:error, %{status: 429}} = error ->
        # Backoff and retry
        new_state = %{state | backoff_until: now + 1000}
        {:reply, error, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end
end
```

## 4. InternalClientHolder

**Purpose**: Manages shared resources across all clients.

### Python Implementation

Key responsibilities:
1. **Session Management**: Create session, maintain heartbeat
2. **Connection Pooling**: Separate pools per operation type
3. **Event Loop**: Dedicated asyncio event loop in background thread
4. **Retry Logic**: Centralized retry handler

```python
class InternalClientHolder:
    def __init__(self, **kwargs):
        # Dedicated event loop in background thread
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

        # Connection pools
        self._client_pools: dict[ClientConnectionPoolType, ClientConnectionPool] = {}

        # Create session
        session_id, heartbeat_task = self.run_coroutine_threadsafe(
            self._create_session()
        ).result()
        self._session_id = session_id

    def aclient(self, pool_type: ClientConnectionPoolType):
        # Context manager that provides AsyncTinker client
        # from appropriate pool
        ...

    def run_coroutine_threadsafe(self, coro):
        # Submit coroutine to background event loop
        return asyncio.run_coroutine_threadsafe(coro, self._loop)
```

### Elixir Port Strategy

Use **Application supervision tree** with dedicated processes:

```elixir
defmodule Tinkex.Application do
  use Application

  def start(_type, _args) do
    children = [
      # HTTP connection pool
      {Finch, name: Tinkex.HTTP.Pool, pools: pool_config()},

      # Session manager
      Tinkex.SessionManager,

      # Dynamic supervisor for clients
      {DynamicSupervisor, name: Tinkex.ClientSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp pool_config do
    %{
      default: [
        protocol: :http2,
        count: 10,
        max_idle_time: 60_000
      ]
    }
  end
end
```

**Session Manager:**
```elixir
defmodule Tinkex.SessionManager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Send heartbeat every 10 seconds
    schedule_heartbeat()

    state = %{
      sessions: %{}
    }

    {:ok, state}
  end

  def handle_info(:heartbeat, state) do
    # Send heartbeat for all active sessions
    Enum.each(state.sessions, fn {session_id, _} ->
      send_heartbeat(session_id)
    end)

    schedule_heartbeat()
    {:noreply, state}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, 10_000)
  end
end
```

## Next Steps

See `03_async_model.md` for detailed analysis of the async/futures implementation.
