# Sampling Dispatch Throttling Specification

## Summary

Implement layered byte-aware dispatch throttling for sampling requests, matching Python SDK v0.7.0. This includes:
- Global concurrency semaphore (existing: 400 concurrent)
- Throttled concurrency semaphore (new: 10 concurrent during backoff)
- Byte budget semaphore (new: 5MB baseline, 20× penalty during backoff)
- Monotonic backoff timestamps (new: prevents clock drift issues)

## Python SDK Reference

### BytesSemaphore

```python
# tinker/src/tinker/lib/internal_client_holder.py

class BytesSemaphore:
    def __init__(self, max_bytes: int):
        self._bytes: int = max_bytes
        self._condition: asyncio.Condition = asyncio.Condition()
        self._release_task: asyncio.Task[None] | None = None

    async def _release(self):
        async with self._condition:
            self._condition.notify_all()

    @asynccontextmanager
    async def acquire(self, bytes: int):
        async with self._condition:
            while self._bytes < 0:
                await self._condition.wait()
        self._bytes -= bytes
        try:
            yield
        finally:
            self._bytes += bytes
            self._release_task = asyncio.create_task(self._release())
```

### InternalClientHolder Throttling

```python
class InternalClientHolder:
    def __init__(self, ...):
        self._sample_backoff_until: float | None = None
        self._sample_dispatch_semaphore: asyncio.Semaphore = asyncio.Semaphore(400)
        self._sample_dispatch_throttled_semaphore: asyncio.Semaphore = asyncio.Semaphore(10)
        self._sample_dispatch_bytes_semaphore: BytesSemaphore = BytesSemaphore(5 * 1024 * 1024)

    def _sample_backoff_requested_recently(self) -> bool:
        return (
            self._sample_backoff_until is not None and
            time.monotonic() - self._sample_backoff_until < 10
        )

    @asynccontextmanager
    async def _sample_dispatch_bytes_rate_limit(self, bytes: int):
        if self._sample_backoff_requested_recently():
            bytes *= 20  # 20× penalty during backoff
        async with self._sample_dispatch_bytes_semaphore.acquire(bytes):
            yield

    @asynccontextmanager
    async def sample_dispatch_rate_limit(self, estimated_bytes_count: int):
        async with contextlib.AsyncExitStack() as stack:
            await stack.enter_async_context(self._sample_dispatch_count_rate_limit())
            if self._sample_backoff_requested_recently():
                await stack.enter_async_context(self._sample_dispatch_count_throttled_rate_limit())
            await stack.enter_async_context(self._sample_dispatch_bytes_rate_limit(estimated_bytes_count))
            yield
```

### SamplingClient Backoff

```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py

async def _sample_async_impl(self, prompt, ...):
    estimated_bytes_count = self.holder.estimate_bytes_count_in_model_input(prompt)
    async with self.holder.sample_dispatch_rate_limit(estimated_bytes_count):
        while True:
            if (
                self.holder._sample_backoff_until is not None and
                time.monotonic() < self.holder._sample_backoff_until
            ):
                await asyncio.sleep(1)
                continue

            # ... send request ...

            if untyped_future is not None:
                break

            # 429 handling - scale backoff with payload size
            backoff_duration = 1 if estimated_bytes_count <= 128 * 1024 else 5
            self.holder._sample_backoff_until = time.monotonic() + backoff_duration
            continue
```

## Current Elixir Implementation

### SamplingClient Dispatch

```elixir
# lib/tinkex/sampling_client.ex

@default_dispatch_concurrency 400

defp build_dispatch_semaphore(config, opts) do
  limit = Keyword.get(opts, :dispatch_concurrency, @default_dispatch_concurrency)
  %{name: {...}, limit: limit}
end

defp with_dispatch(%{dispatch_semaphore: semaphore}, fun) do
  acquire_dispatch(semaphore.name, semaphore.limit)
  try do
    fun.()
  after
    Semaphore.release(semaphore.name)
  end
end
```

### RateLimiter

```elixir
# lib/tinkex/rate_limiter.ex (existing)
# Provides per-key backoff tracking
```

### Missing Components

1. **BytesSemaphore**: No equivalent
2. **Throttled semaphore**: No secondary low-limit semaphore
3. **Byte budget**: No byte-aware rate limiting
4. **Recent backoff window**: `RateLimiter` is monotonic but clearing backoff erases “recently throttled” context; need local tracking to mirror Python’s `_sample_backoff_until`.

## Required Changes

### 1. New BytesSemaphore Module

