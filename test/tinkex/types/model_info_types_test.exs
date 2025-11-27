defmodule Tinkex.Types.ModelInfoTypesTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{GetInfoResponse, ModelData, UnloadModelResponse}

  describe "ModelData.from_json/1" do
    test "parses string keys" do
      json = %{
        "arch" => "llama",
        "model_name" => "meta-llama/Llama-3",
        "tokenizer_id" => "hf/tok"
      }

      assert %ModelData{arch: "llama", model_name: "meta-llama/Llama-3", tokenizer_id: "hf/tok"} =
               ModelData.from_json(json)
    end

    test "parses atom keys" do
      json = %{arch: "qwen", model_name: "Qwen/Qwen2", tokenizer_id: "hf/qwen"}

      assert %ModelData{arch: "qwen", model_name: "Qwen/Qwen2", tokenizer_id: "hf/qwen"} =
               ModelData.from_json(json)
    end
  end

  describe "GetInfoResponse.from_json/1" do
    test "parses response with optional fields" do
      json = %{
        "model_id" => "model-1",
        "model_data" => %{"arch" => "llama", "model_name" => "meta-llama/Llama-3"},
        "is_lora" => true,
        "lora_rank" => 8,
        "model_name" => "meta-llama/Llama-3",
        "type" => "get_info"
      }

      assert %GetInfoResponse{
               model_id: "model-1",
               model_data: %ModelData{arch: "llama", model_name: "meta-llama/Llama-3"},
               is_lora: true,
               lora_rank: 8,
               model_name: "meta-llama/Llama-3",
               type: "get_info"
             } = GetInfoResponse.from_json(json)
    end

    test "handles atom keys and missing optionals" do
      json = %{
        model_id: "model-2",
        model_data: %{arch: "qwen", tokenizer_id: "hf/qwen"}
      }

      assert %GetInfoResponse{
               model_id: "model-2",
               model_data: %ModelData{arch: "qwen", tokenizer_id: "hf/qwen"},
               is_lora: nil,
               lora_rank: nil,
               model_name: nil,
               type: nil
             } = GetInfoResponse.from_json(json)
    end
  end

  describe "UnloadModelResponse.from_json/1" do
    test "parses string keys" do
      json = %{"model_id" => "model-3", "type" => "unload_model"}

      assert %UnloadModelResponse{model_id: "model-3", type: "unload_model"} =
               UnloadModelResponse.from_json(json)
    end

    test "parses atom keys" do
      json = %{model_id: "model-4"}

      assert %UnloadModelResponse{model_id: "model-4", type: nil} =
               UnloadModelResponse.from_json(json)
    end
  end
end
