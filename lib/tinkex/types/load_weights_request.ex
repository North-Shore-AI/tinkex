defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  Mirrors Python tinker.types.LoadWeightsRequest.
  """

  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :type]}
  defstruct [:model_id, :path, :seq_id, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          type: String.t()
        }
end
