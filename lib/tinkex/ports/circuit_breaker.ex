defmodule Tinkex.Ports.CircuitBreaker do
  @moduledoc """
  Port for circuit breaker execution.
  """

  @callback call(String.t(), (-> term()), keyword()) :: term()
end
