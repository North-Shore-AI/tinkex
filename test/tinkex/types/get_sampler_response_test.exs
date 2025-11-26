defmodule Tinkex.Types.GetSamplerResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.GetSamplerResponse

  describe "from_json/1" do
    test "parses complete response with model_path" do
      json = %{
        "sampler_id" => "session-id:sample:0",
        "base_model" => "Qwen/Qwen2.5-7B",
        "model_path" => "tinker://run-id/weights/checkpoint-001"
      }

      result = GetSamplerResponse.from_json(json)

      assert %GetSamplerResponse{
               sampler_id: "session-id:sample:0",
               base_model: "Qwen/Qwen2.5-7B",
               model_path: "tinker://run-id/weights/checkpoint-001"
             } = result
    end

    test "parses response without model_path" do
      json = %{
        "sampler_id" => "session-id:sample:0",
        "base_model" => "Qwen/Qwen2.5-7B"
      }

      result = GetSamplerResponse.from_json(json)

      assert %GetSamplerResponse{
               sampler_id: "session-id:sample:0",
               base_model: "Qwen/Qwen2.5-7B",
               model_path: nil
             } = result
    end

    test "handles atom keys with model_path" do
      json = %{
        sampler_id: "test-sampler",
        base_model: "test-model",
        model_path: "tinker://test/weights/001"
      }

      result = GetSamplerResponse.from_json(json)

      assert result.sampler_id == "test-sampler"
      assert result.base_model == "test-model"
      assert result.model_path == "tinker://test/weights/001"
    end

    test "handles atom keys without model_path" do
      json = %{
        sampler_id: "test-sampler",
        base_model: "test-model"
      }

      result = GetSamplerResponse.from_json(json)

      assert result.model_path == nil
    end
  end

  describe "Jason.Encoder" do
    test "includes model_path when present" do
      resp = %GetSamplerResponse{
        sampler_id: "test-sampler",
        base_model: "test-model",
        model_path: "tinker://run/weights/001"
      }

      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      assert decoded["sampler_id"] == "test-sampler"
      assert decoded["base_model"] == "test-model"
      assert decoded["model_path"] == "tinker://run/weights/001"
    end

    test "excludes model_path when nil" do
      resp = %GetSamplerResponse{
        sampler_id: "test-sampler",
        base_model: "test-model",
        model_path: nil
      }

      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      assert decoded["sampler_id"] == "test-sampler"
      assert decoded["base_model"] == "test-model"
      refute Map.has_key?(decoded, "model_path")
    end
  end

  describe "roundtrip" do
    test "from_json and encode roundtrip with model_path" do
      original_json = %{
        "sampler_id" => "session:sample:0",
        "base_model" => "Qwen/Qwen2.5-7B",
        "model_path" => "tinker://run/weights/checkpoint"
      }

      resp = GetSamplerResponse.from_json(original_json)
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)
      roundtrip = GetSamplerResponse.from_json(decoded)

      assert roundtrip.sampler_id == original_json["sampler_id"]
      assert roundtrip.base_model == original_json["base_model"]
      assert roundtrip.model_path == original_json["model_path"]
    end

    test "from_json and encode roundtrip without model_path" do
      original_json = %{
        "sampler_id" => "session:sample:0",
        "base_model" => "Qwen/Qwen2.5-7B"
      }

      resp = GetSamplerResponse.from_json(original_json)
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)
      roundtrip = GetSamplerResponse.from_json(decoded)

      assert roundtrip.sampler_id == original_json["sampler_id"]
      assert roundtrip.base_model == original_json["base_model"]
      assert roundtrip.model_path == nil
    end
  end
end
