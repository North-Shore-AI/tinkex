defmodule Tinkex.Generated.Types.GetInfoResponse do
  @moduledoc """
  GetInfoResponse type.
  """

  defstruct [:is_lora, :lora_rank, :model_data, :model_id, :model_name, :type]

  @type t :: %__MODULE__{
          is_lora: term() | nil,
          lora_rank: term() | nil,
          model_data: term(),
          model_id: term(),
          model_name: term() | nil,
          type: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:is_lora, :any, [optional: true]},
      {:lora_rank, :any, [optional: true]},
      {:model_data, :any, [required: true]},
      {:model_id, :any, [required: true]},
      {:model_name, :any, [optional: true]},
      {:type, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.GetInfoResponse struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         is_lora: validated["is_lora"],
         lora_rank: validated["lora_rank"],
         model_data: validated["model_data"],
         model_id: validated["model_id"],
         model_name: validated["model_name"],
         type: validated["type"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.GetInfoResponse struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "is_lora" => struct.is_lora,
      "lora_rank" => struct.lora_rank,
      "model_data" => struct.model_data,
      "model_id" => struct.model_id,
      "model_name" => struct.model_name,
      "type" => struct.type
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.GetInfoResponse from a map."
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

  @doc "Create a new Tinkex.Generated.Types.GetInfoResponse."
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