**File**: `lib/tinkex/bytes_semaphore.ex`

```elixir
defmodule Tinkex.BytesSemaphore do
  @moduledoc """
  Byte-budget semaphore for rate limiting by payload size.

  Unlike count-based semaphores, this tracks cumulative byte usage and
  blocks acquisition when the budget goes negative. Useful for throttling
  large payloads without over-penalizing small requests.

  ## Architecture

  Uses a GenServer to track byte budget across concurrent processes.
  Acquisition can "go negative" to allow in-flight requests to complete,
  but new acquisitions block until budget recovers.
  """

  use GenServer

  @type t :: pid()

  defstruct [:max_bytes, :current_bytes, :waiters]

  @doc """
  Start a BytesSemaphore with the given byte budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, 5 * 1024 * 1024)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, max_bytes, name: name)
  end

  @doc """
  Acquire bytes from the semaphore.

  Blocks if current budget is negative. Returns `:ok` when acquired.
  """
  @spec acquire(t(), non_neg_integer()) :: :ok
  def acquire(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    GenServer.call(semaphore, {:acquire, bytes}, :infinity)
  end

  @doc """
  Release bytes back to the semaphore.
  """
  @spec release(t(), non_neg_integer()) :: :ok
  def release(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    GenServer.cast(semaphore, {:release, bytes})
  end

  @doc """
  Execute a function with acquired bytes, releasing on completion.
  """
  @spec with_bytes(t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_bytes(semaphore, bytes, fun) do
    acquire(semaphore, bytes)
    try do
      fun.()
    after
      release(semaphore, bytes)
    end
  end

  # GenServer callbacks

  @impl true
  def init(max_bytes) do
    state = %__MODULE__{
      max_bytes: max_bytes,
      current_bytes: max_bytes,
      waiters: :queue.new()
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, bytes}, from, state) do
    if state.current_bytes >= 0 do
      # Budget available, acquire immediately
      {:reply, :ok, %{state | current_bytes: state.current_bytes - bytes}}
    else
      # Budget negative, queue the waiter
      waiters = :queue.in({from, bytes}, state.waiters)
      {:noreply, %{state | waiters: waiters}}
    end
  end

  @impl true
  def handle_cast({:release, bytes}, state) do
    new_bytes = state.current_bytes + bytes
    state = %{state | current_bytes: new_bytes}

    # Wake up waiters if budget is now positive
    state = maybe_wake_waiters(state)
    {:noreply, state}
  end

  defp maybe_wake_waiters(%{current_bytes: bytes, waiters: waiters} = state)
       when bytes >= 0 do
    case :queue.out(waiters) do
      {{:value, {from, request_bytes}}, remaining} ->
        GenServer.reply(from, :ok)
        state = %{state |
          current_bytes: bytes - request_bytes,
          waiters: remaining
        }
        maybe_wake_waiters(state)

      {:empty, _} ->
        state
    end
  end

  defp maybe_wake_waiters(state), do: state
end
```

### 2. New SamplingDispatch Module

**File**: `lib/tinkex/sampling_dispatch.ex`

