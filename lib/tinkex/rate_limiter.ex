defmodule Tinkex.RateLimiter do
  @moduledoc """
  Shared backoff state per `{base_url, api_key}` combination.
  """

  alias Foundation.RateLimit.BackoffWindow
  alias Tinkex.PoolKey

  @registry_name :tinkex_rate_limiters

  @type limiter :: BackoffWindow.limiter()

  @doc """
  Get or create the limiter for a `{base_url, api_key}` tuple.
  """
  @spec for_key({String.t(), String.t() | nil}) :: limiter()
  def for_key({base_url, api_key}) do
    normalized_base = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized_base, api_key}}
    BackoffWindow.for_key(registry(), key)
  end

  @doc """
  Determine whether the limiter is currently in a backoff window.
  """
  @spec should_backoff?(limiter()) :: boolean()
  def should_backoff?(limiter) do
    BackoffWindow.should_backoff?(limiter)
  end

  @doc """
  Set a backoff window in milliseconds.
  """
  @spec set_backoff(limiter(), non_neg_integer()) :: :ok
  def set_backoff(limiter, duration_ms) do
    BackoffWindow.set(limiter, duration_ms)
  end

  @doc """
  Clear any active backoff window.
  """
  @spec clear_backoff(limiter()) :: :ok
  def clear_backoff(limiter) do
    BackoffWindow.clear(limiter)
  end

  @doc """
  Block until the backoff window has passed.
  """
  @spec wait_for_backoff(limiter()) :: :ok
  def wait_for_backoff(limiter) do
    BackoffWindow.wait(limiter)
  end

  defp registry do
    BackoffWindow.new_registry(name: @registry_name)
  end
end
