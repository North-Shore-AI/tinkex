defmodule Tinkex.Types.ImageChunkTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.ImageChunk

  describe "new/3" do
    test "creates chunk with base64 encoded data" do
      binary = "fake_png_data"
      chunk = ImageChunk.new(binary, :png)

      assert chunk.data == Base.encode64(binary)
      assert chunk.format == :png
      assert chunk.type == "image"
      assert chunk.expected_tokens == nil
    end

    test "creates chunk with expected_tokens when provided" do
      binary = "fake_png_data"
      chunk = ImageChunk.new(binary, :png, expected_tokens: 50)

      assert chunk.data == Base.encode64(binary)
      assert chunk.format == :png
      assert chunk.expected_tokens == 50
      assert chunk.type == "image"
    end
  end

  describe "length/1" do
    test "returns expected_tokens" do
      chunk = ImageChunk.new("data", :jpeg, expected_tokens: 42)
      assert ImageChunk.length(chunk) == 42
    end

    test "raises when expected_tokens is nil" do
      chunk = ImageChunk.new("data", :jpeg)

      assert_raise ArgumentError, fn ->
        ImageChunk.length(chunk)
      end
    end
  end

  describe "JSON encoding" do
    test "encodes with correct field names" do
      chunk = ImageChunk.new("test_data", :png)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      # Verify field names match Python SDK exactly
      assert decoded["data"] == Base.encode64("test_data")
      assert decoded["format"] == "png"
      assert decoded["type"] == "image"

      # Ensure we're NOT using wrong field names
      refute Map.has_key?(decoded, "image_data")
      refute Map.has_key?(decoded, "image_format")
      refute Map.has_key?(decoded, "height")
      refute Map.has_key?(decoded, "width")
      refute Map.has_key?(decoded, "tokens")
    end

    test "encodes jpeg format correctly" do
      chunk = ImageChunk.new("jpeg_data", :jpeg)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      assert decoded["format"] == "jpeg"
    end

    test "includes expected_tokens when present" do
      chunk = ImageChunk.new("test_data", :png, expected_tokens: 50)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      assert decoded["expected_tokens"] == 50
    end

    test "excludes expected_tokens when nil" do
      chunk = ImageChunk.new("test_data", :png)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "expected_tokens")
    end
  end
end
