defmodule Tinkex.Types.LoadWeightsRequestTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.LoadWeightsRequest

  describe "struct creation" do
    test "defaults optimizer to false" do
      request = %LoadWeightsRequest{
        model_id: "run-1",
        path: "tinker://run-1/weights/0001"
      }

      assert request.optimizer == false
      assert request.type == "load_weights"
    end

    test "allows setting optimizer and seq_id" do
      request = %LoadWeightsRequest{
        model_id: "run-1",
        path: "tinker://run-1/weights/0001",
        seq_id: 5,
        optimizer: true
      }

      assert request.optimizer == true
      assert request.seq_id == 5
    end
  end

  describe "json encoding" do
    test "encodes optimizer field and omits deprecated name" do
      json =
        %LoadWeightsRequest{
          model_id: "run-123",
          path: "tinker://run-123/weights/checkpoint-001",
          optimizer: true,
          seq_id: 7
        }
        |> Jason.encode!()
        |> Jason.decode!()

      assert json == %{
               "model_id" => "run-123",
               "optimizer" => true,
               "path" => "tinker://run-123/weights/checkpoint-001",
               "seq_id" => 7,
               "type" => "load_weights"
             }

      refute Map.has_key?(json, "load_optimizer_state")
    end
  end
end
