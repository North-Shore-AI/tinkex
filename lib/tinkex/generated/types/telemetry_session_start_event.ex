defmodule Tinkex.Generated.Types.TelemetrySessionStartEvent do
  @moduledoc """
  TelemetrySessionStartEvent type.
  """

  defstruct [:event, :event_id, :event_session_index, :severity, :timestamp]

  @type t :: %__MODULE__{
          event: term() | nil,
          event_id: term(),
          event_session_index: term(),
          severity: term() | nil,
          timestamp: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:event, :any, [optional: true]},
      {:event_id, :any, [required: true]},
      {:event_session_index, :any, [required: true]},
      {:severity, :any, [optional: true]},
      {:timestamp, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.TelemetrySessionStartEvent struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         event: validated["event"],
         event_id: validated["event_id"],
         event_session_index: validated["event_session_index"],
         severity: validated["severity"],
         timestamp: validated["timestamp"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.TelemetrySessionStartEvent struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "event" => struct.event,
      "event_id" => struct.event_id,
      "event_session_index" => struct.event_session_index,
      "severity" => struct.severity,
      "timestamp" => struct.timestamp
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.TelemetrySessionStartEvent from a map."
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

  @doc "Create a new Tinkex.Generated.Types.TelemetrySessionStartEvent."
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
