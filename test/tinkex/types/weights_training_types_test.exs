defmodule Tinkex.Types.WeightsTrainingTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    Checkpoint,
    Cursor,
    LoadWeightsResponse,
    SaveWeightsForSamplerResponse,
    SaveWeightsResponse,
    TrainingRun,
    TrainingRunsResponse
  }

  test "parses save weights response payloads" do
    resp = SaveWeightsResponse.from_json(%{"path" => "tinker://run/weights/step-1"})
    assert resp.path == "tinker://run/weights/step-1"
    assert resp.type == "save_weights"
  end

  test "parses save_weights_for_sampler responses with sampler id" do
    resp =
      SaveWeightsForSamplerResponse.from_json(%{
        "path" => "tinker://run/sampler/step-2",
        "sampling_session_id" => "session:sample:1"
      })

    assert resp.path == "tinker://run/sampler/step-2"
    assert resp.sampling_session_id == "session:sample:1"
    assert resp.type == "save_weights_for_sampler"
  end

  test "parses load weights response" do
    resp = LoadWeightsResponse.from_json(%{"path" => "tinker://run/weights/step-3"})
    assert resp.path == "tinker://run/weights/step-3"
    assert resp.type == "load_weights"
  end

  test "parses training run with nested checkpoints and datetime" do
    payload = %{
      "training_run_id" => "run-123",
      "base_model" => "meta-llama/Llama-3-8B",
      "model_owner" => "alice",
      "is_lora" => true,
      "lora_rank" => 16,
      "corrupted" => false,
      "last_request_time" => "2025-11-26T00:00:00Z",
      "last_checkpoint" => %{
        "checkpoint_id" => "ckpt-1",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-123/weights/0001",
        "time" => "2025-11-26T00:00:00Z",
        "size_bytes" => 100,
        "public" => false
      },
      "last_sampler_checkpoint" => %{
        "checkpoint_id" => "ckpt-2",
        "checkpoint_type" => "sampler",
        "tinker_path" => "tinker://run-123/sampler/0001",
        "time" => "2025-11-26T00:00:00Z",
        "size_bytes" => 100,
        "public" => false
      },
      "user_metadata" => %{"env" => "test"}
    }

    run = TrainingRun.from_map(payload)

    assert run.training_run_id == "run-123"
    assert run.base_model == "meta-llama/Llama-3-8B"
    assert run.model_owner == "alice"
    assert run.is_lora
    assert run.lora_rank == 16
    assert run.corrupted == false
    assert %DateTime{} = run.last_request_time
    assert %Checkpoint{} = run.last_checkpoint
    assert %Checkpoint{} = run.last_sampler_checkpoint
    assert run.user_metadata == %{"env" => "test"}
  end

  test "parses training runs response with cursor" do
    payload = %{
      "training_runs" => [
        %{
          "training_run_id" => "run-xyz",
          "base_model" => "base",
          "model_owner" => "bob",
          "is_lora" => false,
          "last_request_time" => "2025-11-26T00:00:00Z"
        }
      ],
      "cursor" => %{"offset" => 0, "limit" => 1, "total_count" => 10}
    }

    resp = TrainingRunsResponse.from_map(payload)

    assert length(resp.training_runs) == 1
    assert %TrainingRun{} = hd(resp.training_runs)
    assert %Cursor{offset: 0, limit: 1, total_count: 10} = resp.cursor
  end
end
