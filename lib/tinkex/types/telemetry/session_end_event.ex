defmodule Tinkex.Types.Telemetry.SessionEndEvent do
  @moduledoc """
  Session end telemetry event.

  Mirrors Python tinker.types.session_end_event.SessionEndEvent.
  Emitted when a telemetry session ends.
  """

  alias Tinkex.Types.Telemetry.{EventType, Severity}

  @type t :: %__MODULE__{
          event: :session_end,
          event_id: String.t(),
          event_session_index: non_neg_integer(),
          severity: Severity.t(),
          timestamp: String.t(),
          duration: String.t() | nil
        }

  @enforce_keys [:event_id, :event_session_index, :timestamp]
  defstruct event: :session_end,
            event_id: nil,
            event_session_index: nil,
            severity: :info,
            timestamp: nil,
            duration: nil

  @doc """
  Create a new SessionEndEvent.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      event: :session_end,
      event_id: Keyword.fetch!(attrs, :event_id),
      event_session_index: Keyword.fetch!(attrs, :event_session_index),
      severity: Keyword.get(attrs, :severity, :info),
      timestamp: Keyword.fetch!(attrs, :timestamp),
      duration: Keyword.get(attrs, :duration)
    }
  end

  @doc """
  Convert struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    base = %{
      "event" => EventType.to_string(:session_end),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => event.timestamp
    }

    if event.duration do
      Map.put(base, "duration", event.duration)
    else
      base
    end
  end

  @doc """
  Parse wire format map to struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      event: :session_end,
      event_id: map["event_id"],
      event_session_index: map["event_session_index"],
      severity: Severity.parse(map["severity"]) || :info,
      timestamp: map["timestamp"],
      duration: map["duration"]
    }
  end
end