```elixir
defmodule Tinkex.SamplingDispatch do
  @moduledoc """
  Layered dispatch rate limiting for sampling requests.

  Implements Python SDK v0.7.0 throttling strategy:
  1. Global concurrency semaphore (400 concurrent)
  2. Throttled concurrency semaphore (10 concurrent during backoff)
  3. Byte budget semaphore (5MB baseline, 20× penalty during backoff)

  ## Usage

      {:ok, dispatch} = SamplingDispatch.start_link(rate_limiter: rate_limiter)

      SamplingDispatch.with_rate_limit(dispatch, estimated_bytes, fn ->
        # Send sampling request
      end)
  """

  use GenServer

  alias Tinkex.BytesSemaphore
  alias Tinkex.RateLimiter

  @default_concurrency 400
  @throttled_concurrency 10
  @default_byte_budget 5 * 1024 * 1024  # 5MB
  @backoff_window_ms 10_000
  @byte_penalty_multiplier 20

  defstruct [
    :rate_limiter,
    :concurrency_semaphore,
    :throttled_semaphore,
    :bytes_semaphore,
    :config,
    :last_backoff_until
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Execute a function with layered rate limiting.

  Acquires all necessary semaphores based on current backoff state:
  - Always: global concurrency semaphore
  - During backoff: throttled concurrency semaphore
  - Always: byte budget (with 20× penalty during backoff)
  """
  @spec with_rate_limit(pid(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_rate_limit(dispatch, estimated_bytes, fun) do
    GenServer.call(dispatch, {:with_rate_limit, estimated_bytes, fun}, :infinity)
  end

  @doc """
  Set backoff state (called after 429 response).
  """
  @spec set_backoff(pid(), non_neg_integer()) :: :ok
  def set_backoff(dispatch, duration_ms) do
    GenServer.call(dispatch, {:set_backoff, duration_ms})
  end

  @impl true
  def init(opts) do
    rate_limiter = Keyword.fetch!(opts, :rate_limiter)

    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    throttled = Keyword.get(opts, :throttled_concurrency, @throttled_concurrency)
    byte_budget = Keyword.get(opts, :byte_budget, @default_byte_budget)

    {:ok, concurrency_sem} = start_counting_semaphore(concurrency)
    {:ok, throttled_sem} = start_counting_semaphore(throttled)
    {:ok, bytes_sem} = BytesSemaphore.start_link(max_bytes: byte_budget)

    state = %__MODULE__{
      rate_limiter: rate_limiter,
      concurrency_semaphore: concurrency_sem,
      throttled_semaphore: throttled_sem,
      bytes_semaphore: bytes_sem,
      config: %{
        concurrency: concurrency,
        throttled: throttled,
        byte_budget: byte_budget
      }
    }

    state = %{state | last_backoff_until: nil}
    {:ok, state}
  end

  @impl true
  def handle_call({:with_rate_limit, estimated_bytes, fun}, _from, state) do
    result = execute_with_limits(state, estimated_bytes, fun)
    {:reply, result, state}
  end

  def handle_call({:set_backoff, duration_ms}, _from, state) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    RateLimiter.set_backoff(state.rate_limiter, duration_ms)
    {:reply, :ok, %{state | last_backoff_until: backoff_until}}
  end

  defp execute_with_limits(state, estimated_bytes, fun) do
    now = System.monotonic_time(:millisecond)

    backoff_active? =
      state.last_backoff_until != nil and
        (now < state.last_backoff_until or now - state.last_backoff_until < @backoff_window_ms)

    # Calculate effective byte cost
    effective_bytes =
      if backoff_active? do
        estimated_bytes * @byte_penalty_multiplier
      else
        estimated_bytes
      end

    # Acquire semaphores in order
    acquire_counting_semaphore(state.concurrency_semaphore, state.config.concurrency)

    try do
      if backoff_active? do
        acquire_counting_semaphore(state.throttled_semaphore, state.config.throttled)
      end

      try do
        BytesSemaphore.with_bytes(state.bytes_semaphore, effective_bytes, fun)
      after
        if backoff_active? do
          release_counting_semaphore(state.throttled_semaphore)
        end
      end
    after
      release_counting_semaphore(state.concurrency_semaphore)
    end
  end

  # Use Erlang's :semaphore or Semaphore library
  defp start_counting_semaphore(limit) do
    # Using the Semaphore library pattern from SamplingClient
    name = make_ref()
    {:ok, %{name: name, limit: limit}}
  end

  defp acquire_counting_semaphore(%{name: name, limit: limit}, _) do
    case Semaphore.acquire(name, limit) do
      true -> :ok
      false ->
        Process.sleep(2)
        acquire_counting_semaphore(%{name: name, limit: limit}, limit)
    end
  end

  defp release_counting_semaphore(%{name: name}) do
    Semaphore.release(name)
  end
end
```

**Note:** `last_backoff_until` is intentionally not cleared when RateLimiter backoff is cleared; this mirrors Python’s `_sample_backoff_until` so we can keep throttling for a short window after the server asked us to slow down.

### 3. Update SamplingClient

**File**: `lib/tinkex/sampling_client.ex`

```elixir
defmodule Tinkex.SamplingClient do
  alias Tinkex.ByteEstimator
  alias Tinkex.SamplingDispatch

  # In init/1, create dispatch module
  def init(opts) do
    # ... existing init ...

    {:ok, dispatch} =
      SamplingDispatch.start_link(
        rate_limiter: limiter,
        concurrency: Keyword.get(opts, :dispatch_concurrency, 400),
        byte_budget: Keyword.get(opts, :byte_budget, 5 * 1024 * 1024)
      )

    entry = %{
      # ... existing fields ...
      dispatch: dispatch
    }
  end

  # Update do_sample_once to use byte-aware dispatch
  defp do_sample_once(entry, prompt, sampling_params, opts) do
    estimated_bytes = ByteEstimator.estimate_model_input_bytes(prompt)

    SamplingDispatch.with_rate_limit(entry.dispatch, estimated_bytes, fn ->
      RateLimiter.wait_for_backoff(entry.rate_limiter)
      seq_id = next_seq_id(entry.request_id_counter)

      # ... existing request building ...

      case entry.sampling_api.sample_async(request, api_opts) do
        {:ok, resp} ->
          RateLimiter.clear_backoff(entry.rate_limiter)
          handle_sample_response(resp, entry, seq_id, opts)

        {:error, %Error{status: 429} = error} ->
          # Scale backoff with payload size
          backoff = if estimated_bytes <= 128 * 1024, do: 1_000, else: 5_000
          SamplingDispatch.set_backoff(entry.dispatch, backoff)
          {:error, error}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end)
  end
end
```

