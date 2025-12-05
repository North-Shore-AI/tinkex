defmodule Tinkex.Types.CheckpointTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{Checkpoint, CheckpointsListResponse, CheckpointArchiveUrlResponse}

  describe "Checkpoint" do
    test "creates struct with all fields" do
      checkpoint = %Checkpoint{
        checkpoint_id: "ckpt-123",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        training_run_id: "run-1",
        size_bytes: 1_000_000,
        public: false,
        time: ~U[2025-11-20 10:00:00Z]
      }

      assert checkpoint.checkpoint_id == "ckpt-123"
      assert checkpoint.checkpoint_type == "weights"
      assert checkpoint.tinker_path == "tinker://run-1/weights/0001"
      assert checkpoint.training_run_id == "run-1"
      assert checkpoint.size_bytes == 1_000_000
      assert checkpoint.public == false
      assert checkpoint.time == ~U[2025-11-20 10:00:00Z]
    end

    test "size_bytes can be nil" do
      checkpoint = %Checkpoint{
        checkpoint_id: "ckpt-123",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        training_run_id: "run-1",
        size_bytes: nil,
        public: true,
        time: ~U[2025-11-20 10:00:00Z]
      }

      assert checkpoint.size_bytes == nil
      assert checkpoint.public == true
    end

    test "from_map/1 converts string-keyed map to struct" do
      map = %{
        "checkpoint_id" => "ckpt-456",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-2/weights/0001",
        "size_bytes" => 2_000_000,
        "public" => false,
        "time" => "2025-11-21T12:00:00Z"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.checkpoint_id == "ckpt-456"
      assert checkpoint.size_bytes == 2_000_000
      assert checkpoint.training_run_id == "run-2"
      assert %DateTime{} = checkpoint.time
    end

    test "from_map/1 handles nil size_bytes" do
      map = %{
        "checkpoint_id" => "ckpt-789",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-3/weights/0001",
        "size_bytes" => nil,
        "public" => true,
        "time" => "2025-11-21T14:00:00Z"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.size_bytes == nil
      assert %DateTime{} = checkpoint.time
    end

    test "parses training_run_id from tinker_path when missing" do
      map = %{
        "checkpoint_id" => "ckpt-456",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-2/weights/0001",
        "size_bytes" => 2_000_000,
        "public" => false,
        "time" => "2025-11-21T12:00:00Z"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.training_run_id == "run-2"
    end

    test "preserves non-ISO timestamps" do
      map = %{
        "checkpoint_id" => "ckpt-999",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-9/weights/0009",
        "time" => "Thu, 05 Dec 2025 10:00:00 GMT"
      }

      checkpoint = Checkpoint.from_map(map)

      assert checkpoint.time == "Thu, 05 Dec 2025 10:00:00 GMT"
    end
  end

  describe "CheckpointsListResponse" do
    test "creates struct with checkpoints and cursor" do
      checkpoint = %Checkpoint{
        checkpoint_id: "ckpt-1",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        size_bytes: 1000,
        public: false,
        time: "2025-11-20T10:00:00Z"
      }

      response = %CheckpointsListResponse{
        checkpoints: [checkpoint],
        cursor: %Tinkex.Types.Cursor{total_count: 100, offset: 0, limit: 2}
      }

      assert length(response.checkpoints) == 1
      assert response.cursor.total_count == 100
    end

    test "cursor can be nil" do
      response = %CheckpointsListResponse{
        checkpoints: [],
        cursor: nil
      }

      assert response.cursor == nil
    end

    test "from_map/1 converts map with checkpoints to struct" do
      map = %{
        "checkpoints" => [
          %{
            "checkpoint_id" => "ckpt-1",
            "checkpoint_type" => "weights",
            "tinker_path" => "tinker://run-1/weights/0001",
            "size_bytes" => 1000,
            "public" => false,
            "time" => "2025-11-20T10:00:00Z"
          }
        ],
        "cursor" => %{"total_count" => 50, "limit" => 1, "offset" => 0}
      }

      response = CheckpointsListResponse.from_map(map)

      assert length(response.checkpoints) == 1
      [ckpt] = response.checkpoints
      assert ckpt.checkpoint_id == "ckpt-1"
      assert response.cursor.total_count == 50
      assert response.cursor.limit == 1
    end
  end

  describe "CheckpointArchiveUrlResponse" do
    test "creates struct with url and expires" do
      response = %CheckpointArchiveUrlResponse{
        url: "https://storage.example.com/checkpoint.tar",
        expires: ~U[2025-12-03 00:00:00Z]
      }

      assert response.url == "https://storage.example.com/checkpoint.tar"
      assert response.expires == ~U[2025-12-03 00:00:00Z]
    end

    test "from_map/1 converts map to struct and parses iso8601 expires" do
      map = %{
        "url" => "https://example.com/download/ckpt.tar",
        "expires" => "2025-12-03T01:02:03Z"
      }

      response = CheckpointArchiveUrlResponse.from_map(map)

      assert response.url == "https://example.com/download/ckpt.tar"
      assert %DateTime{} = response.expires
      assert DateTime.to_iso8601(response.expires) == "2025-12-03T01:02:03Z"
    end

    test "from_map/1 preserves non-ISO expires strings" do
      map = %{
        "url" => "https://example.com/download/ckpt.tar",
        "expires" => "Wed, 03 Dec 2025 01:02:03 GMT"
      }

      response = CheckpointArchiveUrlResponse.from_map(map)

      assert response.expires == "Wed, 03 Dec 2025 01:02:03 GMT"
    end
  end
end
