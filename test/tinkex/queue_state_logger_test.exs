defmodule Tinkex.QueueStateLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tinkex.QueueStateLogger

  describe "log_state_change/3" do
    test "logs warning for paused_rate_limit with sampling" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_rate_limit, :sampling, "session-123")
        end)

      assert log =~ "Sampling is paused"
      assert log =~ "session-123"
      assert log =~ "concurrent sampler weights limit hit"
    end

    test "logs warning for paused_rate_limit with training" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_rate_limit, :training, "model-abc")
        end)

      assert log =~ "Training is paused"
      assert log =~ "model-abc"
      assert log =~ "concurrent training clients rate limit hit"
    end

    test "logs warning for paused_capacity with sampling" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_capacity, :sampling, "session-456")
        end)

      assert log =~ "Sampling is paused"
      assert log =~ "session-456"
      assert log =~ "running short on capacity, please wait"
    end

    test "logs warning for paused_capacity with training" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:paused_capacity, :training, "model-xyz")
        end)

      assert log =~ "Training is paused"
      assert log =~ "model-xyz"
      assert log =~ "running short on capacity, please wait"
    end

    test "does not log for active state" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:active, :sampling, "session-123")
        end)

      refute log =~ "Sampling is paused for session-1"
    end

    test "logs unknown reason for unknown state" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(:unknown, :training, "model-xyz")
        end)

      assert log =~ "Training is paused"
      assert log =~ "model-xyz"
      assert log =~ "unknown"
    end

    test "prefers server-provided reason" do
      log =
        capture_log(fn ->
          QueueStateLogger.log_state_change(
            :paused_rate_limit,
            :sampling,
            "session-override",
            "server reason"
          )
        end)

      line =
        log
        |> String.split("\n", trim: true)
        |> Enum.find(&String.contains?(&1, "session-override"))

      assert line =~ "server reason"
      refute line =~ "concurrent sampler weights limit hit"
    end
  end

  describe "should_log?/2 (debouncing)" do
    test "returns true when enough time has passed" do
      last_logged = System.monotonic_time(:millisecond) - 61_000
      assert QueueStateLogger.should_log?(last_logged, 60_000) == true
    end

    test "returns false within debounce interval" do
      last_logged = System.monotonic_time(:millisecond) - 30_000
      assert QueueStateLogger.should_log?(last_logged, 60_000) == false
    end

    test "returns true for initial log (nil timestamp)" do
      assert QueueStateLogger.should_log?(nil, 60_000) == true
    end

    test "uses default 60-second interval" do
      last_logged = System.monotonic_time(:millisecond) - 61_000
      assert QueueStateLogger.should_log?(last_logged) == true

      last_logged = System.monotonic_time(:millisecond) - 30_000
      assert QueueStateLogger.should_log?(last_logged) == false
    end
  end

  describe "reason_for_state/2" do
    test "returns sampler message for sampling rate limit" do
      assert QueueStateLogger.reason_for_state(:paused_rate_limit, :sampling) ==
               "concurrent sampler weights limit hit"
    end

    test "returns training clients message for training rate limit" do
      assert QueueStateLogger.reason_for_state(:paused_rate_limit, :training) ==
               "concurrent training clients rate limit hit"
    end

    test "returns capacity message for sampling" do
      assert QueueStateLogger.reason_for_state(:paused_capacity, :sampling) ==
               "Tinker backend is running short on capacity, please wait"
    end

    test "returns capacity message for training" do
      assert QueueStateLogger.reason_for_state(:paused_capacity, :training) ==
               "Tinker backend is running short on capacity, please wait"
    end

    test "returns unknown for unknown state" do
      assert QueueStateLogger.reason_for_state(:unknown, :sampling) == "unknown"
      assert QueueStateLogger.reason_for_state(:unknown, :training) == "unknown"
    end
  end

  describe "resolve_reason/3" do
    test "uses server reason when provided" do
      assert QueueStateLogger.resolve_reason(
               :paused_rate_limit,
               :sampling,
               "server provided"
             ) == "server provided"
    end

    test "falls back to defaults when server reason missing" do
      assert QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, nil) ==
               "concurrent sampler weights limit hit"

      assert QueueStateLogger.resolve_reason(:paused_rate_limit, :training, "") ==
               "concurrent training clients rate limit hit"
    end
  end

  describe "maybe_log/4 (combined debouncing and logging)" do
    test "logs and returns new timestamp when should log" do
      # Simulate enough time has passed
      old_timestamp = System.monotonic_time(:millisecond) - 61_000

      log =
        capture_log(fn ->
          result =
            QueueStateLogger.maybe_log(:paused_rate_limit, :sampling, "session-1", old_timestamp)

          # Should return a new timestamp
          assert is_integer(result)
          assert result > old_timestamp
        end)

      assert log =~ "Sampling is paused"
    end

    test "does not log and returns same timestamp when within interval" do
      # Simulate not enough time has passed
      recent_timestamp = System.monotonic_time(:millisecond) - 30_000

      log =
        capture_log(fn ->
          result =
            QueueStateLogger.maybe_log(
              :paused_rate_limit,
              :sampling,
              "session-1",
              recent_timestamp
            )

          # Should return the same timestamp
          assert result == recent_timestamp
        end)

      refute log =~ "Sampling is paused for session-1"
    end

    test "does not log for active state regardless of timestamp" do
      old_timestamp = System.monotonic_time(:millisecond) - 61_000

      log =
        capture_log(fn ->
          result = QueueStateLogger.maybe_log(:active, :sampling, "session-1", old_timestamp)
          # Should return the same timestamp for active state
          assert result == old_timestamp
        end)

      refute log =~ "Sampling is paused for session-1"
    end

    test "logs with nil timestamp (first call)" do
      log =
        capture_log(fn ->
          result = QueueStateLogger.maybe_log(:paused_capacity, :training, "model-1", nil)
          # Should return a new timestamp
          assert is_integer(result)
        end)

      assert log =~ "Training is paused"
      assert log =~ "running short on capacity, please wait"
    end
  end
end
