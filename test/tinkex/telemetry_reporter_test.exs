defmodule Tinkex.TelemetryReporterTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.Telemetry.Reporter

  import ExUnit.CaptureLog

  setup :setup_http_client

  describe "basic functionality" do
    test "flushes queued events to the telemetry endpoint", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "session-123",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      assert Reporter.log(reporter, "event-one", %{foo: 1})
      assert Reporter.log(reporter, "event-two", %{})

      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500
      assert payload["session_id"] == "session-123"

      # session_start + two generic events
      assert length(payload["events"]) == 3
    end

    test "captures HTTP telemetry events when session_id metadata matches", %{
      bypass: bypass,
      config: config
    } do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"ok":true}))
      end)

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "sess-http",
          config: config,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      assert {:ok, %{"ok" => true}} ==
               Tinkex.API.post("/test", %{},
                 config: config,
                 telemetry_metadata: %{session_id: "sess-http"}
               )

      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500

      names = Enum.map(payload["events"], & &1["event_name"])
      assert "tinkex.http.request.stop" in names
    end

    test "fatal exceptions emit session_end and flush synchronously", %{
      bypass: bypass,
      config: config
    } do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "fatal-session",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      exception = RuntimeError.exception("boom")

      # log_fatal_exception should return true and flush synchronously
      assert Reporter.log_fatal_exception(reporter, exception, :error)

      assert_receive {:telemetry_payload, payload}, 500
      events = Enum.map(payload["events"], & &1["event"])
      assert "UNHANDLED_EXCEPTION" in events
      assert "SESSION_END" in events
    end
  end

  describe "stop/2" do
    test "stops the reporter gracefully with session_end event", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "stop-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      assert Reporter.log(reporter, "before-stop", %{})
      assert :ok = Reporter.stop(reporter)

      assert_receive {:telemetry_payload, payload}, 500
      events = Enum.map(payload["events"], & &1["event"])
      assert "SESSION_START" in events
      assert "SESSION_END" in events
      assert "GENERIC_EVENT" in events
    end

    test "returns false for nil pid" do
      assert Reporter.stop(nil) == false
    end
  end

  describe "wait_until_drained/2" do
    test "returns true when queue is already drained", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "drain-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      # Flush to send session_start
      :ok = Reporter.flush(reporter, sync?: true)

      # Now queue should be drained
      assert Reporter.wait_until_drained(reporter, 1_000) == true
    end

    test "returns false for nil pid" do
      assert Reporter.wait_until_drained(nil) == false
    end
  end

  describe "retry with backoff" do
    test "retries failed sends with exponential backoff", %{bypass: bypass, config: config} do
      parent = self()
      attempt_count = :counters.new(1, [:atomics])

      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        :counters.add(attempt_count, 1, 1)
        current = :counters.get(attempt_count, 1)
        send(parent, {:attempt, current})

        if current < 3 do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(500, ~s({"error":"server error"}))
        else
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          send(parent, {:telemetry_payload, payload})

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
        end
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "retry-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          max_retries: 3,
          retry_base_delay_ms: 100,
          enabled: true
        )

      log =
        capture_log(fn ->
          :ok = Reporter.flush(reporter, sync?: true)
        end)

      # Should have retried
      assert log =~ "retrying"

      # Should eventually succeed
      assert_receive {:telemetry_payload, _payload}, 5_000
    end

    test "gives up after max_retries", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, ~s({"error":"server error"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "max-retry-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          max_retries: 2,
          retry_base_delay_ms: 50,
          enabled: true
        )

      log =
        capture_log(fn ->
          :ok = Reporter.flush(reporter, sync?: true)
        end)

      # Should log final failure
      assert log =~ "failed after 2 retries"
    end
  end

  describe "exception cause chain traversal" do
    test "finds user error in wrapped exception", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "chain-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      # Create a user error (400 status)
      user_error = %{
        __struct__: BadRequestError,
        __exception__: true,
        status: 400,
        message: "bad request"
      }

      assert Reporter.log_exception(reporter, user_error, :error)
      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500

      # Should be logged as user_error, not UNHANDLED_EXCEPTION
      user_events =
        payload["events"]
        |> Enum.filter(&(&1["event"] == "GENERIC_EVENT" and &1["event_name"] == "user_error"))

      assert length(user_events) == 1
      [event] = user_events
      assert event["event_data"]["status_code"] == 400
    end

    test "logs system errors as UNHANDLED_EXCEPTION", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "system-error-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      # 500 errors are system errors, not user errors
      server_error = %{
        __struct__: ServerError,
        __exception__: true,
        status: 500,
        message: "internal error"
      }

      assert Reporter.log_exception(reporter, server_error, :error)
      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500

      # Should be logged as UNHANDLED_EXCEPTION
      exception_events =
        payload["events"]
        |> Enum.filter(&(&1["event"] == "UNHANDLED_EXCEPTION"))

      assert length(exception_events) == 1
    end

    test "excludes 408 and 429 from user errors", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "timeout-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      # 408 (timeout) should be system error
      timeout_error = %{
        __struct__: TimeoutError,
        __exception__: true,
        status: 408,
        message: "timeout"
      }

      assert Reporter.log_exception(reporter, timeout_error, :error)
      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500

      # Should be UNHANDLED_EXCEPTION, not user_error
      exception_events =
        payload["events"]
        |> Enum.filter(&(&1["event"] == "UNHANDLED_EXCEPTION"))

      assert length(exception_events) == 1
    end
  end

  describe "stacktrace capture" do
    test "includes traceback in exception events", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(parent, {:telemetry_payload, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "stacktrace-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      exception = RuntimeError.exception("test error for stacktrace")
      assert Reporter.log_exception(reporter, exception, :error)
      :ok = Reporter.flush(reporter, sync?: true)

      assert_receive {:telemetry_payload, payload}, 500

      exception_events =
        payload["events"]
        |> Enum.filter(&(&1["event"] == "UNHANDLED_EXCEPTION"))

      assert length(exception_events) == 1
      [event] = exception_events

      # Traceback should be present and non-empty
      assert is_binary(event["traceback"])
      assert event["traceback"] != ""
      assert event["error_message"] == "test error for stacktrace"
    end
  end

  describe "flush with wait_drained option" do
    test "waits until events are flushed", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        # Simulate slow endpoint
        Process.sleep(100)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "wait-drained-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      assert Reporter.log(reporter, "test-event", %{})

      # This should block until all events are flushed
      :ok = Reporter.flush(reporter, sync?: true, wait_drained?: true)

      # After flush with wait_drained, wait_until_drained should return immediately
      assert Reporter.wait_until_drained(reporter, 100) == true
    end
  end

  describe "disabled telemetry" do
    test "returns :ignore when disabled via option" do
      config = Tinkex.Config.new(api_key: "test-key", base_url: "http://localhost")

      assert :ignore =
               Reporter.start_link(
                 session_id: "disabled-test",
                 config: config,
                 enabled: false
               )
    end
  end

  describe "nil pid handling" do
    test "all public functions return false/false for nil pid" do
      assert Reporter.log(nil, "event", %{}) == false
      assert Reporter.log_exception(nil, RuntimeError.exception("test"), :error) == false
      assert Reporter.log_fatal_exception(nil, RuntimeError.exception("test"), :error) == false
      assert Reporter.flush(nil) == false
      assert Reporter.stop(nil) == false
      assert Reporter.wait_until_drained(nil) == false
    end
  end

  describe "push/flush counters" do
    test "counters track events correctly", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/api/v1/telemetry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      {:ok, reporter} =
        Reporter.start_link(
          session_id: "counter-test",
          config: config,
          attach_events?: false,
          flush_interval_ms: 0,
          flush_threshold: 1_000,
          enabled: true
        )

      # Log multiple events
      for i <- 1..5 do
        assert Reporter.log(reporter, "event-#{i}", %{i: i})
      end

      # Flush and wait
      :ok = Reporter.flush(reporter, sync?: true)

      # Should be fully drained
      assert Reporter.wait_until_drained(reporter, 1_000) == true
    end
  end
end
