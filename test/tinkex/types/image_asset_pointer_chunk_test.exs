defmodule Tinkex.Types.ImageAssetPointerChunkTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.ImageAssetPointerChunk

  describe "JSON encoding" do
    test "encodes with correct field names" do
      chunk = %ImageAssetPointerChunk{
        location: "s3://bucket/path/image.png",
        format: :png,
        expected_tokens: 50,
        type: "image_asset_pointer"
      }

      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      # Verify field names match Python SDK exactly
      assert decoded["location"] == "s3://bucket/path/image.png"
      assert decoded["format"] == "png"
      assert decoded["expected_tokens"] == 50
      assert decoded["type"] == "image_asset_pointer"

      # Ensure we're NOT using wrong field names
      refute Map.has_key?(decoded, "asset_id")
      refute Map.has_key?(decoded, "url")
      refute Map.has_key?(decoded, "height")
      refute Map.has_key?(decoded, "width")
      refute Map.has_key?(decoded, "tokens")
    end

    test "omits expected_tokens when nil" do
      chunk = %ImageAssetPointerChunk{
        location: "asset://p",
        format: :jpeg,
        type: "image_asset_pointer"
      }

      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "expected_tokens")
    end
  end

  describe "length/1" do
    test "returns expected_tokens" do
      chunk = %ImageAssetPointerChunk{
        location: "test",
        format: :jpeg,
        expected_tokens: 42,
        type: "image_asset_pointer"
      }

      assert ImageAssetPointerChunk.length(chunk) == 42
    end

    test "raises when expected_tokens is nil" do
      chunk = %ImageAssetPointerChunk{
        location: "test",
        format: :jpeg,
        type: "image_asset_pointer"
      }

      assert_raise ArgumentError, fn ->
        ImageAssetPointerChunk.length(chunk)
      end
    end
  end
end
