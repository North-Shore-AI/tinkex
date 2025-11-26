defmodule Tinkex.Types.ImageChunk do
  @moduledoc """
  Image chunk with base64 encoded data.

  Mirrors Python `tinker.types.ImageChunk`.

  ## Fields

  - `data` - Base64-encoded image data
  - `format` - Image format (`:png` or `:jpeg`)
  - `height` - Image height in pixels
  - `width` - Image width in pixels
  - `tokens` - Number of tokens this image represents
  - `expected_tokens` - Advisory expected token count (optional)
  - `type` - Always "image"

  ## Expected Tokens

  The `expected_tokens` field is advisory. The Tinker backend computes the actual
  token count from the image. If `expected_tokens` is provided and doesn't match,
  the request will fail quickly rather than processing the full request.

  ## Wire Format

  ```json
  {
    "data": "base64-encoded-data",
    "format": "png",
    "height": 512,
    "width": 512,
    "tokens": 256,
    "expected_tokens": 256,
    "type": "image"
  }
  ```

  CRITICAL: Field names are `data` and `format`, NOT `image_data` and `image_format`.
  """

  @enforce_keys [:data, :format, :height, :width, :tokens]
  defstruct [:data, :format, :height, :width, :tokens, :expected_tokens, type: "image"]

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          data: String.t(),
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          expected_tokens: non_neg_integer() | nil,
          type: String.t()
        }

  @doc """
  Create a new ImageChunk from binary image data.

  Automatically encodes the binary data as base64.

  ## Parameters

  - `image_binary` - Raw image bytes
  - `format` - Image format (`:png` or `:jpeg`)
  - `height` - Image height in pixels
  - `width` - Image width in pixels
  - `tokens` - Number of tokens this image represents
  - `opts` - Optional keyword list:
    - `:expected_tokens` - Advisory expected token count

  ## Examples

      iex> chunk = ImageChunk.new(<<1, 2, 3>>, :png, 512, 512, 256)
      iex> chunk.tokens
      256

      iex> chunk = ImageChunk.new(<<1, 2, 3>>, :png, 512, 512, 256, expected_tokens: 256)
      iex> chunk.expected_tokens
      256
  """
  @spec new(binary(), format(), pos_integer(), pos_integer(), non_neg_integer(), keyword()) :: t()
  def new(image_binary, format, height, width, tokens, opts \\ []) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      height: height,
      width: width,
      tokens: tokens,
      expected_tokens: Keyword.get(opts, :expected_tokens),
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

    base_map = %{
      data: chunk.data,
      format: format_str,
      height: chunk.height,
      width: chunk.width,
      tokens: chunk.tokens,
      type: chunk.type
    }

    map =
      if chunk.expected_tokens do
        Map.put(base_map, :expected_tokens, chunk.expected_tokens)
      else
        base_map
      end

    Jason.Encode.map(map, opts)
  end
end
