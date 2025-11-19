defmodule Tinkex.Types.ForwardBackwardRequest do
  @moduledoc """
  Request for forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardRequest.
  """

  alias Tinkex.Types.ForwardBackwardInput

  @enforce_keys [:forward_backward_input, :model_id]
  @derive {Jason.Encoder, only: [:forward_backward_input, :model_id, :seq_id]}
  defstruct [:forward_backward_input, :model_id, :seq_id]

  @type t :: %__MODULE__{
          forward_backward_input: ForwardBackwardInput.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
