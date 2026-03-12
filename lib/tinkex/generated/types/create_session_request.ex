defmodule Tinkex.Generated.Types.CreateSessionRequest do
  @moduledoc """
  CreateSessionRequest type.
  """

  defstruct [:sdk_version, :tags, :type, :user_metadata]

  @type t :: %__MODULE__{
          sdk_version: term(),
          tags: term(),
          type: term() | nil,
          user_metadata: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:sdk_version, :any, [required: true]},
      {:tags, :any, [required: true]},
      {:type, :any, [optional: true]},
      {:user_metadata, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.CreateSessionRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         sdk_version: validated["sdk_version"],
         tags: validated["tags"],
         type: validated["type"],
         user_metadata: validated["user_metadata"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.CreateSessionRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "sdk_version" => struct.sdk_version,
      "tags" => struct.tags,
      "type" => struct.type,
      "user_metadata" => struct.user_metadata
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.CreateSessionRequest from a map."
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

  @doc "Create a new Tinkex.Generated.Types.CreateSessionRequest."
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
