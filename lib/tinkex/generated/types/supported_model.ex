defmodule Tinkex.Generated.Types.SupportedModel do
  @moduledoc """
  SupportedModel type.
  """

  defstruct [:arch, :model_id, :model_name]

  @type t :: %__MODULE__{
          arch: term() | nil,
          model_id: term() | nil,
          model_name: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:arch, :any, [optional: true]},
      {:model_id, :any, [optional: true]},
      {:model_name, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SupportedModel struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         arch: validated["arch"],
         model_id: validated["model_id"],
         model_name: validated["model_name"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SupportedModel struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "arch" => struct.arch,
      "model_id" => struct.model_id,
      "model_name" => struct.model_name
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SupportedModel from a map."
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

  @doc "Create a new Tinkex.Generated.Types.SupportedModel."
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
