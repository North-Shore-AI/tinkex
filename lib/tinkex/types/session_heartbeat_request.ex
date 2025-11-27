defmodule Tinkex.Types.SessionHeartbeatRequest do
  @moduledoc """
  Request to send a heartbeat for a session.

  Mirrors Python `tinker.types.SessionHeartbeatRequest`.
  """

  @enforce_keys [:session_id]
  defstruct [:session_id, type: "session_heartbeat"]

  @type t :: %__MODULE__{
          session_id: String.t(),
          type: String.t()
        }

  @doc """
  Create a new SessionHeartbeatRequest.
  """
  @spec new(String.t()) :: t()
  def new(session_id) when is_binary(session_id) do
    %__MODULE__{session_id: session_id}
  end

  @doc """
  Convert to JSON-encodable map.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{session_id: session_id, type: type}) do
    %{"session_id" => session_id, "type" => type}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"session_id" => session_id}) do
    %__MODULE__{session_id: session_id}
  end

  def from_json(%{session_id: session_id}) do
    %__MODULE__{session_id: session_id}
  end
end
