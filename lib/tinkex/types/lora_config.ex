defmodule Tinkex.Types.LoraConfig do
  @moduledoc """
  LoRA configuration for model fine-tuning.

  Mirrors Python tinker.types.LoraConfig.
  """

  @derive {Jason.Encoder, only: [:rank, :seed, :train_mlp, :train_attn, :train_unembed]}
  defstruct rank: 32,
            seed: nil,
            train_mlp: true,
            train_attn: true,
            train_unembed: true

  @type t :: %__MODULE__{
          rank: pos_integer(),
          seed: integer() | nil,
          train_mlp: boolean(),
          train_attn: boolean(),
          train_unembed: boolean()
        }
end
