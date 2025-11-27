defmodule Tinkex.Types.Telemetry.TelemetryEvent do
  @moduledoc """
  Union type for telemetry events.

  Mirrors Python tinker.types.telemetry_event.TelemetryEvent.
  Can be one of: GenericEvent, SessionStartEvent, SessionEndEvent, UnhandledExceptionEvent.
  """

  alias Tinkex.Types.Telemetry.{
    EventType,
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent
  }

  @type t ::
          GenericEvent.t()
          | SessionStartEvent.t()
          | SessionEndEvent.t()
          | UnhandledExceptionEvent.t()

  @doc """
  Convert a telemetry event struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%GenericEvent{} = event), do: GenericEvent.to_map(event)
  def to_map(%SessionStartEvent{} = event), do: SessionStartEvent.to_map(event)
  def to_map(%SessionEndEvent{} = event), do: SessionEndEvent.to_map(event)
  def to_map(%UnhandledExceptionEvent{} = event), do: UnhandledExceptionEvent.to_map(event)

  @doc """
  Parse wire format map to appropriate struct based on event type.
  """
  @spec from_map(map()) :: t() | nil
  def from_map(%{"event" => event_type} = map) do
    case EventType.parse(event_type) do
      :generic_event -> GenericEvent.from_map(map)
      :session_start -> SessionStartEvent.from_map(map)
      :session_end -> SessionEndEvent.from_map(map)
      :unhandled_exception -> UnhandledExceptionEvent.from_map(map)
      nil -> nil
    end
  end

  def from_map(_), do: nil

  @doc """
  Get the event type of a telemetry event.
  """
  @spec event_type(t()) :: EventType.t()
  def event_type(%GenericEvent{}), do: :generic_event
  def event_type(%SessionStartEvent{}), do: :session_start
  def event_type(%SessionEndEvent{}), do: :session_end
  def event_type(%UnhandledExceptionEvent{}), do: :unhandled_exception
end
