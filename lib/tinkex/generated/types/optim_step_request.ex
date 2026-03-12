defmodule Tinkex.Generated.Types.OptimStepRequest do
  @moduledoc """
  OptimStepRequest type.
  """

  defstruct [:adam_params, :model_id, :seq_id]

  @type t :: %__MODULE__{
          adam_params: term(),
          model_id: term(),
          seq_id: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:adam_params, :any, [required: true]},
      {:model_id, :any, [required: true]},
      {:seq_id, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.OptimStepRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         adam_params: validated["adam_params"],
         model_id: validated["model_id"],
         seq_id: validated["seq_id"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.OptimStepRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "adam_params" => struct.adam_params,
      "model_id" => struct.model_id,
      "seq_id" => struct.seq_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.OptimStepRequest from a map."
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

  @doc "Create a new Tinkex.Generated.Types.OptimStepRequest."
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
