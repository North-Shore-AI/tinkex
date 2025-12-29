defmodule Tinkex.Types.EncodedTextChunk do
  @moduledoc """
  Encoded text chunk containing token IDs.

  Mirrors Python tinker.types.EncodedTextChunk.
  """

  alias Sinter.Schema

  @enforce_keys [:tokens]
  defstruct [:tokens, type: "encoded_text"]

  @schema Schema.define([
            {:tokens, {:array, :integer}, [required: true]},
            {:type, :string, [optional: true, default: "encoded_text"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          tokens: [integer()],
          type: String.t()
        }

  @doc """
  Get the length (number of tokens) in this chunk.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: Kernel.length(tokens)
end

defimpl Jason.Encoder, for: Tinkex.Types.EncodedTextChunk do
  def encode(chunk, opts) do
    chunk
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
