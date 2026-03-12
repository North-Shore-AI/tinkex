defmodule Tinkex.Generated.Types.TelemetrySendRequest do
  @moduledoc """
  TelemetrySendRequest type.
  """

  defstruct [:events, :platform, :sdk_version, :session_id]

  @type t :: %__MODULE__{
          events: term(),
          platform: term(),
          sdk_version: term(),
          session_id: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:events, :any, [required: true]},
      {:platform, :any, [required: true]},
      {:sdk_version, :any, [required: true]},
      {:session_id, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.TelemetrySendRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         events: validated["events"],
         platform: validated["platform"],
         sdk_version: validated["sdk_version"],
         session_id: validated["session_id"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.TelemetrySendRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "events" => struct.events,
      "platform" => struct.platform,
      "sdk_version" => struct.sdk_version,
      "session_id" => struct.session_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.TelemetrySendRequest from a map."
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

  @doc "Create a new Tinkex.Generated.Types.TelemetrySendRequest."
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
