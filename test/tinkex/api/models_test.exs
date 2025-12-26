defmodule Tinkex.API.ModelsTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.API.Models
  alias Tinkex.Types.{GetInfoResponse, UnloadModelResponse}

  setup :setup_http_client

  describe "get_info/2" do
    test "uses training pool and parses response", %{bypass: bypass, config: config} do
      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :http, :request, :start])

      Bypass.expect_once(bypass, "POST", "/api/v1/get_info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"model_id" => "model-123", "type" => "get_info"} = Jason.decode!(body)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"model_id":"model-123","model_data":{"model_name":"meta-llama/Llama-3","arch":"llama"},"type":"get_info"})
        )
      end)

      assert {:ok, %GetInfoResponse{} = resp} =
               Models.get_info(%{model_id: "model-123", type: "get_info"}, config: config)

      assert resp.model_id == "model-123"
      assert resp.model_data.model_name == "meta-llama/Llama-3"

      TelemetryHelpers.assert_telemetry(
        [:tinkex, :http, :request, :start],
        %{pool_type: :training, path: "/api/v1/get_info"}
      )
    end
  end

  describe "unload_model/2" do
    test "returns future maps when server responds with request_id", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", "/api/v1/unload_model", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"request_id":"unload-1"}))
      end)

      assert {:ok, %{"request_id" => "unload-1"}} =
               Models.unload_model(%{model_id: "model-123"}, config: config)
    end

    test "parses immediate responses", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/unload_model", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"model_id":"model-123","type":"unload_model"}))
      end)

      assert {:ok, %UnloadModelResponse{model_id: "model-123", type: "unload_model"}} =
               Models.unload_model(%{model_id: "model-123"}, config: config)
    end
  end
end
