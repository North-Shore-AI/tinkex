defmodule Tinkex.Types.RegularizerSpec do
  @moduledoc """
  Specification for a single regularizer in the composition pipeline.

  ## Fields

  - `:fn` - The regularizer function. Must accept `(data, logprobs)` and
    return `{loss_tensor, metrics_map}`. For async regularizers, should
    return a `Task.t()` that resolves to the same tuple.

  - `:weight` - Non-negative float multiplier for the regularizer loss.
    The contribution to total loss is `weight * regularizer_loss`.

  - `:name` - String identifier for telemetry and metrics. Must be unique
    within a regularizer list.

  - `:async` - Boolean flag indicating whether `fn` returns a Task (default: false).
    When true, the executor will `Task.await/2` the result.

  ## Examples

      # Synchronous regularizer
      %RegularizerSpec{
        fn: fn _data, logprobs ->
          {Nx.sum(Nx.abs(logprobs)), %{"l1" => 1.0}}
        end,
        weight: 0.01,
        name: "l1_sparsity"
      }

      # Async regularizer (I/O-bound)
      %RegularizerSpec{
        fn: fn data, _logprobs ->
          Task.async(fn ->
            result = external_api_call(data)
            {Nx.tensor(result.penalty), %{"validated" => true}}
          end)
        end,
        weight: 0.1,
        name: "external_validation",
        async: true
      }
  """

  @type regularizer_result :: {Nx.Tensor.t(), %{String.t() => number()}}

  @type regularizer_fn ::
          (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() -> regularizer_result())

  @type async_regularizer_fn ::
          (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
             Task.t())

  @enforce_keys [:fn, :weight, :name]
  defstruct [:fn, :weight, :name, async: false]

  @type t :: %__MODULE__{
          fn: regularizer_fn() | async_regularizer_fn(),
          weight: number(),
          name: String.t(),
          async: boolean()
        }

  @doc """
  Create a new RegularizerSpec with validation.

  ## Examples

      RegularizerSpec.new(%{
        fn: &my_regularizer/2,
        weight: 0.01,
        name: "l1"
      })

      RegularizerSpec.new(fn: &my_reg/2, weight: 0.5, name: "entropy")
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    validate!(attrs)

    %__MODULE__{
      fn: Map.fetch!(attrs, :fn),
      weight: Map.fetch!(attrs, :weight),
      name: Map.fetch!(attrs, :name),
      async: Map.get(attrs, :async, false)
    }
  end

  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  @doc """
  Validate regularizer spec attributes.

  Raises `ArgumentError` if any validation fails.

  ## Validations

  - `:fn` must be a function of arity 2
  - `:weight` must be a non-negative number
  - `:name` must be a non-empty string
  - `:async` must be a boolean (if provided)
  """
  @spec validate!(map()) :: :ok
  def validate!(attrs) do
    fn_val = Map.get(attrs, :fn)

    unless is_function(fn_val, 2) do
      raise ArgumentError,
            "RegularizerSpec :fn must be a function of arity 2, got: #{inspect(fn_val)}"
    end

    weight = Map.get(attrs, :weight)

    unless is_number(weight) and weight >= 0 do
      raise ArgumentError,
            "RegularizerSpec :weight must be a non-negative number, got: #{inspect(weight)}"
    end

    name = Map.get(attrs, :name)

    unless is_binary(name) and byte_size(name) > 0 do
      raise ArgumentError,
            "RegularizerSpec :name must be a non-empty string, got: #{inspect(name)}"
    end

    async = Map.get(attrs, :async, false)

    unless is_boolean(async) do
      raise ArgumentError,
            "RegularizerSpec :async must be a boolean, got: #{inspect(async)}"
    end

    :ok
  end
end
