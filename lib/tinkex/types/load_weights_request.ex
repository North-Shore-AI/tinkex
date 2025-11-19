defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  Mirrors Python tinker.types.LoadWeightsRequest.
  """

  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]

  @type t :: %__MODULE__{
          model_id: String.t(),
          checkpoint_name: String.t(),
          seq_id: integer() | nil
        }
end
