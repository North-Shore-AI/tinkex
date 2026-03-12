defmodule Tinkex.Generated.Types.SaveWeightsForSamplerRequest do
  @moduledoc """
  SaveWeightsForSamplerRequest type.
  """

  defstruct [:model_id, :path, :sampling_session_seq_id, :seq_id, :type]

  @type t :: %__MODULE__{
          model_id: term(),
          path: term() | nil,
          sampling_session_seq_id: term() | nil,
          seq_id: term() | nil,
          type: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:model_id, :any, [required: true]},
      {:path, :any, [optional: true]},
      {:sampling_session_seq_id, :any, [optional: true]},
      {:seq_id, :any, [optional: true]},
      {:type, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SaveWeightsForSamplerRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         model_id: validated["model_id"],
         path: validated["path"],
         sampling_session_seq_id: validated["sampling_session_seq_id"],
         seq_id: validated["seq_id"],
         type: validated["type"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SaveWeightsForSamplerRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "model_id" => struct.model_id,
      "path" => struct.path,
      "sampling_session_seq_id" => struct.sampling_session_seq_id,
      "seq_id" => struct.seq_id,
      "type" => struct.type
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SaveWeightsForSamplerRequest from a map."
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

  @doc "Create a new Tinkex.Generated.Types.SaveWeightsForSamplerRequest."
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
