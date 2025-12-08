defmodule Tinkex.Telemetry.Reporter.Serializer do
  @moduledoc """
  Event serialization and sanitization for telemetry.

  Handles:
    * Converting typed event structs to wire format maps
    * Sanitizing data for JSON serialization (atoms to strings, etc)
    * Platform detection
  """

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent
  }

  @doc """
  Convert a typed event struct to a wire format map.

  Delegates to the appropriate `to_map/1` function based on event type.
  """
  @spec event_to_map(struct() | map()) :: map()
  def event_to_map(%GenericEvent{} = event), do: GenericEvent.to_map(event)
  def event_to_map(%SessionStartEvent{} = event), do: SessionStartEvent.to_map(event)
  def event_to_map(%SessionEndEvent{} = event), do: SessionEndEvent.to_map(event)

  def event_to_map(%UnhandledExceptionEvent{} = event),
    do: UnhandledExceptionEvent.to_map(event)

  def event_to_map(map) when is_map(map), do: map

  @doc """
  Build a telemetry request payload from events and state.

  Returns a map with session_id, platform, sdk_version, and serialized events.
  """
  @spec build_request(list(), map()) :: map()
  def build_request(events, state) do
    # Convert typed structs to wire format maps
    event_maps = Enum.map(events, &event_to_map/1)

    %{
      session_id: state.session_id,
      platform: platform(),
      sdk_version: Tinkex.Version.current(),
      events: event_maps
    }
  end

  @doc """
  Sanitize a value for JSON serialization.

  Converts:
    * Structs to maps (via Map.from_struct)
    * Atoms to strings
    * Lists recursively
    * Maps recursively (keys and values)
    * Numbers, binaries, booleans, nil - pass through
    * Everything else - inspect
  """
  @spec sanitize(term()) :: term()
  def sanitize(%_struct{} = struct), do: struct |> Map.from_struct() |> sanitize()

  def sanitize(map) when is_map(map),
    do: map |> Enum.into(%{}, fn {k, v} -> {to_string(k), sanitize(v)} end)

  def sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  def sanitize(value) when is_atom(value), do: Atom.to_string(value)

  def sanitize(value)
      when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
      do: value

  def sanitize(value), do: inspect(value)

  @doc """
  Get the platform string (os_type/os_flavor).

  Example: "unix/linux"
  """
  @spec platform() :: String.t()
  def platform do
    :os.type()
    |> Tuple.to_list()
    |> Enum.map(&to_string/1)
    |> Enum.join("/")
  end
end
