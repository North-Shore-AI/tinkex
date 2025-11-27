defmodule Tinkex.Types.Telemetry.UnhandledExceptionEvent do
  @moduledoc """
  Unhandled exception telemetry event.

  Mirrors Python tinker.types.unhandled_exception_event.UnhandledExceptionEvent.
  Emitted when an unhandled exception occurs.
  """

  alias Tinkex.Types.Telemetry.{EventType, Severity}

  @type t :: %__MODULE__{
          event: :unhandled_exception,
          event_id: String.t(),
          event_session_index: non_neg_integer(),
          severity: Severity.t(),
          timestamp: String.t(),
          error_type: String.t(),
          error_message: String.t(),
          traceback: String.t() | nil
        }

  @enforce_keys [:event_id, :event_session_index, :timestamp, :error_type, :error_message]
  defstruct event: :unhandled_exception,
            event_id: nil,
            event_session_index: nil,
            severity: :error,
            timestamp: nil,
            error_type: nil,
            error_message: nil,
            traceback: nil

  @doc """
  Create a new UnhandledExceptionEvent.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      event: :unhandled_exception,
      event_id: Keyword.fetch!(attrs, :event_id),
      event_session_index: Keyword.fetch!(attrs, :event_session_index),
      severity: Keyword.get(attrs, :severity, :error),
      timestamp: Keyword.fetch!(attrs, :timestamp),
      error_type: Keyword.fetch!(attrs, :error_type),
      error_message: Keyword.fetch!(attrs, :error_message),
      traceback: Keyword.get(attrs, :traceback)
    }
  end

  @doc """
  Convert struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    base = %{
      "event" => EventType.to_string(:unhandled_exception),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => event.timestamp,
      "error_type" => event.error_type,
      "error_message" => event.error_message
    }

    if event.traceback do
      Map.put(base, "traceback", event.traceback)
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
      event: :unhandled_exception,
      event_id: map["event_id"],
      event_session_index: map["event_session_index"],
      severity: Severity.parse(map["severity"]) || :error,
      timestamp: map["timestamp"],
      error_type: map["error_type"],
      error_message: map["error_message"],
      traceback: map["traceback"]
    }
  end
end
