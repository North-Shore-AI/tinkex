defmodule Tinkex.APITest do
  use Tinkex.HTTPCase, async: false
  import ExUnit.CaptureLog
  require Logger

  alias Tinkex.API
  alias Tinkex.API.Sampling
  alias Tinkex.API.Session
  alias Tinkex.API.Training
  alias Tinkex.Config

  setup :setup_http_client

  # Python parity: _base_client.py `_should_retry` retries on 408/409/429/5xx
  describe "post/3 retry logic (Python parity)" do
    @tag slow: true
    test "retries on 409 conflict (Python parity)", %{bypass: bypass, config: config} do
      # Python SDK retries on 409 (lock timeout) - _base_client.py line 725-727
      counter =
        stub_sequence(bypass, [
          {409, %{error: "Conflict/lock timeout"}, []},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    @tag slow: true
    test "retries on 5xx errors", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {503, %{error: "Service unavailable"}, []},
          {503, %{error: "Service unavailable"}, []},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 3
    end

    @tag slow: true
    test "retries on 408 timeout", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {408, %{error: "Request timeout"}, []},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    @tag slow: true
    test "retries on 429 with Retry-After", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {429, %{error: "Rate limited"}, [{"retry-after-ms", "10"}]},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    @tag slow: true
    test "parses Retry-After header in seconds", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {429, %{error: "Rate limited"}, [{"Retry-After", "1"}]},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "honors x-should-retry: false even on 5xx", %{bypass: bypass, config: config} do
      stub_with_headers(bypass, 503, %{error: "Don't retry"}, [{"x-should-retry", "false"}])

      {:error, error} = API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    @tag slow: true
    test "honors x-should-retry: true on 400", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {400, %{error: "Bad request"}, [{"x-should-retry", "true"}]},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "does not retry 4xx errors without override", %{bypass: bypass, config: config} do
      stub_error(bypass, 400, %{error: "Bad request"})

      {:error, error} = API.post("/test", %{}, config: config)
      assert error.status == 400
      assert error.category == :user
    end

    test "handles case-insensitive x-should-retry header", %{bypass: bypass, config: config} do
      stub_with_headers(bypass, 503, %{error: "Don't retry"}, [{"X-Should-Retry", "false"}])

      {:error, error} = API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "handles case-insensitive Retry-After header", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {429, %{error: "Rate limited"}, [{"RETRY-AFTER-MS", "5"}]},
          {200, %{result: "success"}, []}
        ])

      {:ok, result} = API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    @tag slow: true
    test "respects max_retries", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {503, %{error: "Error 1"}, []},
          {503, %{error: "Error 2"}, []},
          {503, %{error: "Error 3"}, []}
        ])

      {:error, error} = API.post("/test", %{}, config: config, max_retries: 1)
      assert error.status == 503
      assert Agent.get(counter, & &1) == 2
    end

    test "raises without config" do
      assert_raise KeyError, fn -> API.post("/test", %{}, []) end
    end
  end

  describe "error categorization" do
    test "parses error category from response", %{bypass: bypass, config: config} do
      stub_error(bypass, 400, %{error: "Bad input", category: "user"})

      {:error, error} = API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers :user category from 4xx", %{bypass: bypass, config: config} do
      stub_error(bypass, 422, %{error: "Validation failed"})

      {:error, error} = API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers :server category from 5xx", %{bypass: bypass, config: config} do
      stub_error(bypass, 500, %{error: "Internal error"})

      {:error, error} = API.post("/test", %{}, config: config, max_retries: 0)
      assert error.category == :server
    end
  end

  describe "connection errors" do
    test "handles connection refused", %{bypass: bypass, config: config} do
      Bypass.down(bypass)

      {:error, error} = API.post("/test", %{}, config: config, max_retries: 0)
      assert error.type == :api_connection
    end

    test "handles connection closed mid-request", %{config: base_config} do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, packet: :raw, reuseaddr: true, active: false])

      acceptor =
        Task.async(fn ->
          case :gen_tcp.accept(listener) do
            {:ok, socket} ->
              :gen_tcp.close(socket)

            _ ->
              :ok
          end
        end)

      {:ok, port} = :inet.port(listener)

      config =
        Config.new(
          api_key: base_config.api_key,
          http_pool: base_config.http_pool,
          base_url: "http://localhost:#{port}",
          timeout: 100
        )

      try do
        {:error, error} = API.post("/test", %{}, config: config, max_retries: 0)
        assert error.type == :api_connection
      after
        :gen_tcp.close(listener)
        Task.shutdown(acceptor, :brutal_kill)
      end
    end
  end

  describe "telemetry events" do
    test "emits start and stop events", %{bypass: bypass, config: config} do
      attach_telemetry([
        [:tinkex, :http, :request, :start],
        [:tinkex, :http, :request, :stop]
      ])

      stub_success(bypass, %{result: "ok"})

      API.post("/test", %{}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], %{system_time: _},
                      %{method: :post, path: "/test"}}

      assert_receive {:telemetry, [:tinkex, :http, :request, :stop], %{duration: duration},
                      %{result: :ok, path: "/test"}}

      assert duration > 0
    end

    test "includes pool_type in metadata", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])
      stub_success(bypass, %{result: "ok"})

      API.post("/test", %{}, config: config, pool_type: :training)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :training, path: "/test"}}
    end

    test "different endpoints use pool metadata", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      Bypass.expect_once(bypass, "POST", "/api/v1/forward_backward", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result":"ok"}))
      end)

      Training.forward_backward(%{}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :training, path: "/api/v1/forward_backward"}}

      Bypass.expect_once(bypass, "POST", "/api/v1/asample", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result":"ok"}))
      end)

      Sampling.sample_async(%{}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :sampling, path: "/api/v1/asample"}}

      Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id":"test"}))
      end)

      Session.create(%{}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :session, path: "/api/v1/create_session"}}
    end
  end

  describe "concurrent requests" do
    test "handles 20 concurrent requests via harness", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        Agent.update(counter, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result":"ok"}))
      end)

      operations =
        for idx <- 1..4 do
          {:call, {:post, "/test", %{sequence: idx}}}
        end

      scenario =
        ConcurrentHarness.simple_genserver_scenario(
          Tinkex.TestSupport.APIWorker,
          operations,
          5,
          server_opts: %{config: config},
          mailbox: [sampling_interval: 1],
          performance_expectations: [max_time_ms: 2_000],
          invariant: fn _pid, ctx ->
            assert ctx.metrics.total_operations == 20
          end,
          metadata: %{test: :concurrent_requests}
        )

      assert {:ok, report} = ConcurrentHarness.run(scenario)
      assert report.metrics.total_operations == 20
      assert Agent.get(counter, & &1) == 20

      Agent.stop(counter)
    end
  end

  describe "headers and redaction" do
    test "includes cloudflare headers when configured", %{bypass: bypass, config: config} do
      config =
        %Config{
          config
          | cf_access_client_id: "cf-id",
            cf_access_client_secret: "cf-secret"
        }

      Bypass.expect_once(bypass, "GET", "/cf", fn conn ->
        assert Plug.Conn.get_req_header(conn, "cf-access-client-id") == ["cf-id"]
        assert Plug.Conn.get_req_header(conn, "cf-access-client-secret") == ["cf-secret"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"ok":true}))
      end)

      assert {:ok, %{"ok" => true}} = API.get("/cf", config: config)
    end

    test "omits cloudflare headers when not configured", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/cf-missing", fn conn ->
        assert Plug.Conn.get_req_header(conn, "cf-access-client-id") == []
        assert Plug.Conn.get_req_header(conn, "cf-access-client-secret") == []

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"ok":true}))
      end)

      assert {:ok, %{"ok" => true}} = API.get("/cf-missing", config: config)
    end

    test "redacts secrets when dumping headers", %{bypass: bypass, config: config} do
      config =
        %Config{
          config
          | cf_access_client_secret: "super-secret",
            dump_headers?: true
        }

      Bypass.expect_once(bypass, "GET", "/dump", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"ok":true}))
      end)

      previous_level = Logger.level()

      log =
        capture_log([level: :debug], fn ->
          Logger.configure(level: :debug)
          assert {:ok, %{"ok" => true}} = API.get("/dump", config: config)
        end)

      Logger.configure(level: previous_level)

      refute log =~ "super-secret"
      refute log =~ "cf-access-client-secret"
      assert log =~ "[REDACTED]"
    end
  end
end
