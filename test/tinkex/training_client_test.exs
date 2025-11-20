defmodule Tinkex.TrainingClientTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.TrainingClient
  alias Tinkex.Types.{AdamParams, Datum, ForwardBackwardOutput, ModelInput, OptimStepResponse}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  defmodule PollingBoom do
    def poll(_future, _opts), do: Task.async(fn -> :ok end)
    def await(_task, _timeout), do: raise("boom")
  end

  test "forward_backward sends chunks sequentially and combines results", %{
    bypass: bypass,
    config: config
  } do
    {:ok, order} = Agent.start_link(fn -> [] end)

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-1"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)
          Agent.update(order, &(&1 ++ [payload["seq_id"]]))

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"req-#{payload["seq_id"]}"}))

        "/api/v1/future/retrieve" ->
          payload = Jason.decode!(body)

          chunk_result = %{
            "loss_fn_output_type" => "mean",
            "loss_fn_outputs" => [%{"chunk" => payload["request_id"]}],
            "metrics" => %{"loss" => if(payload["request_id"] == "req-0", do: 1.0, else: 3.0)}
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{status: "completed", result: chunk_result}))
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-1",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data =
      Enum.map(1..130, fn idx ->
        %Datum{model_input: ModelInput.from_ints([idx])}
      end)

    {:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
    assert {:ok, %ForwardBackwardOutput{} = output} = Task.await(task, 5_000)

    assert Agent.get(order, & &1) == [0, 1]
    assert length(output.loss_fn_outputs) == 2
    assert_in_delta output.metrics["loss"], 2.0, 0.001
  end

  test "forward_backward replies even when polling crashes", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-err"}))

        "/api/v1/forward_backward" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"req-crash"}))
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-err",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        future_module: PollingBoom
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
    assert {:error, %Tinkex.Error{type: :request_failed}} = Task.await(task, 5_000)
    assert Process.alive?(client)
  end

  test "optim_step polls future result", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-2"}))

        "/api/v1/optim_step" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"opt-2"}))

        "/api/v1/future/retrieve" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            Jason.encode!(%{status: "completed", result: %{"metrics" => %{"lr" => 0.5}}})
          )
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-2",
        model_seq_id: 1,
        base_model: "base",
        config: config
      )

    {:ok, task} = TrainingClient.optim_step(client, %AdamParams{learning_rate: 0.01})
    assert {:ok, %OptimStepResponse{} = response} = Task.await(task, 5_000)
    assert response.metrics["lr"] == 0.5
  end
end
