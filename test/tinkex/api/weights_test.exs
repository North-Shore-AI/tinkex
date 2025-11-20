defmodule Tinkex.API.WeightsTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Weights

  setup :setup_http_client

  describe "save_weights/2" do
    test "persists weights via API", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/save_weights", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"saved"}))
      end)

      {:ok, result} = Weights.save_weights(%{model_id: "m"}, config: config)
      assert result["status"] == "saved"
    end
  end

  describe "load_weights/2" do
    test "loads weights via API", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/load_weights", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"loaded"}))
      end)

      {:ok, result} = Weights.load_weights(%{model_id: "m"}, config: config)
      assert result["status"] == "loaded"
    end
  end

  describe "save_weights_for_sampler/2" do
    test "uses training pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      Bypass.expect_once(bypass, "POST", "/api/v1/save_weights_for_sampler", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"saved"}))
      end)

      {:ok, _} = Weights.save_weights_for_sampler(%{model_id: "m"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :training, path: "/api/v1/save_weights_for_sampler"}}
    end
  end
end
