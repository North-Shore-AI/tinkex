defmodule Tinkex.Types.SamplingParams do
  @moduledoc """
  Parameters for text generation/sampling.

  Mirrors Python tinker.types.SamplingParams.
  """

  @derive {Jason.Encoder, only: [:max_tokens, :seed, :stop, :temperature, :top_k, :top_p]}
  defstruct [
    :max_tokens,
    :seed,
    :stop,
    temperature: 1.0,
    top_k: -1,
    top_p: 1.0
  ]

  @type t :: %__MODULE__{
          max_tokens: non_neg_integer() | nil,
          seed: integer() | nil,
          stop: String.t() | [String.t()] | [integer()] | nil,
          temperature: float(),
          top_k: integer(),
          top_p: float()
        }
end
