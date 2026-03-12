defmodule Tinkex.Generated.Types.GetSamplerResponse do
  @moduledoc """
  GetSamplerResponse type.
  """

  defstruct [:base_model, :model_path, :sampler_id]

  @type t :: %__MODULE__{
          base_model: term(),
          model_path: term() | nil,
          sampler_id: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:base_model, :any, [required: true]},
      {:model_path, :any, [optional: true]},
      {:sampler_id, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.GetSamplerResponse struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         base_model: validated["base_model"],
         model_path: validated["model_path"],
         sampler_id: validated["sampler_id"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.GetSamplerResponse struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "base_model" => struct.base_model,
      "model_path" => struct.model_path,
      "sampler_id" => struct.sampler_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.GetSamplerResponse from a map."
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

  @doc "Create a new Tinkex.Generated.Types.GetSamplerResponse."
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
