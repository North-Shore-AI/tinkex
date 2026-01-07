defmodule Tinkex.Adapters.FoundationCB do
  @moduledoc """
  Foundation-based circuit breaker adapter.
  """

  @behaviour Tinkex.Ports.CircuitBreaker

  alias Foundation.CircuitBreaker.Registry

  @impl true
  def call(name, fun, opts) when is_function(fun, 0) do
    registry = Keyword.get(opts, :registry, Registry.default_registry())
    opts = Keyword.delete(opts, :registry)
    Registry.call(registry, to_string(name), fun, opts)
  end
end
