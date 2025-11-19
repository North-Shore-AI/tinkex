defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request to create a new training session.

  Mirrors Python tinker.types.CreateSessionRequest.
  """

  @derive {Jason.Encoder, only: [:tags, :user_metadata, :sdk_version, :type]}
  defstruct [:tags, :user_metadata, :sdk_version, type: "create_session"]

  @type t :: %__MODULE__{
          tags: [String.t()],
          user_metadata: map() | nil,
          sdk_version: String.t(),
          type: String.t()
        }
end
