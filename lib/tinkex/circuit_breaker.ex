defmodule Tinkex.CircuitBreaker do
  @moduledoc """
  Per-endpoint circuit breaker for resilient API calls.

  Delegates core state transitions to `Foundation.CircuitBreaker` while keeping
  the Tinkex struct shape for compatibility.
  """

  alias Foundation.CircuitBreaker, as: FoundationCircuitBreaker

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

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    FoundationCircuitBreaker.new(name, opts)
    |> from_foundation()
  end

  @spec allow_request?(t()) :: boolean()
  def allow_request?(%__MODULE__{} = cb) do
    cb |> to_foundation() |> FoundationCircuitBreaker.allow_request?()
  end

  @spec state(t()) :: state()
  def state(%__MODULE__{} = cb) do
    cb |> to_foundation() |> FoundationCircuitBreaker.state()
  end

  @spec record_success(t()) :: t()
  def record_success(%__MODULE__{} = cb) do
    cb |> to_foundation() |> FoundationCircuitBreaker.record_success() |> from_foundation()
  end

  @spec record_failure(t()) :: t()
  def record_failure(%__MODULE__{} = cb) do
    cb |> to_foundation() |> FoundationCircuitBreaker.record_failure() |> from_foundation()
  end

  @spec call(t(), (-> result), keyword()) :: {result | {:error, :circuit_open}, t()}
        when result: term()
  def call(%__MODULE__{} = cb, fun, opts \\ []) when is_function(fun, 0) do
    {result, updated_cb} =
      cb
      |> to_foundation()
      |> FoundationCircuitBreaker.call(fun, opts)

    {result, from_foundation(updated_cb)}
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = cb) do
    cb |> to_foundation() |> FoundationCircuitBreaker.reset() |> from_foundation()
  end

  defp to_foundation(%__MODULE__{} = cb) do
    struct(FoundationCircuitBreaker, Map.from_struct(cb))
  end

  defp from_foundation(%FoundationCircuitBreaker{} = cb) do
    struct(__MODULE__, Map.from_struct(cb))
  end
end
