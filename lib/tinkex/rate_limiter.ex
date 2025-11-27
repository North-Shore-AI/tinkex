defmodule Tinkex.RateLimiter do
  @moduledoc """
  Shared backoff state per `{base_url, api_key}` combination.
  """

  alias Tinkex.PoolKey

  @type limiter :: :atomics.atomics_ref()

  @doc """
  Get or create the limiter for a `{base_url, api_key}` tuple.
  """
  @spec for_key({String.t(), String.t() | nil}) :: limiter()
  def for_key({base_url, api_key}) do
    normalized_base = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized_base, api_key}}

    limiter = :atomics.new(1, signed: true)

    case :ets.insert_new(:tinkex_rate_limiters, {key, limiter}) do
      true ->
        limiter

      false ->
        case :ets.lookup(:tinkex_rate_limiters, key) do
          [{^key, existing}] ->
            existing

          [] ->
            :ets.insert(:tinkex_rate_limiters, {key, limiter})
            limiter
        end
    end
  end

  @doc """
  Determine whether the limiter is currently in a backoff window.
  """
  @spec should_backoff?(limiter()) :: boolean()
  def should_backoff?(limiter) do
    backoff_until = :atomics.get(limiter, 1)

    backoff_until != 0 and System.monotonic_time(:millisecond) < backoff_until
  end

  @doc """
  Set a backoff window in milliseconds.
  """
  @spec set_backoff(limiter(), non_neg_integer()) :: :ok
  def set_backoff(limiter, duration_ms) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    :atomics.put(limiter, 1, backoff_until)
    :ok
  end

  @doc """
  Clear any active backoff window.
  """
  @spec clear_backoff(limiter()) :: :ok
  def clear_backoff(limiter) do
    :atomics.put(limiter, 1, 0)
    :ok
  end

  @doc """
  Block until the backoff window has passed.
  """
  @spec wait_for_backoff(limiter()) :: :ok
  def wait_for_backoff(limiter) do
    backoff_until = :atomics.get(limiter, 1)

    if backoff_until != 0 do
      now = System.monotonic_time(:millisecond)

      wait_ms = backoff_until - now

      if wait_ms > 0 do
        Process.sleep(wait_ms)
      end
    end

    :ok
  end
end
