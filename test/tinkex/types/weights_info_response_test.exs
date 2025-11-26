defmodule Tinkex.Types.WeightsInfoResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.WeightsInfoResponse

  describe "from_json/1" do
    test "parses complete response with lora_rank" do
      json = %{
        "base_model" => "Qwen/Qwen2.5-7B",
        "is_lora" => true,
        "lora_rank" => 32
      }

      result = WeightsInfoResponse.from_json(json)

      assert %WeightsInfoResponse{
               base_model: "Qwen/Qwen2.5-7B",
               is_lora: true,
               lora_rank: 32
             } = result
    end

    test "parses response without lora_rank" do
      json = %{
        "base_model" => "Qwen/Qwen2.5-7B",
        "is_lora" => false
      }

      result = WeightsInfoResponse.from_json(json)

      assert %WeightsInfoResponse{
               base_model: "Qwen/Qwen2.5-7B",
               is_lora: false,
               lora_rank: nil
             } = result
    end

    test "handles atom keys" do
      json = %{
        base_model: "test-model",
        is_lora: true,
        lora_rank: 16
      }

      result = WeightsInfoResponse.from_json(json)

      assert result.base_model == "test-model"
      assert result.is_lora == true
      assert result.lora_rank == 16
    end

    test "handles atom keys without lora_rank" do
      json = %{
        base_model: "test-model",
        is_lora: false
      }

      result = WeightsInfoResponse.from_json(json)

      assert result.lora_rank == nil
    end
  end

  describe "Jason.Encoder" do
    test "includes lora_rank when present" do
      resp = %WeightsInfoResponse{
        base_model: "test-model",
        is_lora: true,
        lora_rank: 32
      }

      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      assert decoded["base_model"] == "test-model"
      assert decoded["is_lora"] == true
      assert decoded["lora_rank"] == 32
    end

    test "excludes lora_rank when nil" do
      resp = %WeightsInfoResponse{
        base_model: "test-model",
        is_lora: false,
        lora_rank: nil
      }

      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      assert decoded["base_model"] == "test-model"
      assert decoded["is_lora"] == false
      refute Map.has_key?(decoded, "lora_rank")
    end
  end

  describe "roundtrip" do
    test "from_json and encode roundtrip with lora_rank" do
      original_json = %{
        "base_model" => "Qwen/Qwen2.5-7B",
        "is_lora" => true,
        "lora_rank" => 64
      }

      resp = WeightsInfoResponse.from_json(original_json)
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)
      roundtrip = WeightsInfoResponse.from_json(decoded)

      assert roundtrip.base_model == original_json["base_model"]
      assert roundtrip.is_lora == original_json["is_lora"]
      assert roundtrip.lora_rank == original_json["lora_rank"]
    end

    test "from_json and encode roundtrip without lora_rank" do
      original_json = %{
        "base_model" => "Qwen/Qwen2.5-7B",
        "is_lora" => false
      }

      resp = WeightsInfoResponse.from_json(original_json)
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)
      roundtrip = WeightsInfoResponse.from_json(decoded)

      assert roundtrip.base_model == original_json["base_model"]
      assert roundtrip.is_lora == original_json["is_lora"]
      assert roundtrip.lora_rank == nil
    end
  end
end
