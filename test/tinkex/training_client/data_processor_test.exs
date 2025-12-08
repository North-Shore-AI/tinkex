defmodule Tinkex.TrainingClient.DataProcessorTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient.DataProcessor
  alias Tinkex.Types.{Datum, EncodedTextChunk, ImageChunk, ModelInput}

  describe "chunk_data/1 with byte limits" do
    test "keeps up to 1024 items in a single chunk" do
      data = for _ <- 1..1024, do: small_datum()
      [chunk] = DataProcessor.chunk_data(data)
      assert length(chunk) == 1024
    end

    test "splits when item count exceeds 1024" do
      data = for _ <- 1..1025, do: small_datum()
      [first, second] = DataProcessor.chunk_data(data)

      assert length(first) == 1024
      assert length(second) == 1
    end

    test "splits when byte budget exceeds 5MB" do
      # Each datum ~100 KB (10_000 tokens * 10 bytes)
      data = for _ <- 1..51, do: datum_with_tokens(10_000)
      [first, second] = DataProcessor.chunk_data(data)

      assert length(first) == 50
      assert length(second) == 1
    end

    test "uses byte limit even when under item cap" do
      # Each datum ~600 KB, so 8 fit (<5 MB) and the 9th forces a split.
      data = for _ <- 1..9, do: datum_with_tokens(60_000)
      [first, second] = DataProcessor.chunk_data(data)

      assert length(first) == 8
      assert length(second) == 1
    end

    test "handles mixed text and image payloads" do
      base = [
        datum_with_tokens(1_000),
        datum_with_image(2_000_000),
        datum_with_tokens(1_000),
        datum_with_image(2_000_000),
        datum_with_tokens(1_000)
      ]

      assert DataProcessor.chunk_data(base) |> length() == 1

      # Adding one more 2MB image should push us over the 5MB cap.
      [first, second] = DataProcessor.chunk_data(base ++ [datum_with_image(2_000_000)])
      assert length(first) == 5
      assert length(second) == 1
    end
  end

  defp small_datum do
    %Datum{
      model_input: %ModelInput{chunks: [%EncodedTextChunk{tokens: [1]}]},
      loss_fn_inputs: %{}
    }
  end

  defp datum_with_tokens(count) do
    tokens = Enum.to_list(1..count)

    %Datum{
      model_input: %ModelInput{chunks: [%EncodedTextChunk{tokens: tokens}]},
      loss_fn_inputs: %{}
    }
  end

  defp datum_with_image(size) do
    %Datum{
      model_input: %ModelInput{
        chunks: [%ImageChunk{data: String.duplicate("a", size), format: :png}]
      },
      loss_fn_inputs: %{}
    }
  end
end
