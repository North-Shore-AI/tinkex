defmodule Tinkex.Types.ImageAssetPointerChunk do
  @moduledoc """
  Reference to a pre-uploaded image asset.

  Mirrors Python tinker.types.ImageAssetPointerChunk.

  CRITICAL: Field name is `location`, NOT `asset_id`.
  """

  @enforce_keys [:location, :format, :height, :width, :tokens]
  defstruct [:location, :format, :height, :width, :tokens, type: "image_asset_pointer"]

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          location: String.t(),
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          type: String.t()
        }

  @doc """
  Get the length (number of tokens) consumed by this image reference.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: tokens
end

defimpl Jason.Encoder, for: Tinkex.Types.ImageAssetPointerChunk do
  def encode(chunk, opts) do
    format_str = Atom.to_string(chunk.format)

    %{
      location: chunk.location,
      format: format_str,
      height: chunk.height,
      width: chunk.width,
      tokens: chunk.tokens,
      type: chunk.type
    }
    |> Jason.Encode.map(opts)
  end
end
