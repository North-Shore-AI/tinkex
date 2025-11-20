defmodule Tinkex.API.ServiceTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Service

  setup :setup_http_client

  describe "create_model/2" do
    test "hits create_model endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/create_model", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"model_id":"m-1"}))
      end)

      {:ok, result} = Service.create_model(%{name: "model"}, config: config)
      assert result["model_id"] == "m-1"
    end
  end

  describe "create_sampling_session/2" do
    test "uses session pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      Bypass.expect_once(bypass, "POST", "/api/v1/create_sampling_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id":"sample-session"}))
      end)

      {:ok, _} = Service.create_sampling_session(%{model_id: "model"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :session, path: "/api/v1/create_sampling_session"}}
    end
  end
end
