defmodule Tinkex.Types.CreateSessionResponse do
  @moduledoc """
  Response from create session request.

  Mirrors Python tinker.types.CreateSessionResponse.
  """

  @enforce_keys [:session_id]
  defstruct [:session_id, :info_message, :warning_message, :error_message]

  @type t :: %__MODULE__{
          session_id: String.t(),
          info_message: String.t() | nil,
          warning_message: String.t() | nil,
          error_message: String.t() | nil
        }

  @doc """
  Parse a create session response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      session_id: json["session_id"],
      info_message: json["info_message"],
      warning_message: json["warning_message"],
      error_message: json["error_message"]
    }
  end
end
