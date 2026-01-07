defmodule Tinkex.Adapters.FoundationRate do
  @moduledoc """
  Foundation-based rate limiter adapter.
  """

  @behaviour Tinkex.Ports.RateLimiter

  alias Foundation.RateLimit.BackoffWindow

  @impl true
  def for_key(key, opts \\ []) do
    registry = Keyword.get(opts, :registry, BackoffWindow.default_registry())
    BackoffWindow.for_key(registry, key)
  end

  @impl true
  def wait(limiter, opts \\ []) do
    BackoffWindow.wait(limiter, opts)
  end

  @impl true
  def clear(limiter) do
    BackoffWindow.clear(limiter)
  end

  @impl true
  def set(limiter, duration_ms, opts \\ []) do
    BackoffWindow.set(limiter, duration_ms, opts)
  end
end
