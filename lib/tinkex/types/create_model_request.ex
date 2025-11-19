defmodule Tinkex.Types.CreateModelRequest do
  @moduledoc """
  Request to create a new model.

  Mirrors Python tinker.types.CreateModelRequest.
  """

  alias Tinkex.Types.LoraConfig

  @derive {Jason.Encoder, only: [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata]}
  defstruct [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata]

  @type t :: %__MODULE__{
          session_id: String.t(),
          model_seq_id: integer(),
          base_model: String.t(),
          lora_config: LoraConfig.t(),
          user_metadata: map() | nil
        }
end
