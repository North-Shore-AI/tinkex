defmodule Tinkex.Types.OptimStepRequest do
  @moduledoc """
  Request for optimizer step.

  Mirrors Python tinker.types.OptimStepRequest.
  """

  alias Tinkex.Types.AdamParams

  @derive {Jason.Encoder, only: [:adam_params, :model_id, :seq_id]}
  defstruct [:adam_params, :model_id, :seq_id]

  @type t :: %__MODULE__{
          adam_params: AdamParams.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
