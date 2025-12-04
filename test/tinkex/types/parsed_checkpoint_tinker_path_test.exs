defmodule Tinkex.Types.ParsedCheckpointTinkerPathTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.ParsedCheckpointTinkerPath

  describe "from_tinker_path/1" do
    test "parses training checkpoints" do
      path = "tinker://run-123/weights/checkpoint-001"

      assert {:ok, parsed} = ParsedCheckpointTinkerPath.from_tinker_path(path)

      assert parsed.tinker_path == path
      assert parsed.training_run_id == "run-123"
      assert parsed.checkpoint_type == "training"
      assert parsed.checkpoint_id == "checkpoint-001"
    end

    test "parses sampler checkpoints" do
      path = "tinker://run-123/sampler_weights/checkpoint-001"

      assert {:ok, parsed} = ParsedCheckpointTinkerPath.from_tinker_path(path)

      assert parsed.training_run_id == "run-123"
      assert parsed.checkpoint_type == "sampler"
      assert parsed.checkpoint_id == "checkpoint-001"
    end

    test "rejects missing tinker:// prefix" do
      assert {:error, %Tinkex.Error{type: :validation, category: :user}} =
               ParsedCheckpointTinkerPath.from_tinker_path("run-123/weights/ckpt-1")
    end

    test "rejects invalid segment counts" do
      assert {:error, %Tinkex.Error{category: :user}} =
               ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights")

      assert {:error, %Tinkex.Error{category: :user}} =
               ParsedCheckpointTinkerPath.from_tinker_path(
                 "tinker://run-123/weights/ckpt-1/extra"
               )
    end

    test "rejects unknown checkpoint types" do
      assert {:error, %Tinkex.Error{category: :user}} =
               ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/model/ckpt-1")
    end
  end
end
