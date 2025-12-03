defmodule Tinkex.Types.ImageAssetPointerChunk do
  @moduledoc """
  Reference to a pre-uploaded image asset.

  Mirrors Python tinker.types.ImageAssetPointerChunk.

  CRITICAL: Field name is `location`, NOT `asset_id`.

  The `expected_tokens` field is advisory. The backend computes the real token
  count and will reject mismatches. Calling `length/1` will raise if
  `expected_tokens` is `nil`.
  """

  @enforce_keys [:location, :format]
  defstruct [:location, :format, :expected_tokens, type: "image_asset_pointer"]

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
    format_str = Atom.to_string(chunk.format)

    %{
      location: chunk.location,
      format: format_str,
      expected_tokens: chunk.expected_tokens,
      type: chunk.type
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end
