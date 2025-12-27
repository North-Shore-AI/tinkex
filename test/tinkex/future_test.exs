defmodule Tinkex.FutureTest do
  @moduledoc """
  Tests for Future polling behavior, covering retry logic, error handling,
  and telemetry emission.
  """

  use Tinkex.HTTPCase, async: true

  alias Tinkex.Error
  alias Tinkex.Future

  defmodule ConnectionErrorClient do
    alias Tinkex.Error

    def post(_path, _body, opts) do
      counter = connection_error_counter(opts)
      :ok = :counters.add(counter, 1, 1)
      attempt = :counters.get(counter, 1)

      if attempt < 2 do
        {:error, Error.new(:api_connection, "connection failed")}
      else
        {:ok, %{"status" => "completed", "result" => %{"status" => "ok"}}}
      end
    end

    defp connection_error_counter(opts) do
      config = Keyword.fetch!(opts, :config)

      case config.user_metadata do
        %{connection_error_counter: counter} -> counter
        _ -> raise ArgumentError, "missing connection error counter"
      end
    end
  end

  setup :setup_http_client

  describe "poll_loop 408 handling (Python SDK parity)" do
    test "retries on 408 without backoff until success", %{bypass: bypass, config: config} do
      sleep_calls = :counters.new(1, [:atomics])
      sleep_fun = fn _ms -> :counters.add(sleep_calls, 1, 1) end

      stub_sequence(bypass, [
        {408, %{"message" => "Request timeout"}, []},
        {408, %{"message" => "Request timeout"}, []},
        {408, %{"message" => "Request timeout"}, []},
        {200, %{"status" => "completed", "result" => %{"data" => "success"}}, []}
      ])

      task = Future.poll("test-request-id", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"data" => "success"}} = Task.await(task, 5_000)
      assert :counters.get(sleep_calls, 1) == 0
    end

    test "eventually times out on endless 408s", %{bypass: bypass, config: config} do
      Bypass.stub(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 408, %{"message" => "Request timeout"})
      end)

      task = Future.poll("test-request-id", config: config, timeout: 10)
      assert {:error, %Error{type: :api_status, status: 408}} = Task.await(task, 5_000)
    end
  end

  describe "poll_loop 5xx handling (Python SDK parity)" do
    test "continues polling on 5xx status until success", %{bypass: bypass, config: config} do
      sleep_calls = :counters.new(1, [:atomics])
      sleep_fun = fn _ms -> :counters.add(sleep_calls, 1, 1) end

      stub_sequence(bypass, [
        {500, %{"message" => "Internal error"}, []},
        {502, %{"message" => "Bad gateway"}, []},
        {503, %{"message" => "Service unavailable"}, []},
        {200, %{"status" => "completed", "result" => %{"data" => "success"}}, []}
      ])

      task = Future.poll("test-request-id", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"data" => "success"}} = Task.await(task, 5_000)
      assert :counters.get(sleep_calls, 1) == 0
    end

    test "handles mixed 408/5xx responses without backoff", %{bypass: bypass, config: config} do
      sleep_calls = :counters.new(1, [:atomics])
      sleep_fun = fn _ms -> :counters.add(sleep_calls, 1, 1) end

      stub_sequence(bypass, [
        {408, %{"message" => "Request timeout"}, []},
        {503, %{"message" => "Service unavailable"}, []},
        {408, %{"message" => "Request timeout"}, []},
        {500, %{"message" => "Internal error"}, []},
        {200, %{"status" => "completed", "result" => %{"data" => "finally"}}, []}
      ])

      task = Future.poll("test-request-id", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"data" => "finally"}} = Task.await(task, 5_000)
      assert :counters.get(sleep_calls, 1) == 0
    end
  end

  describe "poll_loop configurable backoff for 408/5xx" do
    test "backs off on 408 when poll_backoff is configured", %{bypass: bypass, config: config} do
      parent = self()
      sleep_fun = fn ms -> send(parent, {:slept, ms}) end
      backoff_fun = fn iteration -> 25 + iteration end

      config = %{config | poll_backoff: backoff_fun}

      stub_sequence(bypass, [
        {408, %{"message" => "Request timeout"}, []},
        {200, %{"status" => "completed", "result" => %{"data" => "success"}}, []}
      ])

      task = Future.poll("test-request-id", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"data" => "success"}} = Task.await(task, 5_000)
      assert_receive {:slept, 25}
      refute_receive {:slept, _}
    end

    test "backs off on 5xx when poll_backoff is configured", %{bypass: bypass, config: config} do
      parent = self()
      sleep_fun = fn ms -> send(parent, {:slept, ms}) end
      backoff_fun = fn iteration -> 40 + iteration end

      config = %{config | poll_backoff: backoff_fun}

      stub_sequence(bypass, [
        {503, %{"message" => "Service unavailable"}, []},
        {200, %{"status" => "completed", "result" => %{"data" => "success"}}, []}
      ])

      task = Future.poll("test-request-id", config: config, sleep_fun: sleep_fun)
      assert {:ok, %{"data" => "success"}} = Task.await(task, 5_000)
      assert_receive {:slept, 40}
      refute_receive {:slept, _}
    end
  end

  describe "poll_loop terminal errors" do
    test "stops on 410 (expired promise)", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 410, %{"message" => "Promise expired", "category" => "server"})
      end)

      task = Future.poll("test-request-id", config: config)
      assert {:error, %Error{status: 410}} = Task.await(task, 5_000)
    end

    test "stops on 4xx user errors (except 408)", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 400, %{"message" => "Bad request", "category" => "user"})
      end)

      task = Future.poll("test-request-id", config: config)
      assert {:error, %Error{status: 400, category: :user}} = Task.await(task, 5_000)
    end
  end

  describe "poll_loop max_retries=0 for HTTP layer (Python SDK parity)" do
    test "HTTP retry layer should not retry on 408", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {408, %{"message" => "Request timeout"}, []},
          {200, %{"status" => "completed", "result" => %{"value" => 42}}, []}
        ])

      task = Future.poll("test-request-id", config: config)
      assert {:ok, %{"value" => 42}} = Task.await(task, 5_000)
      assert Agent.get(counter, & &1) == 2
    end
  end

  describe "connection error handling" do
    test "continues polling on connection errors with backoff", %{config: config} do
      sleep_calls = :counters.new(1, [:atomics])
      connection_calls = :counters.new(1, [:atomics])

      sleep_fun = fn _ms ->
        :counters.add(sleep_calls, 1, 1)
        :ok
      end

      config =
        config
        |> Map.put(:http_client, ConnectionErrorClient)
        |> Map.update(:user_metadata, %{connection_error_counter: connection_calls}, fn meta ->
          Map.put(meta, :connection_error_counter, connection_calls)
        end)

      task =
        Future.poll("test-request-id",
          config: config,
          sleep_fun: sleep_fun
        )

      assert {:ok, %{"status" => "ok"}} = Task.await(task, 5_000)
      assert :counters.get(sleep_calls, 1) == 1
      assert :counters.get(connection_calls, 1) == 2
    end
  end

  describe "telemetry" do
    test "emits api_error telemetry for 5xx errors", %{bypass: bypass, config: config} do
      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])

      stub_sequence(bypass, [
        {503, %{"message" => "Service unavailable"}, []},
        {200, %{"status" => "completed", "result" => %{}}, []}
      ])

      task = Future.poll("test-request-id", config: config)
      _result = Task.await(task, 5_000)

      {:telemetry, _, _measurements, metadata} =
        TelemetryHelpers.assert_telemetry(
          [:tinkex, :future, :api_error],
          %{request_id: "test-request-id", status: 503}
        )

      assert metadata.status == 503
    end
  end
end
