defmodule Tinkex.CircuitBreaker do
  @moduledoc """
  Per-endpoint circuit breaker for resilient API calls.

  Implements the circuit breaker pattern to prevent cascading failures
  when an endpoint is experiencing issues. The circuit has three states:

  - **Closed**: Normal operation. Requests flow through, failures are counted.
  - **Open**: Requests are rejected immediately. After a timeout, transitions to half-open.
  - **Half-Open**: Limited requests allowed to test if the endpoint has recovered.

  ## Configuration

  - `failure_threshold`: Number of failures before opening circuit (default: 5)
  - `reset_timeout_ms`: Time in open state before trying half-open (default: 30,000ms)
  - `half_open_max_calls`: Calls allowed in half-open state (default: 1)

  ## Usage

      cb = CircuitBreaker.new("sampling-endpoint", failure_threshold: 3)

      {result, cb} = CircuitBreaker.call(cb, fn ->
        # Make API call
        {:ok, response}
      end)

  ## ETS-based Registry

  For multi-process scenarios, use `CircuitBreaker.Registry` to store
  circuit breaker state in ETS:

      CircuitBreaker.Registry.call("endpoint-name", fn ->
        # Make API call
      end)
  """

  defstruct [
    :name,
    :opened_at,
    state: :closed,
    failure_count: 0,
    failure_threshold: 5,
    reset_timeout_ms: 30_000,
    half_open_max_calls: 1,
    half_open_calls: 0
  ]

  @type state :: :closed | :open | :half_open

  @type t :: %__MODULE__{
          name: String.t(),
          state: state(),
          failure_count: non_neg_integer(),
          failure_threshold: pos_integer(),
          reset_timeout_ms: pos_integer(),
          half_open_max_calls: pos_integer(),
          half_open_calls: non_neg_integer(),
          opened_at: integer() | nil
        }

  @doc """
  Create a new circuit breaker.

  ## Options

  - `:failure_threshold` - Failures before opening (default: 5)
  - `:reset_timeout_ms` - Open duration before half-open (default: 30,000)
  - `:half_open_max_calls` - Calls allowed in half-open (default: 1)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, 1)
    }
  end

  @doc """
  Check if a request should be allowed.

  Returns `true` if the circuit is closed or half-open (and under limit).
  Returns `false` if the circuit is open.
  """
  @spec allow_request?(t()) :: boolean()
  def allow_request?(%__MODULE__{} = cb) do
    case state(cb) do
      :closed -> true
      :half_open -> cb.half_open_calls < cb.half_open_max_calls
      :open -> false
    end
  end

  @doc """
  Get the current state of the circuit breaker.

  Accounts for reset timeout transitions from open to half-open.
  """
  @spec state(t()) :: state()
  def state(%__MODULE__{state: :open, opened_at: opened_at, reset_timeout_ms: timeout}) do
    now = System.monotonic_time(:millisecond)

    if now - opened_at >= timeout do
      :half_open
    else
      :open
    end
  end

  def state(%__MODULE__{state: state}), do: state

  @doc """
  Record a successful call.

  Resets failure count. Transitions half-open to closed.
  """
  @spec record_success(t()) :: t()
  def record_success(%__MODULE__{} = cb) do
    case state(cb) do
      :closed ->
        %{cb | failure_count: 0}

      :half_open ->
        %{cb | state: :closed, failure_count: 0, half_open_calls: 0, opened_at: nil}

      :open ->
        # Shouldn't happen, but handle gracefully
        cb
    end
  end

  @doc """
  Record a failed call.

  Increments failure count. Opens circuit if threshold reached.
  """
  @spec record_failure(t()) :: t()
  def record_failure(%__MODULE__{} = cb) do
    current_state = state(cb)

    case current_state do
      :closed ->
        new_count = cb.failure_count + 1

        if new_count >= cb.failure_threshold do
          %{
            cb
            | state: :open,
              failure_count: new_count,
              opened_at: System.monotonic_time(:millisecond)
          }
        else
          %{cb | failure_count: new_count}
        end

      :half_open ->
        # Failure in half-open immediately re-opens
        %{cb | state: :open, opened_at: System.monotonic_time(:millisecond), half_open_calls: 0}

      :open ->
        # Already open, nothing to do
        cb
    end
  end

  @doc """
  Execute a function through the circuit breaker.

  Returns `{result, updated_circuit_breaker}`.

  If the circuit is open, returns `{:error, :circuit_open}` without
  executing the function.

  ## Options

  - `:success?` - Custom function to determine if result is a success.
    Default: `{:ok, _}` is success, `{:error, _}` is failure.

  ## Examples

      {result, cb} = CircuitBreaker.call(cb, fn ->
        Tinkex.API.Sampling.sample_async(request, opts)
      end)

      # Custom success classification (4xx errors don't trip breaker)
      {result, cb} = CircuitBreaker.call(cb, fn ->
        Tinkex.API.post("/endpoint", body, opts)
      end, success?: fn
        {:ok, _} -> true
        {:error, %{status: status}} when status < 500 -> true
        _ -> false
      end)
  """
  @spec call(t(), (-> result), keyword()) :: {result | {:error, :circuit_open}, t()}
        when result: term()
  def call(%__MODULE__{} = cb, fun, opts \\ []) do
    success_fn = Keyword.get(opts, :success?, &default_success?/1)

    case state(cb) do
      :open ->
        {{:error, :circuit_open}, cb}

      current_state ->
        # Increment half-open calls if in half-open state
        cb =
          if current_state == :half_open do
            %{cb | half_open_calls: cb.half_open_calls + 1}
          else
            cb
          end

        result = fun.()

        if success_fn.(result) do
          {result, record_success(cb)}
        else
          {result, record_failure(cb)}
        end
    end
  end

  @doc """
  Reset the circuit breaker to closed state.
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = cb) do
    %{cb | state: :closed, failure_count: 0, half_open_calls: 0, opened_at: nil}
  end

  # Private helpers

  defp default_success?({:ok, _}), do: true
  defp default_success?(_), do: false
end
