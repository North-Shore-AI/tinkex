defmodule Tinkex.TrainingClientCustomLossTest do
  @moduledoc """
  Integration-style test for forward_backward_custom/4.

  Verifies gradients are sent back as weights and custom metrics are merged.
  """

  use Tinkex.HTTPCase, async: false

  alias Tinkex.TrainingClient
  alias Tinkex.Types.{Datum, ForwardBackwardOutput, ModelInput, TensorData}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "sends gradients as weights and returns ForwardBackwardOutput", %{
    bypass: bypass,
    config: config
  } do
    {:ok, weight_store} = Agent.start_link(fn -> nil end)
    {:ok, seq_store} = Agent.start_link(fn -> %{forward: [], backward: []} end)

    on_exit(fn ->
      if Process.alive?(weight_store), do: Agent.stop(weight_store, :normal, 100)
      if Process.alive?(seq_store), do: Agent.stop(seq_store, :normal, 100)
    end)

    forward_result = %{
      "loss_fn_output_type" => "cross_entropy",
      "loss_fn_outputs" => [
        %{
          "logprobs" => %{
            "data" => [-1.0, -2.0],
            "dtype" => "float32",
            "shape" => [2]
          }
        }
      ],
      "metrics" => %{"loss" => 2.0}
    }

    backward_result = %{
      "loss_fn_output_type" => "cross_entropy",
      "loss_fn_outputs" => [
        %{
          "logprobs" => %{
            "data" => [-0.5],
            "dtype" => "float32",
            "shape" => [1]
          }
        }
      ],
      "metrics" => %{"loss" => 0.25}
    }

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"custom-loss-model"}))

        "/api/v1/forward" ->
          payload = Jason.decode!(body)
          seq_id = payload["seq_id"]
          Agent.update(seq_store, fn m -> %{m | forward: m.forward ++ [seq_id]} end)

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"request_id" => "forward-#{seq_id}"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)
          seq_id = payload["seq_id"]
          Agent.update(seq_store, fn m -> %{m | backward: m.backward ++ [seq_id]} end)

          [datum_payload] = payload["forward_backward_input"]["data"]
          weights = get_in(datum_payload, ["loss_fn_inputs", "weights"])
          Agent.update(weight_store, fn _ -> weights end)

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"request_id" => "backward-#{seq_id}"}))

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)

          case payload["request_id"] do
            "forward-1" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(
                200,
                Jason.encode!(%{status: "completed", result: forward_result})
              )

            "backward-2" ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(
                200,
                Jason.encode!(%{status: "completed", result: backward_result})
              )

            other ->
              raise "Unexpected request_id #{inspect(other)}"
          end

        other ->
          raise "Unexpected path #{inspect(other)}"
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-custom-loss",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [
      %Datum{
        model_input: ModelInput.from_ints([1, 2]),
        loss_fn_inputs: %{
          "target_tokens" => TensorData.from_nx(Nx.tensor([10, 11], type: {:s, 64}))
        }
      }
    ]

    loss_fn = fn _data, [logprobs] ->
      loss = Nx.sum(logprobs)
      {loss, %{"custom_metric" => 7.0}}
    end

    {:ok, task} = TrainingClient.forward_backward_custom(client, data, loss_fn)
    assert {:ok, %ForwardBackwardOutput{} = output} = Task.await(task, 5_000)

    weights = Agent.get(weight_store, & &1)
    assert get_in(weights, ["data"]) == [-1.0, -1.0]
    assert get_in(weights, ["dtype"]) == "float32"

    seqs = Agent.get(seq_store, & &1)
    assert seqs.forward == [1]
    assert seqs.backward == [2]

    assert output.metrics["loss"] == 0.25
    assert output.metrics["custom_metric"] == 7.0
  end
end
