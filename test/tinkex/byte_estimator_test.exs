defmodule Tinkex.ByteEstimatorTest do
  use ExUnit.Case, async: true

  alias Tinkex.ByteEstimator

  alias Tinkex.Types.{
    Datum,
    EncodedTextChunk,
    ImageAssetPointerChunk,
    ImageChunk,
    ModelInput,
    TensorData
  }

  describe "estimate_chunk_bytes/1" do
    test "returns raw byte size for image chunks" do
      chunk = %ImageChunk{data: String.duplicate("a", 10), format: :png}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == 10
    end

    test "returns location byte size for image asset pointers" do
      location = "tinker://asset/path"
      chunk = %ImageAssetPointerChunk{location: location, format: :png}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == byte_size(location)
    end

    test "applies 10-byte multiplier for encoded text chunks" do
      chunk = %EncodedTextChunk{tokens: [1, 2, 3, 4, 5], type: "encoded_text"}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == 50
    end

    test "falls back to 0 for unknown chunks" do
      assert ByteEstimator.estimate_chunk_bytes(%{foo: :bar}) == 0
    end
  end

  describe "estimate_model_input_bytes/1" do
    test "sums all chunk estimates" do
      input = %ModelInput{
        chunks: [
          %EncodedTextChunk{tokens: [1, 2, 3]},
          %ImageChunk{data: "12345678", format: :png}
        ]
      }

      assert ByteEstimator.estimate_model_input_bytes(input) == 38
    end

    test "returns 0 for empty inputs" do
      assert ByteEstimator.estimate_model_input_bytes(%ModelInput{chunks: []}) == 0
    end
  end

  describe "estimate_loss_fn_inputs_bytes/1" do
    test "handles TensorData inputs" do
      inputs = %{"target_tokens" => %TensorData{data: [1, 2, 3, 4], dtype: :int64}}
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(inputs) == 40
    end

    test "handles plain maps with data lists" do
      inputs = %{
        "weights" => %{data: [0.1, 0.2]},
        :mask => %{"data" => [1, 2, 3]}
      }

      assert ByteEstimator.estimate_loss_fn_inputs_bytes(inputs) == 50
    end

    test "handles Nx tensors" do
      tensor = Nx.tensor([1, 2, 3, 4, 5])
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(%{"tensor" => tensor}) == 50
    end
  end

  describe "estimate_datum_bytes/1" do
    test "combines model input and loss input estimates" do
      datum = %Datum{
        model_input: %ModelInput{chunks: [%EncodedTextChunk{tokens: [1, 2, 3]}]},
        loss_fn_inputs: %{"target_tokens" => %TensorData{data: [1, 2], dtype: :int32}}
      }

      assert ByteEstimator.estimate_datum_bytes(datum) == 50
    end
  end

  describe "estimate_data_bytes/1" do
    test "sums estimates across datums" do
      data = [
        %Datum{
          model_input: %ModelInput{chunks: [%EncodedTextChunk{tokens: [1]}]},
          loss_fn_inputs: %{}
        },
        %Datum{
          model_input: %ModelInput{chunks: [%EncodedTextChunk{tokens: [1, 2]}]},
          loss_fn_inputs: %{}
        }
      ]

      assert ByteEstimator.estimate_data_bytes(data) == 30
    end
  end
end
