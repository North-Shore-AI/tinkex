defmodule Tinkex.Types.CreateSamplingSessionRequest do
  @moduledoc """
  Request to create a new sampling session.

  Mirrors Python tinker.types.CreateSamplingSessionRequest.
  """

  @enforce_keys [:session_id, :sampling_session_seq_id]
  @derive {Jason.Encoder, only: [:session_id, :sampling_session_seq_id, :base_model, :model_path, :type]}
  defstruct [:session_id, :sampling_session_seq_id, :base_model, :model_path, type: "create_sampling_session"]

  @type t :: %__MODULE__{
          session_id: String.t(),
          sampling_session_seq_id: integer(),
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          type: String.t()
        }
end
