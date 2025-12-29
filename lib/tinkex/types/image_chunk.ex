defmodule Tinkex.Types.ImageChunk do
  @moduledoc """
  Image chunk with base64 encoded data.

  Mirrors Python `tinker.types.ImageChunk`.

  ## Fields

  - `data` - Base64-encoded image data
  - `format` - Image format (`:png` or `:jpeg`)
  - `expected_tokens` - Advisory expected token count (optional, required for `.length/1`)
  - `type` - Always "image"

  ## Expected Tokens

  The `expected_tokens` field is advisory. The Tinker backend computes the actual
  token count from the image. If `expected_tokens` is provided and doesn't match,
  the request will fail quickly rather than processing the full request.

  Calling `length/1` will raise if `expected_tokens` is `nil`; this mirrors the
  Python SDK guardrails to avoid silently miscounting tokens.

  ## Wire Format

  ```json
  {
    "data": "base64-encoded-data",
    "format": "png",
    "expected_tokens": 256,
    "type": "image"
  }
  ```

  CRITICAL: Field names are `data` and `format`, NOT `image_data` and `image_format`.
  """

  alias Sinter.Schema

  @enforce_keys [:data, :format]
  defstruct [:data, :format, :expected_tokens, type: "image"]

  @schema Schema.define([
            {:data, :string, [required: true]},
            {:format, :string, [required: true, choices: ["png", "jpeg"]]},
            {:expected_tokens, {:nullable, :integer}, [optional: true]},
            {:type, :string, [optional: true, default: "image"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          data: String.t(),
          format: format(),
          expected_tokens: non_neg_integer() | nil,
          type: String.t()
        }

  @doc """
  Create a new ImageChunk from binary image data.

  Automatically encodes the binary data as base64.

  ## Parameters

  - `image_binary` - Raw image bytes
  - `format` - Image format (`:png` or `:jpeg`)
  - `opts` - Optional keyword list:
    - `:expected_tokens` - Advisory expected token count

  ## Examples

      iex> chunk = ImageChunk.new(<<1, 2, 3>>, :png, expected_tokens: 256)
      iex> chunk.expected_tokens
      256
  """
  @spec new(binary(), format(), keyword()) :: t()
  def new(image_binary, format, opts \\ []) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      expected_tokens: Keyword.get(opts, :expected_tokens),
      type: "image"
    }
  end

  @doc """
  Get the length (number of tokens) consumed by this image.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{expected_tokens: nil}) do
    raise ArgumentError, "expected_tokens is required to compute image length"
  end

  def length(%__MODULE__{expected_tokens: expected_tokens}), do: expected_tokens
end

defimpl Jason.Encoder, for: Tinkex.Types.ImageChunk do
  def encode(chunk, opts) do
    chunk
    |> Tinkex.SchemaCodec.omit_nil_fields([:expected_tokens])
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
