defmodule Tinkex.AsyncClientTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.{ServiceClient, SamplingClient, TrainingClient}

  setup :setup_http_client

  setup %{bypass: bypass, config: config} do
    # Stub session creation
    Bypass.stub(bypass, "POST", "/api/v1/create_session", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"session_id": "session-123"}))
    end)

    # Stub sampling session creation
    Bypass.stub(bypass, "POST", "/api/v1/create_sampling_session", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"sampling_session_id": "sampler-456"}))
    end)

    # Stub model creation
    Bypass.stub(bypass, "POST", "/api/v1/create_model", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"model_id": "model-789"}))
    end)

    {:ok, service_pid} = ServiceClient.start_link(config: config)

    on_exit(fn ->
      if Process.alive?(service_pid), do: GenServer.stop(service_pid)
    end)

    {:ok, service_pid: service_pid, bypass: bypass, config: config}
  end

  describe "ServiceClient.create_sampling_client_async/2" do
    test "returns Task that resolves to sampling client", %{service_pid: service_pid} do
      task =
        ServiceClient.create_sampling_client_async(
          service_pid,
          base_model: "meta-llama/Llama-3.2-1B"
        )

      assert %Task{} = task

      {:ok, pid} = Task.await(task, 5000)
      assert is_pid(pid)

      GenServer.stop(pid)
    end

    test "multiple async creates can run concurrently", %{service_pid: service_pid} do
      tasks =
        for _i <- 1..3 do
          ServiceClient.create_sampling_client_async(
            service_pid,
            base_model: "meta-llama/Llama-3.2-1B"
          )
        end

      results = Task.await_many(tasks, 10_000)

      assert length(results) == 3

      for {:ok, pid} <- results do
        assert is_pid(pid)
        GenServer.stop(pid)
      end
    end
  end

  describe "SamplingClient.create_async/2" do
    test "returns Task that resolves to sampling client pid", %{service_pid: service_pid} do
      task =
        SamplingClient.create_async(
          service_pid,
          base_model: "meta-llama/Llama-3.2-1B"
        )

      assert %Task{} = task

      {:ok, pid} = Task.await(task, 5000)
      assert is_pid(pid)

      GenServer.stop(pid)
    end
  end

  describe "TrainingClient.create_sampling_client_async/3" do
    test "returns Task that resolves to sampling client", %{bypass: _bypass, config: config} do
      # Need fresh service client for this test to avoid shutdown issues
      {:ok, service_pid} = ServiceClient.start_link(config: config)

      # Create training client first
      {:ok, training_pid} =
        ServiceClient.create_lora_training_client(
          service_pid,
          base_model: "meta-llama/Llama-3.2-1B"
        )

      # Create sampling client async from training client
      task =
        TrainingClient.create_sampling_client_async(
          training_pid,
          "tinker://run-1/weights/0001"
        )

      assert %Task{} = task

      {:ok, sampling_pid} = Task.await(task, 5000)
      assert is_pid(sampling_pid)

      # Cleanup in order
      GenServer.stop(sampling_pid)
      GenServer.stop(training_pid)
      GenServer.stop(service_pid)
    end
  end
end
