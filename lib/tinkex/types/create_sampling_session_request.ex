defmodule Tinkex.Types.CreateSamplingSessioNRequest do
  @moduledoc """
  Request to create a new sampling session.

  Mirrors Python tinker.types.CreateSamplingSessionRequest.
  """

  @derive {Jason.Encoder, only: [:base_model, :model_path, :user_metadata]}
  defstruct [:base_model, :model_path, :user_metadata]

  @type t :: %__MODULE__{
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          user_metadata: map() | nil
        }
end
