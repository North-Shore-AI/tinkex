defmodule Tinkex.Types.ImageChunkTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.ImageChunk

  describe "new/5" do
    test "creates chunk with base64 encoded data" do
      binary = "fake_png_data"
      chunk = ImageChunk.new(binary, :png, 100, 200, 50)

      assert chunk.data == Base.encode64(binary)
      assert chunk.format == :png
      assert chunk.height == 100
      assert chunk.width == 200
      assert chunk.tokens == 50
      assert chunk.type == "image"
      assert chunk.expected_tokens == nil
    end
  end

  describe "new/6 with options" do
    test "creates chunk with expected_tokens" do
      binary = "fake_png_data"
      chunk = ImageChunk.new(binary, :png, 100, 200, 50, expected_tokens: 50)

      assert chunk.data == Base.encode64(binary)
      assert chunk.format == :png
      assert chunk.height == 100
      assert chunk.width == 200
      assert chunk.tokens == 50
      assert chunk.expected_tokens == 50
      assert chunk.type == "image"
    end

    test "creates chunk without expected_tokens when not provided" do
      chunk = ImageChunk.new("data", :png, 100, 200, 50, [])
      assert chunk.expected_tokens == nil
    end
  end

  describe "length/1" do
    test "returns tokens count" do
      chunk = ImageChunk.new("data", :jpeg, 10, 10, 42)
      assert ImageChunk.length(chunk) == 42
    end
  end

  describe "JSON encoding" do
    test "encodes with correct field names" do
      chunk = ImageChunk.new("test_data", :png, 100, 200, 50)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      # Verify field names match Python SDK exactly
      assert decoded["data"] == Base.encode64("test_data")
      assert decoded["format"] == "png"
      assert decoded["height"] == 100
      assert decoded["width"] == 200
      assert decoded["tokens"] == 50
      assert decoded["type"] == "image"

      # Ensure we're NOT using wrong field names
      refute Map.has_key?(decoded, "image_data")
      refute Map.has_key?(decoded, "image_format")
    end

    test "encodes jpeg format correctly" do
      chunk = ImageChunk.new("jpeg_data", :jpeg, 50, 50, 10)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      assert decoded["format"] == "jpeg"
    end

    test "includes expected_tokens when present" do
      chunk = ImageChunk.new("test_data", :png, 100, 200, 50, expected_tokens: 50)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      assert decoded["expected_tokens"] == 50
    end

    test "excludes expected_tokens when nil" do
      chunk = ImageChunk.new("test_data", :png, 100, 200, 50)
      json = Jason.encode!(chunk)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "expected_tokens")
    end
  end
end
