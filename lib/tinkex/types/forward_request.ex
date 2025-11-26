defmodule Tinkex.Types.ForwardRequest do
  @moduledoc """
  Request for forward-only pass (inference without backward).

  Uses `forward_input` field as expected by the `/api/v1/forward` endpoint.
  """

  alias Tinkex.Types.ForwardBackwardInput

  @enforce_keys [:forward_input, :model_id]
  @derive {Jason.Encoder, only: [:forward_input, :model_id, :seq_id]}
  defstruct [:forward_input, :model_id, :seq_id]

  @type t :: %__MODULE__{
          forward_input: ForwardBackwardInput.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
