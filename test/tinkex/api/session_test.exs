defmodule Tinkex.API.SessionTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Session
  alias Tinkex.Types.CreateSessionResponse

  setup :setup_http_client

  describe "create/2" do
    test "creates session via API", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id":"session-123"}))
      end)

      {:ok, result} = Session.create(%{model_id: "model"}, config: config)
      assert result["session_id"] == "session-123"
    end
  end

  describe "create_typed/2" do
    test "returns typed response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id":"typed", "info_message":"ok"}))
      end)

      {:ok, %CreateSessionResponse{} = resp} =
        Session.create_typed(%{model_id: "model"}, config: config)

      assert resp.session_id == "typed"
      assert resp.info_message == "ok"
    end
  end

  describe "heartbeat/2" do
    test "uses session pool and correct path", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      Bypass.expect_once(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"alive"}))
      end)

      {:ok, _} = Session.heartbeat(%{session_id: "session-123"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :session, path: "/api/v1/session_heartbeat"}}
    end
  end
end
