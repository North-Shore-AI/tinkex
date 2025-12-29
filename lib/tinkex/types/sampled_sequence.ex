defmodule Tinkex.Types.SampledSequence do
  @moduledoc """
  A single sampled sequence from text generation.

  Mirrors Python tinker.types.SampledSequence.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.StopReason

  @enforce_keys [:tokens]
  defstruct [:tokens, :logprobs, :stop_reason]

  @schema Schema.define([
            {:tokens, {:array, :integer}, [required: true]},
            {:logprobs, {:nullable, {:array, :float}}, [optional: true]},
            {:stop_reason, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          tokens: [integer()],
          logprobs: [float()] | nil,
          stop_reason: StopReason.t() | nil
        }

  @doc """
  Parse a sampled sequence from JSON response.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__),
      coerce: true,
      converters: %{stop_reason: &StopReason.parse/1}
    )
  end
end
