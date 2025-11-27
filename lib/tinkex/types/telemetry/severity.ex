defmodule Tinkex.Types.Telemetry.Severity do
  @moduledoc """
  Severity level enumeration for telemetry events.

  Mirrors Python tinker.types.severity.Severity.
  Wire format: `"DEBUG"` | `"INFO"` | `"WARNING"` | `"ERROR"` | `"CRITICAL"`
  """

  @type t :: :debug | :info | :warning | :error | :critical

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | atom() | nil) :: t() | nil
  def parse("DEBUG"), do: :debug
  def parse("INFO"), do: :info
  def parse("WARNING"), do: :warning
  def parse("ERROR"), do: :error
  def parse("CRITICAL"), do: :critical
  def parse(:debug), do: :debug
  def parse(:info), do: :info
  def parse(:warning), do: :warning
  def parse(:error), do: :error
  def parse(:critical), do: :critical
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t() | String.t()) :: String.t()
  def to_string(:debug), do: "DEBUG"
  def to_string(:info), do: "INFO"
  def to_string(:warning), do: "WARNING"
  def to_string(:error), do: "ERROR"
  def to_string(:critical), do: "CRITICAL"
  def to_string(str) when is_binary(str), do: String.upcase(str)

  @doc """
  List all valid severity levels in order of increasing severity.
  """
  @spec values() :: [t()]
  def values, do: [:debug, :info, :warning, :error, :critical]
end
