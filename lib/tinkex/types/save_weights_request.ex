defmodule Tinkex.Types.SaveWeightsRequest do
  @moduledoc """
  Request to save model weights as a checkpoint.

  Mirrors Python tinker.types.SaveWeightsRequest.
  """

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :ttl_seconds, :type]}
  defstruct [:model_id, :path, :seq_id, :ttl_seconds, type: "save_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          seq_id: integer() | nil,
          ttl_seconds: pos_integer() | nil,
          type: String.t()
        }
end
