defmodule Tinkex.Types.SaveWeightsForSamplerRequest do
  @moduledoc """
  Request to save model weights for use in sampling.

  Mirrors Python tinker.types.SaveWeightsForSamplerRequest.
  """

  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]

  @type t :: %__MODULE__{
          model_id: String.t(),
          checkpoint_name: String.t(),
          seq_id: integer() | nil
        }
end
