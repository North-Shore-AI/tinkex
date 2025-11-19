defmodule Tinkex.Types.SaveWeightsRequest do
  @moduledoc """
  Request to save model weights as a checkpoint.

  Mirrors Python tinker.types.SaveWeightsRequest.
  """

  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]

  @type t :: %__MODULE__{
          model_id: String.t(),
          checkpoint_name: String.t(),
          seq_id: integer() | nil
        }
end
