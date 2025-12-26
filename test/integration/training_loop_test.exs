defmodule Tinkex.Integration.TrainingLoopTest do
  use Tinkex.HTTPCase, async: true

  require Logger

  alias Tinkex.{ServiceClient, TrainingClient}
  alias Tinkex.Types.{AdamParams, Datum, ForwardBackwardOutput, ModelInput, OptimStepResponse}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "runs end-to-end training loop with chunking and save weights", %{
    bypass: bypass,
    config: config
  } do
    request_log = start_supervised!({Agent, fn -> [] end})

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"integration-session"}))

        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-integration"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)
          Agent.update(request_log, &(&1 ++ [{:forward, payload["seq_id"]}]))

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"request_id" => "fw-#{payload["seq_id"]}"}))

        "/api/v1/optim_step" ->
          payload = Jason.decode!(body)
          Agent.update(request_log, &(&1 ++ [{:optim, payload["seq_id"]}]))

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"request_id" => "opt-#{payload["seq_id"]}"}))

        "/api/v1/save_weights_for_sampler" ->
          payload = Jason.decode!(body)
          Agent.update(request_log, &(&1 ++ [{:save, payload["seq_id"]}]))

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"request_id" => "save-#{payload["seq_id"]}"}))

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)

          # seq_ids start at 1 since 0 is used by create_model
          response =
            case payload["request_id"] do
              "fw-1" ->
                %{
                  status: "completed",
                  result: %{
                    "loss_fn_output_type" => "mean",
                    "loss_fn_outputs" => [%{"chunk" => 0}],
                    "metrics" => %{"loss" => 1.0, "grad:sum" => 10.0}
                  }
                }

              "fw-2" ->
                %{
                  status: "completed",
                  result: %{
                    "loss_fn_output_type" => "mean",
                    "loss_fn_outputs" => [%{"chunk" => 1}, %{"chunk" => 2}, %{"chunk" => 3}],
                    "metrics" => %{"loss" => 3.0, "grad:sum" => 20.0}
                  }
                }

              "opt-3" ->
                %{status: "completed", result: %{"metrics" => %{"lr" => 0.02}}}

              "save-4" ->
                %{
                  status: "completed",
                  result: %{"status" => "saved", "path" => "/weights/mock.bin"}
                }

              other ->
                flunk("Unexpected future request #{inspect(other)}")
            end

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(response))

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    {:ok, service} = ServiceClient.start_link(config: config)

    {:ok, training} =
      ServiceClient.create_lora_training_client(service, "integration-base")

    data =
      Enum.map(1..1_025, fn idx ->
        %Datum{model_input: ModelInput.from_ints([idx])}
      end)

    loop_start = System.monotonic_time(:millisecond)

    {:ok, fb_task} =
      TrainingClient.forward_backward(training, data, :cross_entropy, sleep_fun: fn _ -> :ok end)

    assert {:ok, %ForwardBackwardOutput{} = output} = Task.await(fb_task, 5_000)
    assert Agent.get(request_log, &Enum.slice(&1, 0, 2)) == [{:forward, 1}, {:forward, 2}]

    assert length(output.loss_fn_outputs) == 4
    assert_in_delta output.metrics["loss"], 2.5, 0.001
    assert output.metrics["grad:sum"] == 30.0

    {:ok, optim_task} = TrainingClient.optim_step(training, %AdamParams{learning_rate: 0.02})
    assert {:ok, %OptimStepResponse{} = optim_result} = Task.await(optim_task, 5_000)
    assert optim_result.metrics["lr"] == 0.02

    {:ok, save_task} = TrainingClient.save_weights_for_sampler(training, "/tmp/mock.bin")

    assert {:ok, %{"path" => "/weights/mock.bin", "status" => "saved"}} =
             Task.await(save_task, 5_000)

    total_duration = System.monotonic_time(:millisecond) - loop_start
    Logger.info("training loop completed in #{total_duration}ms (integration test)")

    assert Agent.get(request_log, & &1) == [{:forward, 1}, {:forward, 2}, {:optim, 3}, {:save, 4}]

    GenServer.stop(service)
  end
end
