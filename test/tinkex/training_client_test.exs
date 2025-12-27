defmodule Tinkex.TrainingClientTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.{Config, TrainingClient}

  alias Tinkex.Types.{
    AdamParams,
    Datum,
    ForwardBackwardOutput,
    GetInfoResponse,
    LoadWeightsResponse,
    ModelInput,
    OptimStepResponse,
    SaveWeightsForSamplerResponse,
    SaveWeightsResponse,
    UnloadModelResponse
  }

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  defmodule PollingBoom do
    def poll(_future, _opts), do: Task.async(fn -> :ok end)
    def await(_task, _timeout), do: raise("boom")
  end

  defmodule ServiceStub do
    def create_model(_request, _opts), do: {:ok, %{"model_id" => "model-stub"}}
  end

  defmodule WeightsStub do
    def save_weights_for_sampler(_request, _opts) do
      response =
        :persistent_term.get({__MODULE__, :response}, %{"path" => "tinker://stub/sampler"})

      {:ok, response}
    end
  end

  defmodule SamplingClientStub do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def init(opts) do
      state = Map.new(opts)
      if state[:test_pid], do: send(state[:test_pid], {:sampling_client_started, state})
      {:ok, state}
    end
  end

  test "returns error when background task crashes", %{config: config} do
    :persistent_term.put({WeightsStub, :response}, %{"path" => "tinker://stub/sampler"})

    on_exit(fn ->
      :persistent_term.erase({WeightsStub, :response})
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-crash-task",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        service_api: ServiceStub,
        weights_api: WeightsStub,
        client_supervisor: :missing_supervisor
      )

    {:ok, task} = TrainingClient.save_weights_and_get_sampling_client(client)
    assert {:error, %Tinkex.Error{type: :request_failed} = error} = Task.await(task, 1_000)
    assert error.message =~ "Background task"
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

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)

          chunk_result = %{
            "loss_fn_output_type" => "mean",
            "loss_fn_outputs" => [%{"chunk" => payload["request_id"]}],
            "metrics" => %{"loss" => if(payload["request_id"] == "req-1", do: 1.0, else: 3.0)}
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
      Enum.map(1..1_025, fn idx ->
        %Datum{model_input: ModelInput.from_ints([idx])}
      end)

    {:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
    assert {:ok, %ForwardBackwardOutput{} = output} = Task.await(task, 5_000)

    # seq_ids start at 1 since 0 is used by create_model
    assert Agent.get(order, & &1) == [1, 2]
    assert length(output.loss_fn_outputs) == 2
    assert_in_delta output.metrics["loss"], 2.0, 0.001
  end

  test "forward_backward validates loss_fn client-side", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-validate-loss-fn"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)
          flunk("Unexpected /api/v1/forward_backward call: #{inspect(payload)}")

        other ->
          flunk("Unexpected request path: #{inspect(other)}")
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-validate-loss-fn",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} = TrainingClient.forward_backward(client, data, "mse")
    assert {:error, %Tinkex.Error{type: :validation} = error} = Task.await(task, 5_000)
    assert error.category == :user
    assert error.message =~ "Invalid loss_fn"
    assert "cross_entropy" in error.data.allowed
  end

  test "forward validates loss_fn client-side", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-validate-loss-fn-forward"}))

        "/api/v1/forward" ->
          payload = Jason.decode!(body)
          flunk("Unexpected /api/v1/forward call: #{inspect(payload)}")

        other ->
          flunk("Unexpected request path: #{inspect(other)}")
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-validate-loss-fn-forward",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} = TrainingClient.forward(client, data, :mse)
    assert {:error, %Tinkex.Error{type: :validation} = error} = Task.await(task, 5_000)
    assert error.category == :user
    assert error.message =~ "Invalid loss_fn"
    assert "cross_entropy" in error.data.allowed
  end

  test "forward_backward validates loss_fn_config client-side", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-validate-loss-fn-config"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)
          flunk("Unexpected /api/v1/forward_backward call: #{inspect(payload)}")

        other ->
          flunk("Unexpected request path: #{inspect(other)}")
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-validate-loss-fn-config",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} =
      TrainingClient.forward_backward(client, data, :cross_entropy,
        loss_fn_config: %{beta: "nope"}
      )

    assert {:error, %Tinkex.Error{type: :validation} = error} = Task.await(task, 5_000)
    assert error.category == :user
    assert error.message =~ "loss_fn_config"
  end

  test "forward validates loss_fn_config client-side", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-validate-loss-fn-config-forward"}))

        "/api/v1/forward" ->
          payload = Jason.decode!(body)
          flunk("Unexpected /api/v1/forward call: #{inspect(payload)}")

        other ->
          flunk("Unexpected request path: #{inspect(other)}")
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-validate-loss-fn-config-forward",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} =
      TrainingClient.forward(client, data, :cross_entropy, loss_fn_config: [:not_a_map])

    assert {:error, %Tinkex.Error{type: :validation} = error} = Task.await(task, 5_000)
    assert error.category == :user
    assert error.message =~ "loss_fn_config"
  end

  test "forward_backward normalizes loss_fn_config keys and values", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-normalize-loss-fn-config"}))

        "/api/v1/forward_backward" ->
          payload = Jason.decode!(body)

          assert payload["forward_backward_input"]["loss_fn_config"] == %{
                   "beta" => 1.0,
                   "clip" => 0.2
                 }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"req-#{payload["seq_id"]}"}))

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)

          chunk_result = %{
            "loss_fn_output_type" => "mean",
            "loss_fn_outputs" => [%{"chunk" => payload["request_id"]}],
            "metrics" => %{"loss" => 1.0}
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{status: "completed", result: chunk_result}))

        other ->
          flunk("Unexpected request path: #{inspect(other)}")
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-normalize-loss-fn-config",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    data = [%Datum{model_input: ModelInput.from_ints([1])}]

    {:ok, task} =
      TrainingClient.forward_backward(client, data, :cross_entropy,
        loss_fn_config: %{"clip" => "0.2", beta: 1}
      )

    assert {:ok, %ForwardBackwardOutput{}} = Task.await(task, 5_000)
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

        "/api/v1/retrieve_future" ->
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

  test "get_info returns typed response", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-info"}))

        "/api/v1/get_info" ->
          payload = Jason.decode!(body)
          assert payload["model_id"] == "model-info"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            ~s({"model_id":"model-info","model_data":{"tokenizer_id":"tok","model_name":"name"}})
          )
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-info",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    assert {:ok, %GetInfoResponse{} = info} = TrainingClient.get_info(client)
    assert info.model_data.tokenizer_id == "tok"
    assert info.model_id == "model-info"
  end

  test "unload_model polls future and parses response", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-unload"}))

        "/api/v1/unload_model" ->
          payload = Jason.decode!(body)
          assert payload["model_id"] == "model-unload"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"unload-req"}))

        "/api/v1/retrieve_future" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            ~s({"status":"completed","result":{"model_id":"model-unload","type":"unload_model"}})
          )
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-unload",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    assert {:ok, %UnloadModelResponse{model_id: "model-unload", type: "unload_model"}} =
             TrainingClient.unload_model(client)
  end

  test "save_state posts checkpoint request and returns typed response", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-save"}))

        "/api/v1/save_weights" ->
          payload = Jason.decode!(body)
          assert payload["path"] == "checkpoint-1"
          assert payload["model_id"] == "model-save"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"path":"tinker://model-save/weights/checkpoint-1"}))
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    {:ok, task} = TrainingClient.save_state(client, "checkpoint-1")
    assert {:ok, %SaveWeightsResponse{path: path}} = Task.await(task, 5_000)
    assert path =~ "checkpoint-1"
  end

  test "load_state_with_optimizer posts optimizer flag true", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-load"}))

        "/api/v1/load_weights" ->
          payload = Jason.decode!(body)
          assert payload["optimizer"] == true
          assert payload["path"] == "tinker://run/weights/ckpt-1"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"path":"tinker://run/weights/ckpt-1"}))
      end
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-load",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    {:ok, task} = TrainingClient.load_state_with_optimizer(client, "tinker://run/weights/ckpt-1")

    assert {:ok, %LoadWeightsResponse{path: "tinker://run/weights/ckpt-1"}} =
             Task.await(task, 5_000)
  end

  test "save_weights_for_sampler sends path from name argument", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "POST", "/api/v1/create_model", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"model_id":"model-save"}))
    end)

    Bypass.expect_once(bypass, "POST", "/api/v1/save_weights_for_sampler", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      # Name argument should be sent as path in the request
      assert payload["path"] == "sampler-weights"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"path":"tinker://samplers/ckpt-1"}))
    end)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save",
        model_seq_id: 0,
        base_model: "base",
        config: config
      )

    {:ok, task} = TrainingClient.save_weights_for_sampler(client, "sampler-weights")

    assert {:ok, %SaveWeightsForSamplerResponse{path: "tinker://samplers/ckpt-1"}} =
             Task.await(task, 5_000)

    GenServer.stop(client)
  end

  test "save_weights_and_get_sampling_client returns sampling client when path is provided" do
    :persistent_term.put({WeightsStub, :response}, %{"path" => "tinker://stub/sampler"})
    on_exit(fn -> :persistent_term.erase({WeightsStub, :response}) end)

    {:ok, client_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    config = Config.new(api_key: "tml-k", base_url: "http://example.com", http_pool: :stub_pool)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save-sampler",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        service_api: ServiceStub,
        weights_api: WeightsStub,
        client_supervisor: client_supervisor,
        sampling_client_module: SamplingClientStub
      )

    {:ok, task} =
      TrainingClient.save_weights_and_get_sampling_client(client,
        test_pid: self()
      )

    assert {:ok, sampling_pid} = Task.await(task, 5_000)
    assert is_pid(sampling_pid)

    assert_receive {:sampling_client_started, opts}, 2_000
    opts_map = Map.new(opts)
    assert opts_map[:model_path] == "tinker://stub/sampler"
    refute Map.has_key?(opts_map, :sampling_session_id)
  end

  test "save_weights_and_get_sampling_client supports sampling_session_id-only responses" do
    :persistent_term.put({WeightsStub, :response}, %{
      "sampling_session_id" => "session:sample:ephemeral"
    })

    on_exit(fn -> :persistent_term.erase({WeightsStub, :response}) end)

    {:ok, client_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    config = Config.new(api_key: "tml-k", base_url: "http://example.com", http_pool: :stub_pool)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save-sampler-ephemeral",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        service_api: ServiceStub,
        weights_api: WeightsStub,
        client_supervisor: client_supervisor,
        sampling_client_module: SamplingClientStub
      )

    {:ok, task} =
      TrainingClient.save_weights_and_get_sampling_client(client,
        test_pid: self()
      )

    assert {:ok, sampling_pid} = Task.await(task, 5_000)
    assert is_pid(sampling_pid)

    assert_receive {:sampling_client_started, opts}, 2_000
    opts_map = Map.new(opts)
    assert opts_map[:sampling_session_id] == "session:sample:ephemeral"
    refute Map.has_key?(opts_map, :model_path)
  end

  test "save_weights_and_get_sampling_client_sync returns pid (path response)" do
    :persistent_term.put({WeightsStub, :response}, %{"path" => "tinker://stub/sampler-sync"})
    on_exit(fn -> :persistent_term.erase({WeightsStub, :response}) end)

    {:ok, client_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    config = Config.new(api_key: "tml-k", base_url: "http://example.com", http_pool: :stub_pool)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save-sampler-sync",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        service_api: ServiceStub,
        weights_api: WeightsStub,
        client_supervisor: client_supervisor,
        sampling_client_module: SamplingClientStub,
        test_pid: self()
      )

    assert {:ok, pid} =
             TrainingClient.save_weights_and_get_sampling_client_sync(client, test_pid: self())

    assert is_pid(pid)
    assert_receive {:sampling_client_started, state}, 2_000
    assert state.model_path == "tinker://stub/sampler-sync"
  end

  test "save_weights_and_get_sampling_client_sync returns pid (sampling_session_id response)" do
    :persistent_term.put({WeightsStub, :response}, %{
      "sampling_session_id" => "session:sample:sync"
    })

    on_exit(fn -> :persistent_term.erase({WeightsStub, :response}) end)

    {:ok, client_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    config = Config.new(api_key: "tml-k", base_url: "http://example.com", http_pool: :stub_pool)

    {:ok, client} =
      TrainingClient.start_link(
        session_id: "sess-save-sampler-sync-ephemeral",
        model_seq_id: 0,
        base_model: "base",
        config: config,
        service_api: ServiceStub,
        weights_api: WeightsStub,
        client_supervisor: client_supervisor,
        sampling_client_module: SamplingClientStub,
        test_pid: self()
      )

    assert {:ok, pid} =
             TrainingClient.save_weights_and_get_sampling_client_sync(client, test_pid: self())

    assert is_pid(pid)
    assert_receive {:sampling_client_started, state}, 2_000
    assert state.sampling_session_id == "session:sample:sync"
    refute Map.has_key?(state, :model_path)
  end
end
