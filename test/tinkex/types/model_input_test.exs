defmodule Tinkex.Types.ModelInputTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{EncodedTextChunk, ImageChunk, ImageAssetPointerChunk, ModelInput}

  describe "empty/0" do
    test "creates ModelInput with empty chunks list" do
      assert %ModelInput{chunks: []} = ModelInput.empty()
    end
  end

  describe "append/2" do
    test "appends text chunk to empty input" do
      input = ModelInput.empty()
      chunk = %EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"}
      result = ModelInput.append(input, chunk)

      assert %ModelInput{chunks: [^chunk]} = result
    end

    test "appends multiple chunks" do
      chunk1 = %EncodedTextChunk{tokens: [1, 2], type: "encoded_text"}
      chunk2 = %EncodedTextChunk{tokens: [3, 4], type: "encoded_text"}

      result =
        ModelInput.empty()
        |> ModelInput.append(chunk1)
        |> ModelInput.append(chunk2)

      assert %ModelInput{chunks: [^chunk1, ^chunk2]} = result
    end

    test "appends image chunk" do
      input = ModelInput.from_ints([1, 2])
      image_chunk = ImageChunk.new("base64data", :png, expected_tokens: 10)
      result = ModelInput.append(input, image_chunk)

      assert length(result.chunks) == 2
      assert hd(tl(result.chunks)) == image_chunk
    end
  end

  describe "append_int/2" do
    test "appends token to empty input creating new EncodedTextChunk" do
      result = ModelInput.empty() |> ModelInput.append_int(42)

      assert %ModelInput{chunks: [%EncodedTextChunk{tokens: [42]}]} = result
    end

    test "extends last EncodedTextChunk tokens" do
      result =
        ModelInput.from_ints([1, 2])
        |> ModelInput.append_int(3)

      assert ModelInput.to_ints(result) == [1, 2, 3]
    end

    test "appends multiple tokens sequentially" do
      result =
        ModelInput.empty()
        |> ModelInput.append_int(1)
        |> ModelInput.append_int(2)
        |> ModelInput.append_int(3)

      assert ModelInput.to_ints(result) == [1, 2, 3]
      # Should still be a single chunk
      assert length(result.chunks) == 1
    end

    test "creates new EncodedTextChunk after image chunk" do
      image_chunk = ImageChunk.new("data", :png, expected_tokens: 5)

      result =
        ModelInput.empty()
        |> ModelInput.append(image_chunk)
        |> ModelInput.append_int(42)

      assert length(result.chunks) == 2
      assert [^image_chunk, %EncodedTextChunk{tokens: [42]}] = result.chunks
    end

    test "token concatenation preserves earlier chunks" do
      chunk1 = %EncodedTextChunk{tokens: [1, 2], type: "encoded_text"}
      image = ImageChunk.new("img", :png, expected_tokens: 3)

      result =
        ModelInput.empty()
        |> ModelInput.append(chunk1)
        |> ModelInput.append(image)
        |> ModelInput.append_int(99)

      assert length(result.chunks) == 3
      assert [^chunk1, ^image, %EncodedTextChunk{tokens: [99]}] = result.chunks
    end
  end

  describe "from_ints/1" do
    test "creates ModelInput from token list" do
      tokens = [1, 2, 3, 4, 5]
      model_input = ModelInput.from_ints(tokens)

      assert %ModelInput{chunks: [%EncodedTextChunk{tokens: ^tokens}]} = model_input
    end
  end

  describe "to_ints/1" do
    test "extracts tokens from ModelInput" do
      tokens = [1, 2, 3]
      model_input = ModelInput.from_ints(tokens)

      assert ModelInput.to_ints(model_input) == tokens
    end
  end

  describe "length/1" do
    test "returns total token count" do
      model_input = ModelInput.from_ints([1, 2, 3])
      assert ModelInput.length(model_input) == 3
    end

    test "sums encoded text and image chunks when expected_tokens provided" do
      model_input = %ModelInput{
        chunks: [
          %EncodedTextChunk{tokens: [1, 2], type: "encoded_text"},
          ImageChunk.new("img", :png, expected_tokens: 5),
          %ImageAssetPointerChunk{location: "tinker://asset", format: :jpeg, expected_tokens: 7}
        ]
      }

      assert ModelInput.length(model_input) == 14
    end

    test "raises when image chunk lacks expected_tokens" do
      model_input = %ModelInput{
        chunks: [
          %EncodedTextChunk{tokens: [1], type: "encoded_text"},
          ImageChunk.new("img", :png)
        ]
      }

      assert_raise ArgumentError, fn ->
        ModelInput.length(model_input)
      end
    end
  end

  describe "JSON encoding" do
    test "encodes correctly" do
      model_input = ModelInput.from_ints([1, 2, 3])
      json = Jason.encode!(model_input)
      decoded = Jason.decode!(json)

      assert is_list(decoded["chunks"])
      assert length(decoded["chunks"]) == 1

      [chunk] = decoded["chunks"]
      assert chunk["tokens"] == [1, 2, 3]
      assert chunk["type"] == "encoded_text"
    end
  end
end
