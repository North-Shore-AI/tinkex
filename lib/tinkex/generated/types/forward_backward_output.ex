defmodule Tinkex.Generated.Types.ForwardBackwardOutput do
  @moduledoc """
  ForwardBackwardOutput type.
  """

  defstruct [:loss_fn_output_type, :loss_fn_outputs, :metrics]

  @type t :: %__MODULE__{
          loss_fn_output_type: term(),
          loss_fn_outputs: term() | nil,
          metrics: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:loss_fn_output_type, :any, [required: true]},
      {:loss_fn_outputs, :any, [optional: true]},
      {:metrics, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.ForwardBackwardOutput struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         loss_fn_output_type: validated["loss_fn_output_type"],
         loss_fn_outputs: validated["loss_fn_outputs"],
         metrics: validated["metrics"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.ForwardBackwardOutput struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "loss_fn_output_type" => struct.loss_fn_output_type,
      "loss_fn_outputs" => struct.loss_fn_outputs,
      "metrics" => struct.metrics
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.ForwardBackwardOutput from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    struct(__MODULE__, atomize_keys(data))
  end

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.ForwardBackwardOutput."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
