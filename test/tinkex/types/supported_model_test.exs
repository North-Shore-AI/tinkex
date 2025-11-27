defmodule Tinkex.Types.SupportedModelTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.SupportedModel

  describe "from_json/1" do
    test "parses model_name from string keys" do
      json = %{"model_name" => "meta-llama/Llama-3-8B"}
      model = SupportedModel.from_json(json)

      assert model.model_name == "meta-llama/Llama-3-8B"
    end

    test "parses model_name from atom keys" do
      json = %{model_name: "meta-llama/Llama-3-8B"}
      model = SupportedModel.from_json(json)

      assert model.model_name == "meta-llama/Llama-3-8B"
    end

    test "parses all known fields with string keys" do
      json = %{
        "model_name" => "meta-llama/Meta-Llama-3-8B",
        "model_id" => "llama-3-8b",
        "arch" => "llama"
      }

      model = SupportedModel.from_json(json)

      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.model_id == "llama-3-8b"
      assert model.arch == "llama"
    end

    test "parses all known fields with atom keys" do
      json = %{
        model_name: "Qwen/Qwen2-72B",
        model_id: "qwen2-72b",
        arch: "qwen2"
      }

      model = SupportedModel.from_json(json)

      assert model.model_name == "Qwen/Qwen2-72B"
      assert model.model_id == "qwen2-72b"
      assert model.arch == "qwen2"
    end

    test "handles missing optional fields" do
      json = %{"model_name" => "test-model"}
      model = SupportedModel.from_json(json)

      assert model.model_name == "test-model"
      assert model.model_id == nil
      assert model.arch == nil
    end

    test "handles empty map" do
      model = SupportedModel.from_json(%{})

      assert model.model_name == nil
      assert model.model_id == nil
      assert model.arch == nil
    end

    test "backward compatibility: plain string becomes model_name" do
      model = SupportedModel.from_json("meta-llama/Meta-Llama-3-8B")

      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.model_id == nil
      assert model.arch == nil
    end

    test "ignores unknown fields without error" do
      json = %{
        "model_name" => "test",
        "model_id" => "test-id",
        "arch" => "llama",
        "unknown_field" => "should be ignored",
        "another_field" => 123
      }

      model = SupportedModel.from_json(json)

      assert model.model_name == "test"
      assert model.model_id == "test-id"
      assert model.arch == "llama"
    end
  end

  describe "struct" do
    test "has correct fields" do
      model = %SupportedModel{}

      assert Map.has_key?(model, :model_name)
      assert Map.has_key?(model, :model_id)
      assert Map.has_key?(model, :arch)
    end

    test "can be created directly" do
      model = %SupportedModel{
        model_name: "test-model",
        model_id: "test-id",
        arch: "llama"
      }

      assert model.model_name == "test-model"
      assert model.model_id == "test-id"
      assert model.arch == "llama"
    end
  end
end
