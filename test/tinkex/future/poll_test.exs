defmodule Tinkex.Future.PollTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.Future
  alias Tinkex.Error

  setup :setup_http_client

  defmodule TestObserver do
    @behaviour Tinkex.QueueStateObserver

    def register(pid) when is_pid(pid) do
      :persistent_term.put({__MODULE__, :pid}, pid)
    end

    def unregister do
      :persistent_term.erase({__MODULE__, :pid})
    end

    @impl true
    def on_queue_state_change(queue_state) do
      case :persistent_term.get({__MODULE__, :pid}, nil) do
        pid when is_pid(pid) -> send(pid, {:observer_called, queue_state})
        _ -> :ok
      end
    end
  end

  setup _context do
    on_exit(fn -> TestObserver.unregister() end)
    :ok
  end

  describe "poll/2" do
    test "returns completed result", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/future/retrieve", fn conn ->
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
      Bypass.expect_once(bypass, "POST", "/api/v1/future/retrieve", fn conn ->
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

      sleep_fun = fn _ -> Process.sleep(1) end

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
           "retry_after_ms" => nil
         }, []},
        {200, %{"status" => "completed", "result" => %{"done" => true}}, []}
      ])

      handler_id = attach_telemetry([[:tinkex, :queue, :state_change]])
      TestObserver.register(self())

      parent = self()

      sleep_fun = fn ms ->
        send(parent, {:slept, ms})
      end

      task =
        Future.poll("req-try",
          config: config,
          sleep_fun: sleep_fun,
          queue_state_observer: TestObserver
        )

      assert {:ok, %{"done" => true}} = Task.await(task, 1_000)
      assert_receive {:slept, 1_000}

      assert_receive {:telemetry, [:tinkex, :queue, :state_change], %{},
                      %{queue_state: :paused_rate_limit, request_id: "req-try"}}

      assert_receive {:observer_called, :paused_rate_limit}
      :telemetry.detach(handler_id)
    end

    test "returns api_timeout when pending beyond timeout", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        resp(conn, 200, %{"status" => "pending"})
      end)

      task =
        Future.poll("req-timeout",
          config: config,
          timeout: 5,
          sleep_fun: fn _ -> Process.sleep(1) end
        )

      assert {:error, %Error{type: :api_timeout}} = Task.await(task, 1_000)
    end
  end

  defp resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end
end
