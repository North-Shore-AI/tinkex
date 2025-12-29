defmodule Tinkex.Types.LoraConfig do
  @moduledoc """
  LoRA configuration for model fine-tuning.

  Mirrors Python tinker.types.LoraConfig.
  """

  alias Sinter.Schema

  @derive {Jason.Encoder, only: [:rank, :seed, :train_mlp, :train_attn, :train_unembed]}
  defstruct rank: 32,
            seed: nil,
            train_mlp: true,
            train_attn: true,
            train_unembed: true

  @schema Schema.define([
            {:rank, :integer, [optional: true, default: 32]},
            {:seed, :integer, [optional: true]},
            {:train_mlp, :boolean, [optional: true, default: true]},
            {:train_attn, :boolean, [optional: true, default: true]},
            {:train_unembed, :boolean, [optional: true, default: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          rank: pos_integer(),
          seed: integer() | nil,
          train_mlp: boolean(),
          train_attn: boolean(),
          train_unembed: boolean()
        }
end
