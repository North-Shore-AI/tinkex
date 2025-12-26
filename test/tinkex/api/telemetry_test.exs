defmodule Tinkex.API.TelemetryTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.API.Telemetry

  setup :setup_http_client

  describe "send/2" do
    test "fires and forgets asynchronously", %{bypass: bypass, config: config} do
      parent = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        send(parent, :telemetry_received)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"ok"}))
      end)

      report =
        trace_messages(self(), fn ->
          assert :ok = Telemetry.send(%{event: "test"}, config: config)
          assert_receive :telemetry_received, 500
        end)

      assert :telemetry_received in report.messages
    end
  end

  describe "send_sync/2" do
    test "waits for response", %{bypass: bypass, config: config} do
      stub_success(bypass, %{status: "ok"})

      {:ok, result} = Telemetry.send_sync(%{event: "sync"}, config: config)
      assert result["status"] == "ok"
    end
  end
end
