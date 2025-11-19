defmodule Tinkex.Types.ImageChunk do
  @moduledoc """
  Image chunk with base64 encoded data.

  Mirrors Python tinker.types.ImageChunk.

  CRITICAL: Field names are `data` and `format`, NOT `image_data` and `image_format`.
  """

  @enforce_keys [:data, :format, :height, :width, :tokens]
  defstruct [:data, :format, :height, :width, :tokens, type: "image"]

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          data: String.t(),
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          type: String.t()
        }

  @doc """
  Create a new ImageChunk from binary image data.

  Automatically encodes the binary data as base64.
  """
  @spec new(binary(), format(), pos_integer(), pos_integer(), non_neg_integer()) :: t()
  def new(image_binary, format, height, width, tokens) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      height: height,
      width: width,
      tokens: tokens,
      type: "image"
    }
  end

  @doc """
  Get the length (number of tokens) consumed by this image.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: tokens
end

defimpl Jason.Encoder, for: Tinkex.Types.ImageChunk do
  def encode(chunk, opts) do
    format_str = Atom.to_string(chunk.format)

    %{
      data: chunk.data,
      format: format_str,
      height: chunk.height,
      width: chunk.width,
      tokens: chunk.tokens,
      type: chunk.type
    }
    |> Jason.Encode.map(opts)
  end
end
