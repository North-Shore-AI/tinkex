defmodule Tinkex.API.TrainingTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.Types.ForwardBackwardOutput
  alias Tinkex.Types.OptimStepResponse
  alias Tinkex.API.Training

  setup :setup_http_client

  describe "forward_backward/2" do
    test "polls future and returns typed output", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/forward_backward" ->
            assert Jason.decode!(body)["model_id"] == "test"

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"fw-1"}))

          "/api/v1/retrieve_future" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{
                status: "completed",
                result: %{
                  "loss_fn_output_type" => "mean",
                  "loss_fn_outputs" => [%{"idx" => 1}],
                  "metrics" => %{"loss" => 0.5}
                }
              })
            )
        end
      end)

      assert {:ok, %ForwardBackwardOutput{} = output} =
               Training.forward_backward(%{model_id: "test"}, config: config)

      assert output.metrics["loss"] == 0.5
    end

    test "uses training pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/forward_backward" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"fw-2"}))

          "/api/v1/retrieve_future" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{
                status: "completed",
                result: %{
                  "loss_fn_output_type" => "sum",
                  "loss_fn_outputs" => [],
                  "metrics" => %{"loss" => 0.25}
                }
              })
            )
        end
      end)

      {:ok, _} = Training.forward_backward(%{model_id: "model-123"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :training, path: "/api/v1/forward_backward"}}
    end
  end

  describe "optim_step/2" do
    test "polls future to completion", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/optim_step" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"opt-1"}))

          "/api/v1/retrieve_future" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{status: "completed", result: %{"metrics" => %{"lr" => 0.1}}})
            )
        end
      end)

      assert {:ok, %OptimStepResponse{} = response} =
               Training.optim_step(%{model_id: "model"}, config: config)

      assert response.metrics["lr"] == 0.1
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

  describe "forward_future/2 transform handling" do
    test "drops nil fields by default", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/forward", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        refute Map.has_key?(payload, "optional")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"request_id":"fw-nil"}))
      end)

      assert {:ok, %{"request_id" => "fw-nil"}} =
               Training.forward_future(%{model_id: "m", optional: nil}, config: config)
    end

    test "respects caller-provided transform options", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/forward", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert Map.has_key?(payload, "optional")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"request_id":"fw-keep-nil"}))
      end)

      assert {:ok, %{"request_id" => "fw-keep-nil"}} =
               Training.forward_future(
                 %{model_id: "m", optional: nil},
                 config: config,
                 transform: [drop_nil?: false]
               )
    end
  end
end
