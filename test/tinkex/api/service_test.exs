defmodule Tinkex.API.ServiceTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Service
  alias Tinkex.Types.{GetServerCapabilitiesResponse, HealthResponse}

  setup :setup_http_client

  test "get_server_capabilities returns supported models", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        ~s({"supported_models":[{"model_name":"llama"},{"model_name":"qwen"}]})
      )
    end)

    assert {:ok, %GetServerCapabilitiesResponse{} = resp} =
             Service.get_server_capabilities(config: config)

    assert resp.supported_models == ["llama", "qwen"]
  end

  test "health_check returns ok status", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", "/api/v1/healthz", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"status":"ok"}))
    end)

    assert {:ok, %HealthResponse{status: "ok"}} = Service.health_check(config: config)
  end
end
