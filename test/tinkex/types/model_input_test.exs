defmodule Tinkex.Types.ModelInputTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{EncodedTextChunk, ImageChunk, ImageAssetPointerChunk, ModelInput}

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
