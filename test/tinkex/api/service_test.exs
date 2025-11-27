defmodule Tinkex.API.ServiceTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Service
  alias Tinkex.Types.{GetServerCapabilitiesResponse, HealthResponse, SupportedModel}

  setup :setup_http_client

  test "get_server_capabilities returns supported models with metadata", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        ~s({"supported_models":[{"model_name":"llama","arch":"llama","model_id":"llama-3-8b"},{"model_name":"qwen","arch":"qwen2","model_id":"qwen2-72b"}]})
      )
    end)

    assert {:ok, %GetServerCapabilitiesResponse{} = resp} =
             Service.get_server_capabilities(config: config)

    assert length(resp.supported_models) == 2

    [llama, qwen] = resp.supported_models
    assert %SupportedModel{model_name: "llama", arch: "llama", model_id: "llama-3-8b"} = llama
    assert %SupportedModel{model_name: "qwen", arch: "qwen2", model_id: "qwen2-72b"} = qwen
  end

  test "get_server_capabilities handles backward compatible string format", %{
    bypass: bypass,
    config: config
  } do
    # Legacy format: just model names in objects without full metadata
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

    assert length(resp.supported_models) == 2
    assert Enum.all?(resp.supported_models, &match?(%SupportedModel{}, &1))

    # model_names/1 helper provides backward compatibility
    assert GetServerCapabilitiesResponse.model_names(resp) == ["llama", "qwen"]
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
