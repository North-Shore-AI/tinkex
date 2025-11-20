defmodule Tinkex.Types.ModelInput do
  @moduledoc """
  Model input containing chunks of encoded text and/or images.

  Mirrors Python tinker.types.ModelInput.
  """

  alias Tinkex.Types.EncodedTextChunk

  @derive {Jason.Encoder, only: [:chunks]}
  defstruct chunks: []

  @type chunk ::
          EncodedTextChunk.t()
          | Tinkex.Types.ImageChunk.t()
          | Tinkex.Types.ImageAssetPointerChunk.t()
  @type t :: %__MODULE__{
          chunks: [chunk()]
        }

  @doc """
  Create ModelInput from a list of token IDs.
  """
  @spec from_ints([integer()]) :: t()
  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
    }
  end

  @doc """
  Extract all token IDs from the ModelInput.

  Only works with EncodedTextChunk chunks. Raises for image chunks.
  """
  @spec to_ints(t()) :: [integer()]
  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %EncodedTextChunk{tokens: tokens} -> tokens
      _ -> raise ArgumentError, "Cannot convert non-text chunk to ints"
    end)
  end

  @doc """
  Get the total length (token count) of the ModelInput.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, &chunk_length/1))
  end

  defp chunk_length(%EncodedTextChunk{} = chunk), do: EncodedTextChunk.length(chunk)
  defp chunk_length(%Tinkex.Types.ImageChunk{} = chunk), do: Tinkex.Types.ImageChunk.length(chunk)

  defp chunk_length(%Tinkex.Types.ImageAssetPointerChunk{} = chunk),
    do: Tinkex.Types.ImageAssetPointerChunk.length(chunk)
end
