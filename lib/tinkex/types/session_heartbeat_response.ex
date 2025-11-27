defmodule Tinkex.Types.SessionHeartbeatResponse do
  @moduledoc """
  Response to a session heartbeat request.

  Mirrors Python `tinker.types.SessionHeartbeatResponse`.
  """

  defstruct type: "session_heartbeat"

  @type t :: %__MODULE__{
          type: String.t()
        }

  @doc """
  Create a new SessionHeartbeatResponse.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"type" => "session_heartbeat"}), do: new()
  def from_json(%{type: "session_heartbeat"}), do: new()
  def from_json(_), do: new()
end
