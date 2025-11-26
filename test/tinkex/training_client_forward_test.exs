defmodule Tinkex.TrainingClientForwardTest do
  @moduledoc """
  Tests for forward-only path in TrainingClient.

  The forward/4 function allows running inference without backward pass,
  returning logprobs that can be converted to Nx tensors via TensorData.to_nx/1.
  """

  use Tinkex.HTTPCase, async: false

  alias Tinkex.TrainingClient
  alias Tinkex.Types.{Datum, ModelInput, TensorData}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  describe "forward/4" do
    test "returns logprobs without backward pass", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_model" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"model_id":"model-forward-1"}))

          "/api/v1/forward" ->
            payload = Jason.decode!(body)
            # Verify we're getting forward request with forward_input field
            assert payload["forward_input"] != nil
            assert payload["model_id"] == "model-forward-1"

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"fwd-#{payload["seq_id"]}"}))

          "/api/v1/retrieve_future" ->
            _payload = Jason.decode!(body)

            # Forward result with logprobs
            result = %{
              "loss_fn_output_type" => "logprobs",
              "loss_fn_outputs" => [
                %{
                  "logprobs" => %{
                    "data" => [-0.5, -1.2, -0.8],
                    "dtype" => "float32",
                    "shape" => [3]
                  }
                }
              ],
              "metrics" => %{}
            }

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{status: "completed", result: result}))
        end
      end)

      {:ok, client} =
        TrainingClient.start_link(
          session_id: "sess-fwd-1",
          model_seq_id: 0,
          base_model: "base",
          config: config
        )

      data = [%Datum{model_input: ModelInput.from_ints([1, 2, 3])}]

      {:ok, task} = TrainingClient.forward(client, data, :cross_entropy)
      assert {:ok, output} = Task.await(task, 5_000)

      assert output.loss_fn_output_type == "logprobs"
      assert length(output.loss_fn_outputs) == 1

      # Verify logprobs can be converted to Nx tensor
      [first_output] = output.loss_fn_outputs
      logprobs_data = first_output["logprobs"]

      tensor_data = %TensorData{
        data: logprobs_data["data"],
        dtype: :float32,
        shape: logprobs_data["shape"]
      }

      nx_tensor = TensorData.to_nx(tensor_data)
      assert Nx.shape(nx_tensor) == {3}
      assert Nx.type(nx_tensor) == {:f, 32}
    end

    test "handles chunked data correctly", %{bypass: bypass, config: config} do
      {:ok, chunk_order} = Agent.start_link(fn -> [] end)

      Bypass.expect(bypass, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_model" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"model_id":"model-fwd-chunks"}))

          "/api/v1/forward" ->
            payload = Jason.decode!(body)
            Agent.update(chunk_order, &(&1 ++ [payload["seq_id"]]))

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"fwd-chunk-#{payload["seq_id"]}"}))

          "/api/v1/retrieve_future" ->
            payload = Jason.decode!(body)

            chunk_result = %{
              "loss_fn_output_type" => "logprobs",
              "loss_fn_outputs" => [%{"chunk" => payload["request_id"]}],
              "metrics" => %{}
            }

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{status: "completed", result: chunk_result}))
        end
      end)

      {:ok, client} =
        TrainingClient.start_link(
          session_id: "sess-fwd-chunks",
          model_seq_id: 0,
          base_model: "base",
          config: config
        )

      # Create 130 data items to force chunking (max_chunk_len is 128)
      data =
        Enum.map(1..130, fn idx ->
          %Datum{model_input: ModelInput.from_ints([idx])}
        end)

      {:ok, task} = TrainingClient.forward(client, data, :cross_entropy)
      assert {:ok, output} = Task.await(task, 5_000)

      # Should have processed 2 chunks (seq_ids start at 1 since 0 is used by create_model)
      assert Agent.get(chunk_order, & &1) == [1, 2]
      assert length(output.loss_fn_outputs) == 2
    end

    test "returns ForwardBackwardOutput with loss_fn_outputs", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect(bypass, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_model" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"model_id":"model-fwd-output"}))

          "/api/v1/forward" ->
            payload = Jason.decode!(body)

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"request_id":"fwd-out-#{payload["seq_id"]}"}))

          "/api/v1/retrieve_future" ->
            result = %{
              "loss_fn_output_type" => "logprobs",
              "loss_fn_outputs" => [
                %{
                  "logprobs" => %{
                    "data" => [-1.0, -2.0],
                    "dtype" => "float32",
                    "shape" => [2]
                  },
                  "token_ids" => [100, 200]
                }
              ],
              "metrics" => %{"inference_time_ms" => 42.5}
            }

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{status: "completed", result: result}))
        end
      end)

      {:ok, client} =
        TrainingClient.start_link(
          session_id: "sess-fwd-output",
          model_seq_id: 0,
          base_model: "base",
          config: config
        )

      data = [%Datum{model_input: ModelInput.from_ints([1, 2])}]

      {:ok, task} = TrainingClient.forward(client, data, :cross_entropy)
      assert {:ok, %Tinkex.Types.ForwardBackwardOutput{} = output} = Task.await(task, 5_000)

      # Verify output structure
      assert output.loss_fn_output_type == "logprobs"
      assert length(output.loss_fn_outputs) == 1
      assert output.metrics["inference_time_ms"] == 42.5

      # Verify loss_fn_outputs contain expected fields
      [first] = output.loss_fn_outputs
      assert first["token_ids"] == [100, 200]
      assert first["logprobs"]["data"] == [-1.0, -2.0]
    end
  end
end
