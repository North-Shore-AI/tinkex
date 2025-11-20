defmodule Tinkex.API.TrainingTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Training

  setup :setup_http_client

  describe "forward_backward/2" do
    test "sends request to correct endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/forward_backward", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"metrics":{"loss":0.5}}))
      end)

      {:ok, result} = Training.forward_backward(%{model_id: "test"}, config: config)
      assert result["metrics"]["loss"] == 0.5
    end

    test "uses training pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])
      stub_success(bypass, %{metrics: %{loss: 0.25}})

      {:ok, _} = Training.forward_backward(%{model_id: "model-123"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :training, path: "/api/v1/forward_backward"}}
    end
  end

  describe "optim_step/2" do
    test "sends request to correct endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/optim_step", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"updated"}))
      end)

      {:ok, result} = Training.optim_step(%{model_id: "model"}, config: config)
      assert result["status"] == "updated"
    end
  end

  describe "forward/2" do
    test "issues inference-only request", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/forward", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result":"ok"}))
      end)

      assert {:ok, %{"result" => "ok"}} = Training.forward(%{inputs: []}, config: config)
    end
  end
end
