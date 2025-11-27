defmodule Tinkex.Types.TelemetryResponse do
  @moduledoc """
  Response to a telemetry send request.

  Mirrors Python `tinker.types.TelemetryResponse`.
  """

  defstruct status: "accepted"

  @type status :: :accepted

  @type t :: %__MODULE__{
          status: String.t()
        }

  @doc """
  Create a new TelemetryResponse.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{status: "accepted"}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"status" => "accepted"}), do: new()
  def from_json(%{status: "accepted"}), do: new()
  def from_json(_), do: new()
end
