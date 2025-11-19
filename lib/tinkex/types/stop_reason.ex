defmodule Tinkex.Types.StopReason do
  @moduledoc """
  Stop reason for sampling completion.

  Mirrors Python tinker.types.stop_reason.StopReason.
  Wire format: `"length"` | `"stop"`
  """

  @type t :: :length | :stop

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("length"), do: :length
  def parse("stop"), do: :stop
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:length), do: "length"
  def to_string(:stop), do: "stop"
end