## Test Cases

```elixir
# test/tinkex/bytes_semaphore_test.exs

describe "BytesSemaphore" do
  test "allows acquisition up to budget" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1000)

    # Acquire 500 bytes - should succeed immediately
    task1 = Task.async(fn -> BytesSemaphore.acquire(sem, 500) end)
    assert Task.await(task1) == :ok

    # Acquire another 600 bytes - goes negative but allowed
    task2 = Task.async(fn -> BytesSemaphore.acquire(sem, 600) end)
    assert Task.await(task2) == :ok

    # Third acquisition should block until release
    task3 = Task.async(fn -> BytesSemaphore.acquire(sem, 100) end)
    refute Task.yield(task3, 100)

    # Release first 500 bytes
    BytesSemaphore.release(sem, 500)

    # task3 should complete after release brings budget positive
    assert Task.await(task3) == :ok
  end

  test "with_bytes releases on normal return" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

    result = BytesSemaphore.with_bytes(sem, 50, fn -> :done end)
    assert result == :done

    # Budget should be restored
    assert BytesSemaphore.acquire(sem, 100) == :ok
  end

  test "with_bytes releases on exception" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

    catch_error do
      BytesSemaphore.with_bytes(sem, 50, fn -> raise "oops" end)
    end

    # Budget should still be restored
    assert BytesSemaphore.acquire(sem, 100) == :ok
  end
end

# test/tinkex/sampling_dispatch_test.exs

describe "SamplingDispatch" do
  test "applies 20× penalty during backoff" do
    limiter = RateLimiter.for_key({"http://example.com", "k"})
    {:ok, dispatch} = SamplingDispatch.start_link(
      rate_limiter: limiter,
      byte_budget: 1_000_000  # 1MB
    )

    # Set backoff
    SamplingDispatch.set_backoff(dispatch, 10_000)

    # 100KB request should consume 2MB of budget (20× penalty)
    # which exceeds the 1MB budget, causing blocking
    task = Task.async(fn ->
      SamplingDispatch.with_rate_limit(dispatch, 100_000, fn -> :done end)
    end)

    # Should eventually complete but will be heavily throttled
    assert Task.await(task, 5000) == :done
  end

  test "normal operation without backoff" do
    limiter = RateLimiter.for_key({"http://example.com", "k"})
    {:ok, dispatch} = SamplingDispatch.start_link(
      rate_limiter: limiter,
      byte_budget: 1_000_000
    )

    # 100KB request without backoff - fast path
    result = SamplingDispatch.with_rate_limit(dispatch, 100_000, fn -> :done end)
    assert result == :done
  end
end
```

## Performance Considerations

### Memory

- BytesSemaphore maintains waiter queue (bounded by concurrency limit)
- Each SamplingClient gets its own dispatch state

### Latency

- Layered semaphores add acquisition overhead (~microseconds)
- Backoff state check is O(1)
- Byte calculation reuses existing ByteEstimator

### Concurrency

- Global semaphore (400) limits total in-flight requests
- Throttled semaphore (10) severely limits during backoff
- Byte budget smooths large payload bursts

## Files Affected

| File | Change |
|------|--------|
| `lib/tinkex/bytes_semaphore.ex` | NEW - Byte-budget semaphore |
| `lib/tinkex/sampling_dispatch.ex` | NEW - Layered dispatch controller |
| `lib/tinkex/sampling_client.ex` | Integrate dispatch, byte estimation |
| `test/tinkex/bytes_semaphore_test.exs` | NEW - Unit tests |
| `test/tinkex/sampling_dispatch_test.exs` | NEW - Integration tests |

## Dependencies

- **Spec 03 (ByteEstimator)**: Required for byte estimation
- **Semaphore library**: Already used by SamplingClient

## Implementation Priority

**Medium** - Improves resilience during rate limiting but not critical for basic operation.
