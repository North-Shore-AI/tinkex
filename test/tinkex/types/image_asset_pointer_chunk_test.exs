defmodule Tinkex.Types.ImageAssetPointerChunkTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.ImageAssetPointerChunk

  describe "JSON encoding" do
    test "encodes with correct field names" do
      chunk = %ImageAssetPointerChunk{
        location: "s3://bucket/path/image.png",
        format: :png,
        height: 100,
        width: 200,
        tokens: 50,
        type: "image_asset_pointer"
      }

      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      # Verify field names match Python SDK exactly
      assert decoded["location"] == "s3://bucket/path/image.png"
      assert decoded["format"] == "png"
      assert decoded["height"] == 100
      assert decoded["width"] == 200
      assert decoded["tokens"] == 50
      assert decoded["type"] == "image_asset_pointer"

      # Ensure we're NOT using wrong field names
      refute Map.has_key?(decoded, "asset_id")
      refute Map.has_key?(decoded, "url")
    end
  end

  describe "length/1" do
    test "returns tokens count" do
      chunk = %ImageAssetPointerChunk{
        location: "test",
        format: :jpeg,
        height: 10,
        width: 10,
        tokens: 42,
        type: "image_asset_pointer"
      }

      assert ImageAssetPointerChunk.length(chunk) == 42
    end
  end
end
