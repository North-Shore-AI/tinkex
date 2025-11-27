defmodule Tinkex.Types.GetServerCapabilitiesResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{GetServerCapabilitiesResponse, SupportedModel}

  describe "from_json/1" do
    test "parses list of model objects with full metadata" do
      json = %{
        "supported_models" => [
          %{"model_name" => "llama", "arch" => "llama", "model_id" => "llama-3-8b"},
          %{"model_name" => "qwen", "arch" => "qwen2", "model_id" => "qwen2-72b"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      assert [%SupportedModel{} | _] = response.supported_models

      [first, second] = response.supported_models
      assert first.model_name == "llama"
      assert first.arch == "llama"
      assert first.model_id == "llama-3-8b"
      assert second.model_name == "qwen"
      assert second.arch == "qwen2"
      assert second.model_id == "qwen2-72b"
    end

    test "parses with atom keys" do
      json = %{
        supported_models: [
          %{model_name: "test", arch: "llama", model_id: "test-1"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 1
      [model] = response.supported_models
      assert model.model_name == "test"
      assert model.model_id == "test-1"
    end

    test "handles legacy string format (backward compatibility)" do
      json = %{
        "supported_models" => ["llama", "qwen"]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2

      assert [%SupportedModel{model_name: "llama"}, %SupportedModel{model_name: "qwen"}] =
               response.supported_models
    end

    test "handles mixed format (objects and strings)" do
      json = %{
        "supported_models" => [
          %{"model_name" => "llama", "arch" => "llama"},
          "qwen"
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      [first, second] = response.supported_models
      assert %SupportedModel{model_name: "llama", arch: "llama"} = first
      assert %SupportedModel{model_name: "qwen"} = second
      assert second.arch == nil
    end

    test "handles empty supported_models" do
      json = %{"supported_models" => []}

      response = GetServerCapabilitiesResponse.from_json(json)

      assert response.supported_models == []
    end

    test "handles missing supported_models key" do
      response = GetServerCapabilitiesResponse.from_json(%{})

      assert response.supported_models == []
    end

    test "preserves all model metadata" do
      json = %{
        "supported_models" => [
          %{
            "model_name" => "meta-llama/Meta-Llama-3-8B",
            "model_id" => "llama-3-8b",
            "arch" => "llama"
          }
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)
      [model] = response.supported_models

      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.model_id == "llama-3-8b"
      assert model.arch == "llama"
    end

    test "filters out nil entries" do
      json = %{
        "supported_models" => [
          %{"model_name" => "valid"},
          nil
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 1
      assert hd(response.supported_models).model_name == "valid"
    end
  end

  describe "model_names/1 helper" do
    test "extracts model names for convenience" do
      response = %GetServerCapabilitiesResponse{
        supported_models: [
          %SupportedModel{model_name: "llama", model_id: "llama-3-8b", arch: "llama"},
          %SupportedModel{model_name: "qwen", model_id: "qwen2-72b", arch: "qwen2"}
        ]
      }

      assert GetServerCapabilitiesResponse.model_names(response) == ["llama", "qwen"]
    end

    test "handles empty list" do
      response = %GetServerCapabilitiesResponse{supported_models: []}

      assert GetServerCapabilitiesResponse.model_names(response) == []
    end

    test "handles nil model_name" do
      response = %GetServerCapabilitiesResponse{
        supported_models: [
          %SupportedModel{model_name: "valid"},
          %SupportedModel{model_name: nil}
        ]
      }

      assert GetServerCapabilitiesResponse.model_names(response) == ["valid", nil]
    end
  end
end
