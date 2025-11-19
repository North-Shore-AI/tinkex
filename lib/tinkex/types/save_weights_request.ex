defmodule Tinkex.Types.SaveWeightsRequest do
  @moduledoc """
  Request to save model weights as a checkpoint.

  Mirrors Python tinker.types.SaveWeightsRequest.
  """

  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :type]}
  defstruct [:model_id, :path, :seq_id, type: "save_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          seq_id: integer() | nil,
          type: String.t()
        }
end
