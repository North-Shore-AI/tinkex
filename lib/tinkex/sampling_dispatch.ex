defmodule Tinkex.SamplingDispatch do
  @moduledoc """
  Layered dispatch rate limiting for sampling requests.

  Applies:
  1. Global concurrency semaphore (default 400)
  2. Throttled concurrency semaphore when a recent backoff was requested
  3. Byte budget semaphore (5MB baseline, 20× penalty during recent backoff)

  Backoff timestamps are tracked with monotonic time to match BackoffWindow
  behavior and keep a brief "recently throttled" window even after the
  backoff has cleared.
  """

  use GenServer

  alias Foundation.RateLimit.BackoffWindow
  alias Foundation.Semaphore.Weighted, as: WeightedSemaphore
  alias Tinkex.PoolKey

  @default_concurrency 400
  @throttled_concurrency 10
  @default_byte_budget 5 * 1024 * 1024
  @backoff_window_ms 10_000
  @byte_penalty_multiplier 20
  @default_acquire_backoff_base_ms 2
  @default_acquire_backoff_max_ms 50
  @default_acquire_backoff_jitter 0.25
  @max_backoff_exponent 20

  @type snapshot :: %{
          concurrency: %{name: term(), limit: pos_integer()},
          throttled: %{name: term(), limit: pos_integer()},
          bytes: WeightedSemaphore.t(),
          backoff_active?: boolean(),
          acquire_backoff: map()
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
    acquire_backoff = build_acquire_backoff(Keyword.get(opts, :acquire_backoff, []))

    ensure_semaphore_started()

    concurrency = %{
      name: concurrency_name(base_url, api_key, concurrency_limit),
      limit: concurrency_limit
    }

    throttled = %{
      name: throttled_name(base_url, api_key, throttled_limit),
      limit: throttled_limit
    }

    {:ok, bytes_semaphore} = WeightedSemaphore.start_link(max_weight: byte_budget)

    {:ok,
     %{
       rate_limiter: limiter,
       concurrency: concurrency,
       throttled: throttled,
       bytes: bytes_semaphore,
       last_backoff_until: nil,
       acquire_backoff: acquire_backoff
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  def handle_call({:set_backoff, duration_ms}, _from, state) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    BackoffWindow.set(state.rate_limiter, duration_ms)
    {:reply, :ok, %{state | last_backoff_until: backoff_until}}
  end

  defp snapshot(state) do
    %{
      concurrency: state.concurrency,
      throttled: state.throttled,
      bytes: state.bytes,
      backoff_active?: recent_backoff?(state.last_backoff_until),
      acquire_backoff: state.acquire_backoff
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

    acquire_counting(snapshot.concurrency, snapshot.acquire_backoff)

    try do
      maybe_acquire_throttled(snapshot.throttled, backoff_active?, snapshot.acquire_backoff)

      try do
        WeightedSemaphore.with_acquire(snapshot.bytes, effective_bytes, fun)
      after
        maybe_release_throttled(snapshot.throttled, backoff_active?, snapshot.acquire_backoff)
      end
    after
      release_counting(snapshot.concurrency, snapshot.acquire_backoff)
    end
  end

  defp acquire_counting(%{name: name, limit: limit}, backoff, attempt \\ 0) do
    case backoff.acquire_fun.(name, limit) do
      true ->
        :ok

      false ->
        backoff.sleep_fun.(backoff_delay(backoff, attempt))
        acquire_counting(%{name: name, limit: limit}, backoff, attempt + 1)
    end
  end

  defp release_counting(%{name: name}, backoff) do
    backoff.release_fun.(name)
  end

  defp maybe_acquire_throttled(_semaphore, false, _backoff), do: :ok

  defp maybe_acquire_throttled(%{name: name, limit: limit}, true, backoff) do
    acquire_counting(%{name: name, limit: limit}, backoff)
  end

  defp maybe_release_throttled(_semaphore, false, _backoff), do: :ok
  defp maybe_release_throttled(%{name: name}, true, backoff), do: backoff.release_fun.(name)

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

  defp build_acquire_backoff(nil), do: build_acquire_backoff([])

  defp build_acquire_backoff(opts) when is_map(opts),
    do: build_acquire_backoff(Map.to_list(opts))

  defp build_acquire_backoff(opts) when is_list(opts) do
    backoff =
      %{
        base_ms: @default_acquire_backoff_base_ms,
        max_ms: @default_acquire_backoff_max_ms,
        jitter: @default_acquire_backoff_jitter,
        sleep_fun: &Process.sleep/1,
        rand_fun: &:rand.uniform/0,
        acquire_fun: &Semaphore.acquire/2,
        release_fun: &Semaphore.release/1
      }
      |> Map.merge(Map.new(opts))

    %{
      base_ms: positive_or_default(backoff.base_ms, @default_acquire_backoff_base_ms),
      max_ms:
        positive_or_default(backoff.max_ms, @default_acquire_backoff_max_ms)
        |> max(positive_or_default(backoff.base_ms, @default_acquire_backoff_base_ms)),
      jitter: normalize_jitter(backoff.jitter),
      sleep_fun: normalize_sleep_fun(backoff.sleep_fun),
      rand_fun: normalize_rand_fun(backoff.rand_fun),
      acquire_fun: normalize_acquire_fun(backoff.acquire_fun),
      release_fun: normalize_release_fun(backoff.release_fun)
    }
  end

  defp build_acquire_backoff(_), do: build_acquire_backoff([])

  defp backoff_delay(backoff, attempt) when is_integer(attempt) and attempt >= 0 do
    capped_attempt = min(attempt, @max_backoff_exponent)
    base_delay = trunc(backoff.base_ms * :math.pow(2, capped_attempt))
    capped_delay = min(base_delay, backoff.max_ms)
    apply_jitter(capped_delay, backoff.jitter, backoff.rand_fun)
  end

  defp backoff_delay(backoff, _attempt), do: backoff.base_ms

  defp apply_jitter(delay, jitter, _rand_fun) when jitter <= 0, do: delay

  defp apply_jitter(delay, jitter, rand_fun) do
    factor = 1 - jitter + rand_fun.() * jitter
    max(trunc(delay * factor), 0)
  end

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp normalize_jitter(value) when is_float(value) and value >= 0 and value <= 1, do: value
  defp normalize_jitter(value) when is_integer(value) and value in [0, 1], do: value * 1.0
  defp normalize_jitter(_value), do: @default_acquire_backoff_jitter

  defp normalize_sleep_fun(fun) when is_function(fun, 1), do: fun
  defp normalize_sleep_fun(_fun), do: &Process.sleep/1

  defp normalize_rand_fun(fun) when is_function(fun, 0), do: fun
  defp normalize_rand_fun(_fun), do: &:rand.uniform/0

  defp normalize_acquire_fun(fun) when is_function(fun, 2), do: fun
  defp normalize_acquire_fun(_fun), do: &Semaphore.acquire/2

  defp normalize_release_fun(fun) when is_function(fun, 1), do: fun
  defp normalize_release_fun(_fun), do: &Semaphore.release/1
end
