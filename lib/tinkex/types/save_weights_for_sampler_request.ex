defmodule Tinkex.Types.SaveWeightsForSamplerRequest do
  @moduledoc """
  Request to save model weights for use in sampling.

  Mirrors Python tinker.types.SaveWeightsForSamplerRequest.
  """

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :path, :sampling_session_seq_id, :seq_id, :type]}
  defstruct [:model_id, :path, :sampling_session_seq_id, :seq_id, type: "save_weights_for_sampler"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          sampling_session_seq_id: integer() | nil,
          seq_id: integer() | nil,
          type: String.t()
        }
end
