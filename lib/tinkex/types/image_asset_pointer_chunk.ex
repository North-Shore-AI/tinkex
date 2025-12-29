defmodule Tinkex.Types.ImageAssetPointerChunk do
  @moduledoc """
  Reference to a pre-uploaded image asset.

  Mirrors Python tinker.types.ImageAssetPointerChunk.

  CRITICAL: Field name is `location`, NOT `asset_id`.

  The `expected_tokens` field is advisory. The backend computes the real token
  count and will reject mismatches. Calling `length/1` will raise if
  `expected_tokens` is `nil`.
  """

  alias Sinter.Schema

  @enforce_keys [:location, :format]
  defstruct [:location, :format, :expected_tokens, type: "image_asset_pointer"]

  @schema Schema.define([
            {:location, :string, [required: true]},
            {:format, :string, [required: true, choices: ["png", "jpeg"]]},
            {:expected_tokens, {:nullable, :integer}, [optional: true]},
            {:type, :string, [optional: true, default: "image_asset_pointer"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          location: String.t(),
          format: format(),
          expected_tokens: non_neg_integer() | nil,
          type: String.t()
        }

  @doc """
  Get the length (number of tokens) consumed by this image reference.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{expected_tokens: nil}) do
    raise ArgumentError, "expected_tokens is required to compute image asset pointer length"
  end

  def length(%__MODULE__{expected_tokens: expected_tokens}), do: expected_tokens
end

defimpl Jason.Encoder, for: Tinkex.Types.ImageAssetPointerChunk do
  def encode(chunk, opts) do
    chunk
    |> Tinkex.SchemaCodec.omit_nil_fields([:expected_tokens])
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
