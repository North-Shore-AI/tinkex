# Client Architecture Analysis

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202, 300-302, 400+. See response documents for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- **SamplingClient**: Changed to "thin GenServer" pattern (state only, HTTP in caller's process)
- **TrainingClient**: Clarified sequential request sends with concurrent polling
- **GenServer Pattern**: Emphasis on state management, not work execution

**Key Corrections (Round 2 - Critiques 200-202):**
- **SamplingClient**: Changed to ETS-based architecture (eliminates GenServer.call bottleneck)
- **RateLimiter**: Added shared backoff state using atomics for 429 coordination
- **TrainingClient**: Fixed race condition (synchronous sends, async polling)
- **Request sequencing**: All training operations share same seq_id counter

**Key Corrections (Round 3 - Critiques 300-302):**
- **ETS table ownership**: Fixed CRITICAL bug - global table in Application, per-client entries (named tables are singletons!)
- **Config threading**: Removed global Application.get_env, pass config through client structs for multi-tenancy
- **Tokenizer heuristics**: Added get_tokenizer_id with Llama-3 special case and caching
- **Task error handling**: Added try/rescue wrappers to prevent infinite hangs
- **Defensive ETS**: Added pattern matching for missing entries

**Key Corrections (Round 4 - Critique 400+):**
- **Task.start safety**: ALL Task.start bodies that call GenServer.reply MUST have try/rescue to prevent infinite hangs
- **SamplingClient return type**: ALWAYS return Task (never mix {:error, ...} and Task.t)
- **429 retry_after_ms**: Use error.retry_after_ms from parsed headers, not hard-coded 1000ms
- **Config struct**: Thread config through all client operations (api_key, base_url, http_pool, timeout)
- **API consistency**: All public client methods return Task.t({:ok, ...} | {:error, ...})

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
    # ⚠️ UPDATED (Round 3): Thread config through state for multi-tenancy
    config = %{
      api_key: opts[:api_key] || Application.get_env(:tinkex, :api_key) || System.get_env("TINKER_API_KEY"),
      base_url: opts[:base_url] || Application.get_env(:tinkex, :base_url),
      http_pool: opts[:http_pool] || Tinkex.HTTP.Pool,
      user_metadata: opts[:user_metadata] || %{}
    }

    # Create session on server (pass config)
    # Start heartbeat process
    with {:ok, session_id} <- create_session(config),
         :ok <- start_heartbeat(session_id, config) do
      state = %{
        session_id: session_id,
        training_client_counter: 0,
        sampling_client_counter: 0,
        config: config,  # Store config for child clients
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

    # Allocate request IDs for all chunks upfront
    {request_ids, new_counter} = allocate_request_ids(
      length(chunks),
      state.request_id_counter
    )

    # ⚠️ CRITICAL: Send ALL requests SYNCHRONOUSLY (blocks GenServer)
    # This ensures requests are sent in order BEFORE next operation starts
    untyped_futures = Enum.zip(request_ids, chunks)
    |> Enum.map(fn {req_id, chunk} ->
      # SYNCHRONOUS send - blocks GenServer until request sent
      {:ok, untyped_future} = send_forward_backward_request(
        chunk,
        loss_fn,
        state.model_id,
        req_id,
        state.http_pool
      )
      untyped_future
    end)

    # ⚠️ CRITICAL (Round 4): Spawn background task with error handling
    # If task crashes without try/rescue, GenServer.reply never called → caller hangs forever!
    Task.start(fn ->
      reply = try do
        # Create polling tasks for each future
        polling_tasks = Enum.map(untyped_futures, fn future ->
          Tinkex.Future.poll(future.request_id, state.http_pool)
        end)

        # Await all polling tasks concurrently
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
      GenServer.reply(from, reply)
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

**Key Differences ⚠️ UPDATED:**
- **GenServer blocks during send phase** - prevents race conditions
- Requests are sent **synchronously** inside `handle_call` (one at a time)
- **Only after all sends complete** does GenServer spawn polling task
- Polling for results happens **concurrently** using `Task.await_many`
- No explicit turn-taking locks needed (GenServer mailbox + sync sends ensure ordering)

**Why This Works (avoiding race condition):**
```
User calls forward_backward() twice rapidly:

CORRECT (this design):
1. GenServer receives Msg1 → Sends Req1, Req2, Req3 (blocks)
2. After sends complete → Spawns polling task, returns {:noreply}
3. GenServer receives Msg2 → Sends Req4, Req5, Req6 (blocks)
4. Guaranteed order: Req1, Req2, Req3, Req4, Req5, Req6 ✓

WRONG (spawn Task immediately):
1. GenServer receives Msg1 → Spawns Task A, returns {:noreply}
2. GenServer receives Msg2 → Spawns Task B (parallel!)
3. Race: Task B might send Req4 before Task A sends Req2 ✗
```

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

### Elixir Port Strategy ⚠️ CORRECTED - ETS-Based Architecture

**CRITICAL FIX (Round 2):** Even "thin GenServer" with `GenServer.call` creates a bottleneck at 400 concurrent requests. The solution is **ETS for lock-free reads** and **atomics for shared backoff state**.

#### Step 1: RateLimiter Module (Shared Backoff State)

```elixir
defmodule Tinkex.RateLimiter do
  @moduledoc """
  Shared backoff state for sampling requests.

  When ONE request gets 429, ALL requests back off immediately.
  Uses atomics for lock-free coordination.
  """

  @doc "Create new rate limiter (returns atomics reference)"
  def new do
    # Store backoff_until timestamp (monotonic milliseconds)
    :atomics.new(1, signed: true)
  end

  @doc "Check if currently in backoff period"
  def should_backoff?(limiter) do
    backoff_until = :atomics.get(limiter, 1)
    System.monotonic_time(:millisecond) < backoff_until
  end

  @doc "Set backoff period (duration in milliseconds)"
  def set_backoff(limiter, duration_ms) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    :atomics.put(limiter, 1, backoff_until)
  end

  @doc "Clear backoff state"
  def clear_backoff(limiter) do
    :atomics.put(limiter, 1, 0)
  end

  @doc "Wait until backoff expires"
  def wait_for_backoff(limiter) do
    if should_backoff?(limiter) do
      Process.sleep(100)
      wait_for_backoff(limiter)
    end
  end
end
```

#### Step 2: SamplingClient with ETS

```elixir
defmodule Tinkex.SamplingClient do
  use GenServer

  ## Client API

  @doc """
  Sample from the model. NO GenServer call - reads from ETS directly.

  ⚠️ CRITICAL (Round 4): ALWAYS returns Task.t({:ok, response} | {:error, error})
  Never mixes return types!
  """
  def sample(client, prompt, num_samples, sampling_params, opts \\ []) do
    # ⚠️ UPDATED (Round 4): ALWAYS return Task for consistency
    Task.async(fn ->
      # ⚠️ UPDATED (Round 3): Defensive ETS lookup with pattern matching
      case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
        [{_, config}] ->
          # Wait if currently in backoff period
          Tinkex.RateLimiter.wait_for_backoff(config.rate_limiter)

          # Increment request ID (lock-free atomic)
          request_id = :atomics.add_get(config.request_id_counter, 1, 1)

          request = %Tinkex.Types.SampleRequest{
            sampling_session_id: config.sampling_session_id,
            seq_id: request_id,
            num_samples: num_samples,
            prompt: prompt,
            sampling_params: sampling_params,
            prompt_logprobs: opts[:include_prompt_logprobs] || false,
            topk_prompt_logprobs: opts[:topk_prompt_logprobs] || 0
          }

          # HTTP call in THIS process
          # ⚠️ UPDATED (Round 4): Use retry_after_ms from error, not hard-coded 1000ms
          case Tinkex.API.Sampling.asample(request, config.http_pool, opts) do
            {:error, %Tinkex.Error{status: 429, retry_after_ms: retry_ms} = error} ->
              # Got rate limited - use server-provided backoff
              backoff_ms = retry_ms || 1000  # Fallback to 1000ms if not provided
              Tinkex.RateLimiter.set_backoff(config.rate_limiter, backoff_ms)
              {:error, error}

            result ->
              result
          end

        [] ->
          # Client not initialized or already terminated
          {:error, %Tinkex.Error{
            message: "SamplingClient not initialized",
            type: :validation
          }}
      end
    end)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Create sampling session
    {:ok, session_id} = create_sampling_session(opts)

    # ⚠️ CRITICAL FIX (Round 3): Do NOT create named table here!
    # Named tables are BEAM-wide singletons - second client will crash.
    # Table MUST be created in Application.start/2

    # Create lock-free request ID counter (per-client)
    request_id_counter = :atomics.new(1, signed: false)

    # Create shared rate limiter (per-client)
    rate_limiter = Tinkex.RateLimiter.new()

    # Write THIS client's config to global ETS table
    # Table created in Tinkex.Application.start/2
    :ets.insert(:tinkex_sampling_clients, {
      {:config, self()},
      %{
        sampling_session_id: session_id,
        http_pool: opts[:http_pool] || Tinkex.HTTP.Pool,
        request_id_counter: request_id_counter,
        rate_limiter: rate_limiter,
        config: opts[:config]  # Store config for API calls
      }
    })

    state = %{
      sampling_session_id: session_id
    }

    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # ⚠️ CRITICAL: Delete only THIS client's entry, NOT the table!
    :ets.delete(:tinkex_sampling_clients, {:config, self()})
    :ok
  end
end
```

**Why This Works:**
1. **Zero GenServer calls** during sampling (ETS reads are lock-free)
2. **True 400 concurrent requests** - no serialization bottleneck
3. **Shared backoff state** - when one request hits 429, all requests back off
4. **Lock-free counters** - atomics for request IDs and backoff timestamps
5. **Minimal latency** - ETS read is ~100ns, GenServer.call is ~5-10μs

**Performance Comparison:**
- **GenServer.call approach**: 400 requests × 5μs = 2ms serialization overhead
- **ETS approach**: 400 requests × 100ns = 40μs total overhead
- **Speedup**: 50x faster at high concurrency

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
    # ⚠️ CRITICAL (Round 3): Create global ETS tables BEFORE starting children
    # Named tables are BEAM-wide singletons - must be created once at app start
    :ets.new(:tinkex_sampling_clients, [
      :set,
      :public,
      :named_table,
      read_concurrency: true  # Optimize for concurrent reads
    ])

    :ets.new(:tinkex_tokenizers, [
      :set,
      :public,
      :named_table,
      read_concurrency: true  # Tokenizer cache
    ])

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

## 5. Tokenizer Module ⚠️ NEW (Round 3)

**CRITICAL:** Python SDK has complex tokenizer selection logic that MUST be ported exactly, including hardcoded Llama-3 hack.

```elixir
defmodule Tinkex.Tokenizer do
  @moduledoc """
  Tokenizer management with HuggingFace model support and caching.

  Ports Python SDK's _get_tokenizer logic including special cases.
  """

  @doc """
  Get tokenizer ID for a model (matches Python SDK exactly).

  1. Try to get from server via get_info
  2. Hardcoded Llama-3 hack (gating workaround)
  3. Fallback to model_name
  """
  def get_tokenizer_id(training_client, model_name) do
    # Try to get from server
    case Tinkex.TrainingClient.get_info(training_client) do
      {:ok, %{model_data: %{tokenizer_id: id}}} when not is_nil(id) ->
        id

      _ ->
        # Hardcoded Llama-3 hack (matches Python exactly!)
        if String.contains?(model_name, "Llama-3") do
          "baseten/Meta-Llama-3-tokenizer"
        else
          model_name  # Fallback
        end
    end
  end

  @doc """
  Encode text to tokens using cached tokenizer.

  Tokenizers are cached in :tinkex_tokenizers ETS table to avoid
  re-downloading from HuggingFace Hub on every call.
  """
  def encode(text, model_name) do
    tokenizer = case :ets.lookup(:tinkex_tokenizers, model_name) do
      [{^model_name, tok}] -> tok
      [] -> load_and_cache(model_name)
    end

    {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, text)
    Tokenizers.Encoding.get_ids(encoding)
  end

  defp load_and_cache(model_name) do
    {:ok, tokenizer} = Tokenizers.Tokenizer.from_pretrained(model_name)
    :ets.insert(:tinkex_tokenizers, {model_name, tokenizer})
    tokenizer
  end
end
```

**Why the Llama-3 hack matters:**
- Llama-3 models have gating issues on HuggingFace
- Without this hack, tokenizer loading fails immediately
- Python SDK includes this workaround
- We must match it for compatibility

## Next Steps

See `03_async_model.md` for detailed analysis of the async/futures implementation.
