defmodule Tinkex.Types.CreateModelRequest do
  @moduledoc """
  Request to create a new model.

  Mirrors Python tinker.types.CreateModelRequest.
  """

  alias Tinkex.Types.LoraConfig

  @enforce_keys [:session_id, :model_seq_id, :base_model]
  @derive {Jason.Encoder,
           only: [:session_id, :model_seq_id, :base_model, :user_metadata, :lora_config, :type]}
  defstruct [
    :session_id,
    :model_seq_id,
    :base_model,
    :user_metadata,
    lora_config: %LoraConfig{},
    type: "create_model"
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          model_seq_id: integer(),
          base_model: String.t(),
          user_metadata: map() | nil,
          lora_config: LoraConfig.t(),
          type: String.t()
        }
end
