defmodule Tinkex.TrainingClientObserverTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Tinkex.TrainingClient

  describe "QueueStateObserver implementation" do
    test "TrainingClient declares the behaviour" do
      # Check that the module has @behaviour Tinkex.QueueStateObserver
      # by verifying the callback is implemented
      assert function_exported?(TrainingClient, :on_queue_state_change, 2)
      assert function_exported?(TrainingClient, :on_queue_state_change, 1)
    end

    test "on_queue_state_change/2 returns :ok" do
      assert :ok == TrainingClient.on_queue_state_change(:active, %{})
    end
  end

  describe "on_queue_state_change/2" do
    setup do
      # Clean up any persistent_term state from previous tests
      model_id = "test-model-#{System.unique_integer([:positive])}"
      debounce_key = {:training_queue_state_debounce, model_id}

      on_exit(fn ->
        try do
          :persistent_term.erase(debounce_key)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:ok, model_id: model_id, debounce_key: debounce_key}
    end

    test "logs warning for paused_rate_limit with model ID", %{model_id: model_id} do
      log =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_rate_limit, %{model_id: model_id})
        end)

      assert log =~ "Training is paused"
      assert log =~ model_id
      # Training uses "concurrent models rate limit hit" instead of "concurrent LoRA"
      assert log =~ "concurrent models rate limit hit"
    end

    test "logs warning for paused_capacity with model ID", %{model_id: model_id} do
      log =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_capacity, %{model_id: model_id})
        end)

      assert log =~ "Training is paused"
      assert log =~ model_id
      assert log =~ "out of capacity"
    end

    test "does not log for active state", %{model_id: model_id} do
      log =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:active, %{model_id: model_id})
        end)

      assert log == ""
    end

    test "respects 60-second debounce interval", %{model_id: model_id, debounce_key: debounce_key} do
      # First call should log
      log1 =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_rate_limit, %{model_id: model_id})
        end)

      assert log1 =~ "Training is paused"

      # Second call within 60s should NOT log (debounced)
      log2 =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_rate_limit, %{model_id: model_id})
        end)

      assert log2 == ""

      # Simulate time passing by clearing the debounce state
      :persistent_term.erase(debounce_key)

      # Third call should log again
      log3 =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_rate_limit, %{model_id: model_id})
        end)

      assert log3 =~ "Training is paused"
    end

    test "uses 'unknown' when no model_id in metadata" do
      log =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:paused_capacity, %{})
        end)

      assert log =~ "unknown"
      assert log =~ "Training is paused"
    end

    test "logs unknown reason for unknown state", %{model_id: model_id} do
      log =
        capture_log(fn ->
          TrainingClient.on_queue_state_change(:unknown, %{model_id: model_id})
        end)

      assert log =~ "Training is paused"
      assert log =~ model_id
      assert log =~ "unknown"
    end
  end
end
