defmodule Tinkex.SamplingDispatch do
  @moduledoc """
  Layered dispatch rate limiting for sampling requests.

  Applies:
  1. Global concurrency semaphore (default 400)
  2. Throttled concurrency semaphore when a recent backoff was requested
  3. Byte budget semaphore (5MB baseline, 20× penalty during recent backoff)

  Backoff timestamps are tracked with monotonic time to match RateLimiter
  behavior and keep a brief "recently throttled" window even after the
  backoff has cleared.
  """

  use GenServer

  alias Tinkex.{BytesSemaphore, PoolKey, RateLimiter}

  @default_concurrency 400
  @throttled_concurrency 10
  @default_byte_budget 5 * 1024 * 1024
  @backoff_window_ms 10_000
  @byte_penalty_multiplier 20

  @type snapshot :: %{
          concurrency: %{name: term(), limit: pos_integer()},
          throttled: %{name: term(), limit: pos_integer()},
          bytes: BytesSemaphore.t(),
          backoff_active?: boolean()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Execute `fun` while holding layered dispatch semaphores.
  """
  @spec with_rate_limit(pid(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_rate_limit(dispatch, estimated_bytes, fun) when is_function(fun, 0) do
    snapshot = GenServer.call(dispatch, :snapshot, :infinity)
    execute_with_limits(snapshot, max(estimated_bytes, 0), fun)
  end

  @doc """
  Set a backoff window (in milliseconds) and mark the dispatch as recently throttled.
  """
  @spec set_backoff(pid(), non_neg_integer()) :: :ok
  def set_backoff(dispatch, duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    GenServer.call(dispatch, {:set_backoff, duration_ms})
  end

  @impl true
  def init(opts) do
    limiter = Keyword.fetch!(opts, :rate_limiter)
    base_url = Keyword.fetch!(opts, :base_url)
    api_key = Keyword.get(opts, :api_key)

    concurrency_limit = Keyword.get(opts, :concurrency, @default_concurrency)
    throttled_limit = Keyword.get(opts, :throttled_concurrency, @throttled_concurrency)
    byte_budget = Keyword.get(opts, :byte_budget, @default_byte_budget)

    ensure_semaphore_started()

    concurrency = %{
      name: concurrency_name(base_url, api_key, concurrency_limit),
      limit: concurrency_limit
    }

    throttled = %{
      name: throttled_name(base_url, api_key, throttled_limit),
      limit: throttled_limit
    }

    {:ok, bytes_semaphore} = BytesSemaphore.start_link(max_bytes: byte_budget)

    {:ok,
     %{
       rate_limiter: limiter,
       concurrency: concurrency,
       throttled: throttled,
       bytes: bytes_semaphore,
       last_backoff_until: nil
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  def handle_call({:set_backoff, duration_ms}, _from, state) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    RateLimiter.set_backoff(state.rate_limiter, duration_ms)
    {:reply, :ok, %{state | last_backoff_until: backoff_until}}
  end

  defp snapshot(state) do
    %{
      concurrency: state.concurrency,
      throttled: state.throttled,
      bytes: state.bytes,
      backoff_active?: recent_backoff?(state.last_backoff_until)
    }
  end

  defp recent_backoff?(nil), do: false

  defp recent_backoff?(backoff_until) do
    now = System.monotonic_time(:millisecond)
    now < backoff_until or now - backoff_until < @backoff_window_ms
  end

  defp execute_with_limits(snapshot, estimated_bytes, fun) do
    backoff_active? = snapshot.backoff_active?

    effective_bytes =
      if backoff_active?, do: estimated_bytes * @byte_penalty_multiplier, else: estimated_bytes

    acquire_counting(snapshot.concurrency)

    try do
      maybe_acquire_throttled(snapshot.throttled, backoff_active?)

      try do
        BytesSemaphore.with_bytes(snapshot.bytes, effective_bytes, fun)
      after
        maybe_release_throttled(snapshot.throttled, backoff_active?)
      end
    after
      release_counting(snapshot.concurrency)
    end
  end

  defp acquire_counting(%{name: name, limit: limit}) do
    case Semaphore.acquire(name, limit) do
      true ->
        :ok

      false ->
        Process.sleep(2)
        acquire_counting(%{name: name, limit: limit})
    end
  end

  defp release_counting(%{name: name}) do
    Semaphore.release(name)
  end

  defp maybe_acquire_throttled(_semaphore, false), do: :ok

  defp maybe_acquire_throttled(%{name: name, limit: limit}, true) do
    acquire_counting(%{name: name, limit: limit})
  end

  defp maybe_release_throttled(_semaphore, false), do: :ok
  defp maybe_release_throttled(%{name: name}, true), do: Semaphore.release(name)

  defp ensure_semaphore_started do
    case Process.whereis(Semaphore) do
      nil ->
        {:ok, _pid} = Semaphore.start_link()
        :ok

      _pid ->
        :ok
    end
  end

  defp concurrency_name(base_url, api_key, limit) do
    {:tinkex_sampling_dispatch, PoolKey.normalize_base_url(base_url), api_key, :concurrency,
     limit}
  end

  defp throttled_name(base_url, api_key, limit) do
    {:tinkex_sampling_dispatch, PoolKey.normalize_base_url(base_url), api_key, :throttled, limit}
  end
end
