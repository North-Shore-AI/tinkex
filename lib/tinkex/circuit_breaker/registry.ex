defmodule Tinkex.CircuitBreaker.Registry do
  @moduledoc """
  ETS-based registry for circuit breaker state.

  Circuit breakers are identified by endpoint names and can be shared across
  processes in the same node. Updates are versioned to avoid lost-update races
  under concurrency.

  ## Usage

      # Initialize the registry (typically in Application.start/2)
      CircuitBreaker.Registry.init()

      # Execute a call through a circuit breaker
      case CircuitBreaker.Registry.call("sampling-endpoint", fn ->
        Tinkex.API.Sampling.sample_async(request, opts)
      end) do
        {:ok, result} -> handle_success(result)
        {:error, :circuit_open} -> {:error, "Service temporarily unavailable"}
        {:error, reason} -> {:error, reason}
      end

      # Check circuit state
      CircuitBreaker.Registry.state("sampling-endpoint")
      # => :closed | :open | :half_open

      # Reset a specific circuit
      CircuitBreaker.Registry.reset("sampling-endpoint")
  """

  alias Foundation.CircuitBreaker.Registry, as: FoundationRegistry
  alias Tinkex.CircuitBreaker

  @table_name :tinkex_circuit_breakers

  @doc """
  Initialize the circuit breaker registry.

  Creates the ETS table if it doesn't exist. Safe to call multiple times.
  """
  @spec init() :: :ok
  def init do
    _ = FoundationRegistry.new_registry(name: @table_name)

    :ok
  end

  @doc """
  Execute a function through a named circuit breaker.

  Creates the circuit breaker if it doesn't exist.

  ## Options

  - `:failure_threshold` - Failures before opening (default: 5)
  - `:reset_timeout_ms` - Open duration before half-open (default: 30,000)
  - `:half_open_max_calls` - Calls allowed in half-open (default: 1)
  - `:success?` - Custom success classifier function
  """
  @spec call(String.t(), (-> result), keyword()) :: result | {:error, :circuit_open}
        when result: term()
  def call(name, fun, opts \\ []) do
    FoundationRegistry.call(@table_name, name, fun, opts)
  end

  @doc """
  Get the current state of a circuit breaker.

  Returns `:closed` if the circuit breaker doesn't exist.
  """
  @spec state(String.t()) :: CircuitBreaker.state()
  def state(name) do
    FoundationRegistry.state(@table_name, name)
  end

  @doc """
  Reset a circuit breaker to closed state.
  """
  @spec reset(String.t()) :: :ok
  def reset(name) do
    FoundationRegistry.reset(@table_name, name)
  end

  @doc """
  Delete a circuit breaker from the registry.
  """
  @spec delete(String.t()) :: :ok
  def delete(name) do
    FoundationRegistry.delete(@table_name, name)
  end

  @doc """
  List all circuit breakers and their states.
  """
  @spec list() :: [{String.t(), CircuitBreaker.state()}]
  def list do
    FoundationRegistry.list(@table_name)
  end
end
