defmodule Tinkex.Types.Telemetry.GenericEvent do
  @moduledoc """
  Generic telemetry event structure.

  Mirrors Python tinker.types.generic_event.GenericEvent.
  Used for custom application-level events.
  """

  alias Tinkex.Types.Telemetry.{EventType, Severity}

  @type t :: %__MODULE__{
          event: :generic_event,
          event_id: String.t(),
          event_session_index: non_neg_integer(),
          severity: Severity.t(),
          timestamp: String.t(),
          event_name: String.t(),
          event_data: map()
        }

  @enforce_keys [:event_id, :event_session_index, :timestamp, :event_name]
  defstruct event: :generic_event,
            event_id: nil,
            event_session_index: nil,
            severity: :info,
            timestamp: nil,
            event_name: nil,
            event_data: %{}

  @doc """
  Create a new GenericEvent.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      event: :generic_event,
      event_id: Keyword.fetch!(attrs, :event_id),
      event_session_index: Keyword.fetch!(attrs, :event_session_index),
      severity: Keyword.get(attrs, :severity, :info),
      timestamp: Keyword.fetch!(attrs, :timestamp),
      event_name: Keyword.fetch!(attrs, :event_name),
      event_data: Keyword.get(attrs, :event_data, %{})
    }
  end

  @doc """
  Convert struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "event" => EventType.to_string(:generic_event),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => event.timestamp,
      "event_name" => event.event_name,
      "event_data" => event.event_data
    }
  end

  @doc """
  Parse wire format map to struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      event: :generic_event,
      event_id: map["event_id"],
      event_session_index: map["event_session_index"],
      severity: Severity.parse(map["severity"]) || :info,
      timestamp: map["timestamp"],
      event_name: map["event_name"],
      event_data: map["event_data"] || %{}
    }
  end
end
