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
    {version, cb} = get_or_create(name, opts)
    success_fn = Keyword.get(opts, :success?, &default_success?/1)
    current_state = CircuitBreaker.state(cb)

    if allow_request?(cb, current_state) do
      result = fun.()
      success? = success_fn.(result)
      updated_cb = apply_result(cb, success?)
      update_with_retry(name, version, updated_cb, success?, opts)
      result
    else
      {:error, :circuit_open}
    end
  end

  @doc """
  Get the current state of a circuit breaker.

  Returns `:closed` if the circuit breaker doesn't exist.
  """
  @spec state(String.t()) :: CircuitBreaker.state()
  def state(name) do
    case get_cb(name) do
      nil -> :closed
      cb -> CircuitBreaker.state(cb)
    end
  end

  @doc """
  Reset a circuit breaker to closed state.
  """
  @spec reset(String.t()) :: :ok
  def reset(name) do
    case get_entry(name) do
      nil -> :ok
      {version, cb} -> update_with_retry_raw(name, version, CircuitBreaker.reset(cb))
    end

    :ok
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
    |> Enum.map(fn
      {name, cb} -> {name, CircuitBreaker.state(cb)}
      {name, _version, cb} -> {name, CircuitBreaker.state(cb)}
    end)
  end

  # Private functions

  defp get_entry(name) do
    ensure_table()

    case :ets.lookup(@table_name, name) do
      [{^name, version, cb}] ->
        {version, cb}

      [{^name, cb}] ->
        :ets.insert(@table_name, {name, 0, cb})
        {0, cb}

      [] ->
        nil
    end
  end

  defp get_cb(name) do
    case get_entry(name) do
      nil -> nil
      {_version, cb} -> cb
    end
  end

  defp get_or_create(name, opts) do
    cb_opts = Keyword.take(opts, [:failure_threshold, :reset_timeout_ms, :half_open_max_calls])

    case get_entry(name) do
      nil ->
        cb = CircuitBreaker.new(name, cb_opts)

        case :ets.insert_new(@table_name, {name, 0, cb}) do
          true -> {0, cb}
          false -> get_entry(name)
        end

      {version, cb} ->
        {version, cb}
    end
  end

  defp allow_request?(cb, current_state) do
    case current_state do
      :closed -> true
      :open -> false
      :half_open -> cb.half_open_calls < cb.half_open_max_calls
    end
  end

  defp apply_result(cb, success?) do
    current_state = CircuitBreaker.state(cb)

    cb =
      if current_state == :half_open do
        %{cb | half_open_calls: cb.half_open_calls + 1}
      else
        cb
      end

    if success? do
      CircuitBreaker.record_success(cb)
    else
      CircuitBreaker.record_failure(cb)
    end
  end

  defp update_with_retry(name, version, updated_cb, success?, opts) do
    if cas_update(name, version, updated_cb) do
      :ok
    else
      case get_entry(name) do
        {next_version, cb} ->
          next_cb = apply_result(cb, success?)
          update_with_retry(name, next_version, next_cb, success?, opts)

        nil ->
          {next_version, cb} = get_or_create(name, opts)
          next_cb = apply_result(cb, success?)
          update_with_retry(name, next_version, next_cb, success?, opts)
      end
    end
  end

  defp update_with_retry_raw(name, version, updated_cb) do
    if cas_update(name, version, updated_cb) do
      :ok
    else
      case get_entry(name) do
        {next_version, cb} -> update_with_retry_raw(name, next_version, CircuitBreaker.reset(cb))
        nil -> :ok
      end
    end
  end

  defp cas_update(name, version, cb) do
    match_spec = [{{name, version, :"$1"}, [], [{{name, version + 1, cb}}]}]
    :ets.select_replace(@table_name, match_spec) == 1
  end

  defp default_success?({:ok, _}), do: true
  defp default_success?(_), do: false

  defp ensure_table do
    case :ets.whereis(@table_name) do
      :undefined -> init()
      _ref -> :ok
    end
  end
end
