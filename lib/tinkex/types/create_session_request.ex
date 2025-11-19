defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request to create a new training session.

  Mirrors Python tinker.types.CreateSessionRequest.
  """

  @derive {Jason.Encoder, only: [:user_metadata]}
  defstruct [:user_metadata]

  @type t :: %__MODULE__{
          user_metadata: map() | nil
        }
end
