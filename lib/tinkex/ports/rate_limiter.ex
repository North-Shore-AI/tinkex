defmodule Tinkex.Ports.RateLimiter do
  @moduledoc """
  Port for rate-limiting primitives.
  """

  @type limiter :: term()

  @callback for_key(term(), keyword()) :: limiter()
  @callback wait(limiter(), keyword()) :: :ok
  @callback clear(limiter()) :: :ok
  @callback set(limiter(), non_neg_integer(), keyword()) :: :ok
end
