defmodule Tinkex.Types.SamplingParams do
  @moduledoc """
  Parameters for text generation/sampling.

  Mirrors Python tinker.types.SamplingParams.
  """

  alias Sinter.Schema

  @derive {Jason.Encoder, only: [:max_tokens, :seed, :stop, :temperature, :top_k, :top_p]}
  defstruct [
    :max_tokens,
    :seed,
    :stop,
    temperature: 1.0,
    top_k: -1,
    top_p: 1.0
  ]

  @schema Schema.define([
            {:max_tokens, :integer, [optional: true]},
            {:seed, :integer, [optional: true]},
            {:stop,
             {:nullable,
              {:union,
               [
                 :string,
                 {:array, :string},
                 {:array, :integer}
               ]}}, [optional: true]},
            {:temperature, :float, [optional: true, default: 1.0]},
            {:top_k, :integer, [optional: true, default: -1]},
            {:top_p, :float, [optional: true, default: 1.0]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          max_tokens: non_neg_integer() | nil,
          seed: integer() | nil,
          stop: String.t() | [String.t()] | [integer()] | nil,
          temperature: float(),
          top_k: integer(),
          top_p: float()
        }
end
