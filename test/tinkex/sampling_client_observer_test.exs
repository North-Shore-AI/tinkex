defmodule Tinkex.SamplingClientObserverTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tinkex.SamplingClient

  describe "QueueStateObserver implementation" do
    test "SamplingClient declares the behaviour" do
      # Check that the module has @behaviour Tinkex.QueueStateObserver
      # by verifying the callback is implemented
      assert Code.ensure_loaded?(SamplingClient)
      assert function_exported?(SamplingClient, :on_queue_state_change, 2)
      assert function_exported?(SamplingClient, :on_queue_state_change, 1)
    end

    test "on_queue_state_change/2 returns :ok" do
      assert :ok == SamplingClient.on_queue_state_change(:active, %{})
    end
  end

  describe "on_queue_state_change/2" do
    setup do
      # Clean up any persistent_term state from previous tests
      session_id = "test-session-#{System.unique_integer([:positive])}"
      debounce_key = {:sampling_queue_state_debounce, session_id}

      on_exit(fn ->
        try do
          :persistent_term.erase(debounce_key)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:ok, session_id: session_id, debounce_key: debounce_key}
    end

    test "logs warning for paused_rate_limit with session ID", %{session_id: session_id} do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id
          })
        end)

      assert log =~ "Sampling is paused"
      assert log =~ session_id
      assert log =~ "concurrent sampler weights limit hit"
    end

    test "logs warning for paused_capacity with session ID", %{session_id: session_id} do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_capacity, %{
            sampling_session_id: session_id
          })
        end)

      assert log =~ "Sampling is paused"
      assert log =~ session_id
      assert log =~ "running short on capacity, please wait"
    end

    test "does not log for active state", %{session_id: session_id} do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:active, %{sampling_session_id: session_id})
        end)

      refute log =~ session_id
    end

    test "respects 60-second debounce interval", %{
      session_id: session_id,
      debounce_key: debounce_key
    } do
      # First call should log
      log1 =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id
          })
        end)

      assert log1 =~ "Sampling is paused"

      # Second call within 60s should NOT log (debounced)
      log2 =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id
          })
        end)

      refute log2 =~ session_id

      # Simulate time passing by clearing the debounce state
      :persistent_term.erase(debounce_key)

      # Third call should log again
      log3 =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id
          })
        end)

      assert log3 =~ "Sampling is paused"
    end

    test "falls back to session_id if sampling_session_id not provided" do
      session_id = "fallback-session-#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{session_id: session_id})
        end)

      assert log =~ session_id
      assert log =~ "Sampling is paused"
    end

    test "uses 'unknown' when no identifier in metadata" do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_capacity, %{})
        end)

      assert log =~ "unknown"
      assert log =~ "Sampling is paused"
    end

    test "prefers server supplied reason when present", %{session_id: session_id} do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id,
            queue_state_reason: "server override"
          })
        end)

      line =
        log
        |> String.split("\n")
        |> Enum.find(fn entry -> String.contains?(entry, session_id) end)

      assert line
      assert line =~ "server override"
      refute line =~ "concurrent sampler weights limit hit"
    end

    test "clears debounce entry when requested", %{
      session_id: session_id,
      debounce_key: debounce_key
    } do
      log =
        capture_log(fn ->
          SamplingClient.on_queue_state_change(:paused_rate_limit, %{
            sampling_session_id: session_id
          })
        end)

      assert log =~ "Sampling is paused"

      assert :persistent_term.get(debounce_key, nil)

      assert :ok == SamplingClient.clear_queue_state_debounce(session_id)
      refute :persistent_term.get(debounce_key, nil)
    end
  end
end
