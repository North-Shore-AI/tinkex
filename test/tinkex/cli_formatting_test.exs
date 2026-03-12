defmodule Tinkex.CLI.FormattingTest do
  use ExUnit.Case, async: true

  alias Tinkex.CLI.Formatting
  alias Tinkex.Types.{Checkpoint, TrainingRun, WeightsInfoResponse}

  test "checkpoint_to_map preserves machine-friendly timestamps for json output" do
    checkpoint = %Checkpoint{
      checkpoint_id: "ckpt-1",
      checkpoint_type: "weights",
      tinker_path: "tinker://run-1/weights/0001",
      training_run_id: "run-1",
      size_bytes: 1024,
      public: true,
      time: ~U[2026-03-10 22:00:00Z],
      expires_at: ~U[2026-03-12 22:00:00Z]
    }

    assert %{
             "time" => "2026-03-10T22:00:00Z",
             "expires_at" => "2026-03-12T22:00:00Z"
           } = Formatting.checkpoint_to_map(checkpoint)
  end

  test "run_to_map preserves machine-friendly timestamps for json output" do
    run = %TrainingRun{
      training_run_id: "run-1",
      base_model: "meta-llama/Llama-3.1-8B",
      model_owner: "owner-1",
      is_lora: true,
      lora_rank: 8,
      corrupted: false,
      last_request_time: ~U[2026-03-10 22:00:00Z],
      last_checkpoint: %Checkpoint{
        checkpoint_id: "ckpt-1",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        training_run_id: "run-1",
        size_bytes: 1024,
        public: true,
        time: ~U[2026-03-10 21:30:00Z],
        expires_at: ~U[2026-03-12 21:30:00Z]
      },
      last_sampler_checkpoint: nil,
      user_metadata: %{"stage" => "prod"}
    }

    assert %{
             "last_request_time" => "2026-03-10T22:00:00Z",
             "last_checkpoint" => %{
               "time" => "2026-03-10T21:30:00Z",
               "expires_at" => "2026-03-12T21:30:00Z"
             }
           } = Formatting.run_to_map(run)
  end

  test "weights_info_to_map includes training flags" do
    info = %WeightsInfoResponse{
      base_model: "meta-llama/Llama-3.1-8B",
      is_lora: true,
      lora_rank: 16,
      train_attn: true,
      train_mlp: false,
      train_unembed: true
    }

    assert %{
             "base_model" => "meta-llama/Llama-3.1-8B",
             "is_lora" => true,
             "lora_rank" => 16,
             "train_attn" => true,
             "train_mlp" => false,
             "train_unembed" => true
           } = Formatting.weights_info_to_map(info)
  end

  test "format_datetime humanizes recent timestamps and falls back to dates for older values" do
    now = ~U[2026-03-11 00:00:00Z]

    assert Formatting.format_datetime(~U[2026-03-10 22:00:00Z], now: now) == "2 hours ago"
    assert Formatting.format_datetime(~U[2026-03-11 02:00:00Z], now: now) == "in 2 hours"
    assert Formatting.format_datetime(~U[2026-01-01 00:00:00Z], now: now) == "2026-01-01"
  end

  test "format_expiration renders never for nil" do
    assert Formatting.format_expiration(nil) == "Never"
  end
end
