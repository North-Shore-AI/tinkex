defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request to create a new training session.

  Mirrors Python tinker.types.CreateSessionRequest.
  """

  @enforce_keys [:tags, :sdk_version]
  @derive {Jason.Encoder, only: [:tags, :user_metadata, :sdk_version, :project_id, :type]}
  defstruct [:tags, :user_metadata, :sdk_version, :project_id, type: "create_session"]

  @type t :: %__MODULE__{
          tags: [String.t()],
          user_metadata: map() | nil,
          sdk_version: String.t(),
          project_id: String.t() | nil,
          type: String.t()
        }
end
