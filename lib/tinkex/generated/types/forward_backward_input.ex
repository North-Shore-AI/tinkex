defmodule Tinkex.Generated.Types.ForwardBackwardInput do
  @moduledoc """
  ForwardBackwardInput type.
  """

  defstruct [:data, :loss_fn, :loss_fn_config]

  @type t :: %__MODULE__{
          data: term(),
          loss_fn: term(),
          loss_fn_config: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:data, :any, [required: true]},
      {:loss_fn, :any, [required: true]},
      {:loss_fn_config, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.ForwardBackwardInput struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         data: validated["data"],
         loss_fn: validated["loss_fn"],
         loss_fn_config: validated["loss_fn_config"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.ForwardBackwardInput struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "data" => struct.data,
      "loss_fn" => struct.loss_fn,
      "loss_fn_config" => struct.loss_fn_config
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.ForwardBackwardInput from a map."
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

  @doc "Create a new Tinkex.Generated.Types.ForwardBackwardInput."
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
