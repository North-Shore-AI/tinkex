defmodule Tinkex.Types.EncodedTextChunk do
  @moduledoc """
  Encoded text chunk containing token IDs.

  Mirrors Python tinker.types.EncodedTextChunk.
  """

  @enforce_keys [:tokens]
  @derive {Jason.Encoder, only: [:tokens, :type]}
  defstruct [:tokens, type: "encoded_text"]

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
