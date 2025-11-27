defmodule Tinkex.Types.Telemetry.SessionStartEvent do
  @moduledoc """
  Session start telemetry event.

  Mirrors Python tinker.types.session_start_event.SessionStartEvent.
  Emitted when a telemetry session begins.
  """

  alias Tinkex.Types.Telemetry.{EventType, Severity}

  @type t :: %__MODULE__{
          event: :session_start,
          event_id: String.t(),
          event_session_index: non_neg_integer(),
          severity: Severity.t(),
          timestamp: String.t()
        }

  @enforce_keys [:event_id, :event_session_index, :timestamp]
  defstruct event: :session_start,
            event_id: nil,
            event_session_index: nil,
            severity: :info,
            timestamp: nil

  @doc """
  Create a new SessionStartEvent.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      event: :session_start,
      event_id: Keyword.fetch!(attrs, :event_id),
      event_session_index: Keyword.fetch!(attrs, :event_session_index),
      severity: Keyword.get(attrs, :severity, :info),
      timestamp: Keyword.fetch!(attrs, :timestamp)
    }
  end

  @doc """
  Convert struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "event" => EventType.to_string(:session_start),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => event.timestamp
    }
  end

  @doc """
  Parse wire format map to struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      event: :session_start,
      event_id: map["event_id"],
      event_session_index: map["event_session_index"],
      severity: Severity.parse(map["severity"]) || :info,
      timestamp: map["timestamp"]
    }
  end
end
