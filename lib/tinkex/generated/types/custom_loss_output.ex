defmodule Tinkex.Generated.Types.CustomLossOutput do
  @moduledoc """
  CustomLossOutput type.
  """

  defstruct [:base_loss, :loss_total, :regularizer_total, :regularizers, :total_grad_norm]

  @type t :: %__MODULE__{
          base_loss: term() | nil,
          loss_total: term(),
          regularizer_total: term() | nil,
          regularizers: term() | nil,
          total_grad_norm: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:base_loss, :any, [optional: true]},
      {:loss_total, :any, [required: true]},
      {:regularizer_total, :any, [optional: true]},
      {:regularizers, :any, [optional: true]},
      {:total_grad_norm, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.CustomLossOutput struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         base_loss: validated["base_loss"],
         loss_total: validated["loss_total"],
         regularizer_total: validated["regularizer_total"],
         regularizers: validated["regularizers"],
         total_grad_norm: validated["total_grad_norm"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.CustomLossOutput struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "base_loss" => struct.base_loss,
      "loss_total" => struct.loss_total,
      "regularizer_total" => struct.regularizer_total,
      "regularizers" => struct.regularizers,
      "total_grad_norm" => struct.total_grad_norm
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.CustomLossOutput from a map."
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

  @doc "Create a new Tinkex.Generated.Types.CustomLossOutput."
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
