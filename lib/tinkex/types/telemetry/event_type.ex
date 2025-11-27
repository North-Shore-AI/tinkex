defmodule Tinkex.Types.Telemetry.EventType do
  @moduledoc """
  Event type enumeration for telemetry events.

  Mirrors Python tinker.types.event_type.EventType.
  Wire format: `"SESSION_START"` | `"SESSION_END"` | `"UNHANDLED_EXCEPTION"` | `"GENERIC_EVENT"`
  """

  @type t :: :session_start | :session_end | :unhandled_exception | :generic_event

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("SESSION_START"), do: :session_start
  def parse("SESSION_END"), do: :session_end
  def parse("UNHANDLED_EXCEPTION"), do: :unhandled_exception
  def parse("GENERIC_EVENT"), do: :generic_event
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:session_start), do: "SESSION_START"
  def to_string(:session_end), do: "SESSION_END"
  def to_string(:unhandled_exception), do: "UNHANDLED_EXCEPTION"
  def to_string(:generic_event), do: "GENERIC_EVENT"

  @doc """
  List all valid event types.
  """
  @spec values() :: [t()]
  def values, do: [:session_start, :session_end, :unhandled_exception, :generic_event]
end
