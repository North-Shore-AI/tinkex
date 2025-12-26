defmodule Tinkex.Future.PollTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.Error
  alias Tinkex.Future

  setup :setup_http_client

  defmodule TestObserver do
    @behaviour Tinkex.QueueStateObserver

    @impl true
    def on_queue_state_change(queue_state) do
      on_queue_state_change(queue_state, %{})
    end

    @impl true
    def on_queue_state_change(queue_state, metadata) do
      case Map.get(metadata, :observer_pid) do
        pid when is_pid(pid) -> send(pid, {:observer_called, queue_state, metadata})
        _ -> :ok
      end
    end
  end

  describe "poll/2" do
    test "returns completed result", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 200, %{"status" => "completed", "result" => %{"value" => 42}})
      end)

      task = Future.poll("req-1", config: config)
      assert {:ok, %{"value" => 42}} = Task.await(task, 1_000)
    end

    test "retries pending responses with exponential backoff", %{bypass: bypass, config: config} do
      stub_sequence(bypass, [
        {200, %{"status" => "pending"}, []},
        {200, %{"status" => "completed", "result" => %{"ok" => true}}, []}
      ])

      parent = self()

      sleep_fun = fn ms ->
        send(parent, {:slept, ms})
      end

      task = Future.poll("req-2", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"ok" => true}} = Task.await(task, 1_000)
      assert_receive {:slept, 1_000}
    end

    test "fails immediately on user-category errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 200, %{
          "status" => "failed",
          "error" => %{"message" => "bad input", "category" => "user"}
        })
      end)

      task = Future.poll("req-user", config: config)
      assert {:error, %Error{type: :request_failed, category: :user}} = Task.await(task, 1_000)
    end

    test "retries server-category errors until timeout", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        resp(conn, 200, %{
          "status" => "failed",
          "error" => %{"message" => "flaky", "category" => "server"}
        })
      end)

      # Use no-op sleep function to test retry logic without delays
      # The timeout: 5 ensures test completes quickly while verifying retry behavior
      sleep_fun = fn _ -> :ok end

      task =
        Future.poll("req-server",
          config: config,
          timeout: 5,
          sleep_fun: sleep_fun
        )

      assert {:error, %Error{type: :request_failed, category: :server}} = Task.await(task, 1_000)
    end

    test "handles try_again responses with telemetry + observer", %{
      bypass: bypass,
      config: config
    } do
      stub_sequence(bypass, [
        {200,
         %{
           "type" => "try_again",
           "request_id" => "req-try",
           "queue_state" => "paused_rate_limit",
           "retry_after_ms" => nil,
           "queue_state_reason" => "server throttle"
         }, []},
        {200, %{"status" => "completed", "result" => %{"done" => true}}, []}
      ])

      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :queue, :state_change])

      parent = self()

      sleep_fun = fn ms ->
        send(parent, {:slept, ms})
      end

      task =
        Future.poll("req-try",
          config: config,
          telemetry_metadata: %{observer_pid: self()},
          sleep_fun: sleep_fun,
          queue_state_observer: TestObserver
        )

      assert {:ok, %{"done" => true}} = Task.await(task, 1_000)
      assert_receive {:slept, 1_000}

      {:telemetry, _, %{}, metadata} =
        TelemetryHelpers.assert_telemetry(
          [:tinkex, :queue, :state_change],
          %{request_id: "req-try"}
        )

      assert metadata.queue_state == :paused_rate_limit
      assert metadata.request_id == "req-try"
      assert metadata.queue_state_reason == "server throttle"

      assert_receive {:observer_called, :paused_rate_limit,
                      %{queue_state_reason: "server throttle"}}
    end

    test "returns api_timeout when pending beyond timeout", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        resp(conn, 200, %{"status" => "pending"})
      end)

      # Use no-op sleep function to test timeout logic without delays
      # The timeout: 5 ensures test completes quickly while verifying timeout behavior
      task =
        Future.poll("req-timeout",
          config: config,
          timeout: 5,
          sleep_fun: fn _ -> :ok end
        )

      assert {:error, %Error{type: :api_timeout}} = Task.await(task, 1_000)
    end

    test "emits telemetry and returns retryable error on 410 expired promise", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 410, %{"message" => "promise expired", "category" => "server"})
      end)

      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])

      task = Future.poll("req-expired", config: config)

      assert {:error, %Error{status: 410, category: :server} = error} = Task.await(task, 1_000)
      assert error.message =~ "expired"

      {:telemetry, _, measurements, _metadata} =
        TelemetryHelpers.assert_telemetry(
          [:tinkex, :future, :api_error],
          %{request_id: "req-expired", status: 410}
        )

      assert is_integer(measurements.elapsed_time)
    end

    test "emits timeout telemetry when poll exceeds timeout", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        resp(conn, 200, %{"status" => "pending"})
      end)

      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :timeout])

      task =
        Future.poll("req-timeout-telemetry",
          config: config,
          timeout: 5,
          sleep_fun: fn _ -> :ok end
        )

      assert {:error, %Error{type: :api_timeout}} = Task.await(task, 1_000)

      {:telemetry, _, measurements, _metadata} =
        TelemetryHelpers.assert_telemetry(
          [:tinkex, :future, :timeout],
          %{request_id: "req-timeout-telemetry"}
        )

      assert measurements.elapsed_time >= 0
    end
  end
end
