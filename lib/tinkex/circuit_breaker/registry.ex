defmodule Tinkex.CircuitBreaker.Registry do
  @moduledoc """
  ETS-based registry for circuit breaker state.

  Provides process-safe circuit breaker management using ETS for state storage.
  Circuit breakers are identified by endpoint names and can be shared across
  processes in the same node.

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

  alias Tinkex.CircuitBreaker

  @table_name :tinkex_circuit_breakers

  @doc """
  Initialize the circuit breaker registry.

  Creates the ETS table if it doesn't exist. Safe to call multiple times.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ref ->
        :ok
    end

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
    cb = get_or_create(name, opts)
    call_opts = Keyword.take(opts, [:success?])

    {result, updated_cb} = CircuitBreaker.call(cb, fun, call_opts)
    put(name, updated_cb)

    result
  end

  @doc """
  Get the current state of a circuit breaker.

  Returns `:closed` if the circuit breaker doesn't exist.
  """
  @spec state(String.t()) :: CircuitBreaker.state()
  def state(name) do
    case get(name) do
      nil -> :closed
      cb -> CircuitBreaker.state(cb)
    end
  end

  @doc """
  Reset a circuit breaker to closed state.
  """
  @spec reset(String.t()) :: :ok
  def reset(name) do
    case get(name) do
      nil ->
        :ok

      cb ->
        put(name, CircuitBreaker.reset(cb))
        :ok
    end
  end

  @doc """
  Delete a circuit breaker from the registry.
  """
  @spec delete(String.t()) :: :ok
  def delete(name) do
    ensure_table()
    :ets.delete(@table_name, name)
    :ok
  end

  @doc """
  List all circuit breakers and their states.
  """
  @spec list() :: [{String.t(), CircuitBreaker.state()}]
  def list do
    ensure_table()

    :ets.tab2list(@table_name)
    |> Enum.map(fn {name, cb} -> {name, CircuitBreaker.state(cb)} end)
  end

  # Private functions

  defp get(name) do
    ensure_table()

    case :ets.lookup(@table_name, name) do
      [{^name, cb}] -> cb
      [] -> nil
    end
  end

  defp put(name, cb) do
    ensure_table()
    :ets.insert(@table_name, {name, cb})
    :ok
  end

  defp get_or_create(name, opts) do
    case get(name) do
      nil ->
        cb = CircuitBreaker.new(name, opts)
        put(name, cb)
        cb

      cb ->
        cb
    end
  end

  defp ensure_table do
    case :ets.whereis(@table_name) do
      :undefined -> init()
      _ref -> :ok
    end
  end
end
