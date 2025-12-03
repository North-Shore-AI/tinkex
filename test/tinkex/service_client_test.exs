defmodule Tinkex.ServiceClientTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Plug.Conn
  alias Tinkex.{Config, ServiceClient}
  alias Tinkex.Types.LoraConfig

  defmodule TrainingClientStub do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, Map.new(opts)}
  end

  defmodule TrainingClientLoadStub do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, Map.new(opts)}

    def load_state(pid, path, _opts \\ []) do
      state = :sys.get_state(pid)
      if state[:test_pid], do: send(state.test_pid, {:load_state_called, path, state})
      {:ok, Task.async(fn -> {:ok, :loaded} end)}
    end

    def load_state_with_optimizer(pid, path, _opts \\ []) do
      state = :sys.get_state(pid)

      if state[:test_pid],
        do: send(state.test_pid, {:load_state_with_optimizer_called, path, state})

      {:ok, Task.async(fn -> {:ok, :loaded_opt} end)}
    end
  end

  defmodule SamplingClientStub do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, Map.new(opts)}
  end

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    finch_name = start_test_finch(base_url)
    manager = start_session_manager()

    config = Config.new(api_key: "test-key", base_url: base_url, http_pool: finch_name)

    {:ok, _} = Application.ensure_all_started(:tinkex)

    heartbeat_stub(bypass)

    on_exit(fn -> Bypass.down(bypass) end)

    {:ok, bypass: bypass, config: config, manager: manager}
  end

  test "start_link creates session via SessionManager", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-1")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    state = :sys.get_state(pid)
    assert state.session_id == "service-session-1"

    GenServer.stop(pid)
  end

  test "create_lora_training_client starts supervised child with sequencing", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-2")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    {:ok, child1} = ServiceClient.create_lora_training_client(pid, "m1")
    {:ok, child2} = ServiceClient.create_lora_training_client(pid, "m2")

    assert %{model_seq_id: 0, session_id: "service-session-2"} = :sys.get_state(child1)
    assert %{model_seq_id: 1, session_id: "service-session-2"} = :sys.get_state(child2)

    GenServer.stop(pid)
  end

  test "create_lora_training_client maps rank and training flags into lora_config", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-rank")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    {:ok, child} =
      ServiceClient.create_lora_training_client(pid, "m1",
        rank: 8,
        seed: 42,
        train_mlp: false,
        train_attn: true,
        train_unembed: false
      )

    state = :sys.get_state(child)

    assert %LoraConfig{
             rank: 8,
             seed: 42,
             train_mlp: false,
             train_attn: true,
             train_unembed: false
           } =
             state.lora_config

    refute Map.has_key?(state, :rank)

    GenServer.stop(pid)
  end

  test "create_lora_training_client rejects all train_* flags disabled", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-train-flags")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    opts = [train_mlp: false, train_attn: false, train_unembed: false]

    assert {:error, %Tinkex.Error{type: :validation}} =
             ServiceClient.create_lora_training_client(pid, "base-model", opts)

    task = ServiceClient.create_lora_training_client_async(pid, "base-model", opts)
    assert {:error, %Tinkex.Error{type: :validation}} = Task.await(task)

    GenServer.stop(pid)
  end

  test "create_sampling_client starts supervised child with sequencing", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-3")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    {:ok, child1} = ServiceClient.create_sampling_client(pid, base_model: "m1")
    {:ok, child2} = ServiceClient.create_sampling_client(pid, base_model: "m2")

    assert %{sampling_client_id: 0, session_id: "service-session-3"} = :sys.get_state(child1)
    assert %{sampling_client_id: 1, session_id: "service-session-3"} = :sys.get_state(child2)

    GenServer.stop(pid)
  end

  test "create_sampling_client validates presence of model_path or base_model", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-missing-model")

    {:ok, pid} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    assert {:error, %Tinkex.Error{type: :validation}} =
             ServiceClient.create_sampling_client(pid, [])

    task = ServiceClient.create_sampling_client_async(pid, [])
    assert {:error, %Tinkex.Error{type: :validation}} = Task.await(task)

    GenServer.stop(pid)
  end

  test "get_server_capabilities proxies through Service API", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-cap")

    expect_get_server_capabilities(bypass, %{
      "supported_models" => [
        %{"model_name" => "m1", "model_id" => "m1-id", "arch" => "llama"},
        %{"model_name" => "m2"}
      ]
    })

    {:ok, svc} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    assert {:ok, %Tinkex.Types.GetServerCapabilitiesResponse{} = resp} =
             ServiceClient.get_server_capabilities(svc)

    assert length(resp.supported_models) == 2
    [m1, m2] = resp.supported_models
    assert %Tinkex.Types.SupportedModel{model_name: "m1", model_id: "m1-id", arch: "llama"} = m1
    assert %Tinkex.Types.SupportedModel{model_name: "m2", model_id: nil, arch: nil} = m2

    GenServer.stop(svc)
  end

  test "create_training_client_from_state builds client from checkpoint metadata", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-5")

    expect_weights_info(bypass, "tinker://run/weights/ckpt-1", %{
      "base_model" => "meta/base",
      "is_lora" => true,
      "lora_rank" => 8
    })

    {:ok, svc} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientLoadStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    assert {:ok, client} =
             ServiceClient.create_training_client_from_state(
               svc,
               "tinker://run/weights/ckpt-1",
               test_pid: self()
             )

    assert_receive {:load_state_called, "tinker://run/weights/ckpt-1", state}, 2_000
    assert state.base_model == "meta/base"
    assert %LoraConfig{rank: 8} = state.lora_config
    assert state.model_seq_id == 0
    assert state.session_id == "service-session-5"

    GenServer.stop(client)
    GenServer.stop(svc)
  end

  test "create_training_client_from_state_with_optimizer loads optimizer state", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-6")

    expect_weights_info(bypass, "tinker://run/weights/ckpt-opt", %{
      "base_model" => "meta/opt-base",
      "is_lora" => true,
      "lora_rank" => 4
    })

    {:ok, svc} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientLoadStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    assert {:ok, client} =
             ServiceClient.create_training_client_from_state_with_optimizer(
               svc,
               "tinker://run/weights/ckpt-opt",
               test_pid: self()
             )

    assert_receive {:load_state_with_optimizer_called, "tinker://run/weights/ckpt-opt", state},
                   2_000

    assert state.base_model == "meta/opt-base"
    assert %LoraConfig{rank: 4} = state.lora_config

    GenServer.stop(client)
    GenServer.stop(svc)
  end

  test "create_training_client_from_state_with_optimizer_async returns task", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-async-opt")

    expect_weights_info(bypass, "tinker://run/weights/ckpt-async", %{
      "base_model" => "meta/opt-base",
      "is_lora" => true,
      "lora_rank" => 2
    })

    {:ok, svc} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientLoadStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    task =
      ServiceClient.create_training_client_from_state_with_optimizer_async(
        svc,
        "tinker://run/weights/ckpt-async",
        test_pid: self()
      )

    assert {:ok, client} = Task.await(task, 2_000)

    assert_receive {:load_state_with_optimizer_called, "tinker://run/weights/ckpt-async", _state},
                   2_000

    GenServer.stop(client)
    GenServer.stop(svc)
  end

  test "multiple service clients do not interfere", %{config: config} do
    bypass1 = Bypass.open()
    bypass2 = Bypass.open()

    base_url1 = "http://localhost:#{bypass1.port}"
    base_url2 = "http://localhost:#{bypass2.port}"

    finch1 = start_test_finch(base_url1)
    finch2 = start_test_finch(base_url2)

    config1 = %Config{config | base_url: base_url1, http_pool: finch1}
    config2 = %Config{config | base_url: base_url2, http_pool: finch2}

    manager1 = start_session_manager()
    manager2 = start_session_manager()

    heartbeat_stub(bypass1)
    heartbeat_stub(bypass2)
    expect_create_session(bypass1, "session-a")
    expect_create_session(bypass2, "session-b")

    {:ok, svc1} =
      ServiceClient.start_link(
        config: config1,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager1
      )

    {:ok, svc2} =
      ServiceClient.start_link(
        config: config2,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager2
      )

    assert :sys.get_state(svc1).session_id == "session-a"
    assert :sys.get_state(svc2).session_id == "session-b"

    GenServer.stop(svc1)
    GenServer.stop(svc2)
  end

  test "create_rest_client returns session/config", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    expect_create_session(bypass, "service-session-4")

    {:ok, svc} =
      ServiceClient.start_link(
        config: config,
        training_client_module: TrainingClientStub,
        sampling_client_module: SamplingClientStub,
        session_manager: manager
      )

    assert {:ok, %{session_id: "service-session-4", config: ^config}} =
             ServiceClient.create_rest_client(svc)

    GenServer.stop(svc)
  end

  defp heartbeat_stub(bypass) do
    Bypass.stub(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
      Conn.resp(conn, 200, ~s({"ok":true}))
    end)
  end

  defp expect_create_session(bypass, session_id) do
    Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
      Conn.resp(conn, 200, ~s({"session_id":"#{session_id}"}))
    end)
  end

  defp expect_weights_info(bypass, tinker_path, payload) do
    Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["tinker_path"] == tinker_path
      Conn.resp(conn, 200, Jason.encode!(payload))
    end)
  end

  defp expect_get_server_capabilities(bypass, payload) do
    Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
      Conn.resp(conn, 200, Jason.encode!(payload))
    end)
  end

  defp start_test_finch(_base_url) do
    name = :"finch_#{System.unique_integer([:positive])}"

    {:ok, _} =
      start_supervised(
        {Finch,
         name: name,
         pools: %{
           :default => [protocols: [:http1]]
         }}
      )

    name
  end

  defp start_session_manager(opts \\ []) do
    name = Keyword.get(opts, :name, :"session_manager_#{System.unique_integer([:positive])}")
    sessions_table = Keyword.get(opts, :sessions_table, unique_sessions_table())
    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 1_000_000)

    spec = %{
      id: {Tinkex.SessionManager, name},
      start:
        {Tinkex.SessionManager, :start_link,
         [
           [
             name: name,
             sessions_table: sessions_table,
             heartbeat_interval_ms: heartbeat_interval_ms
           ]
         ]}
    }

    {:ok, _} = start_supervised(spec)
    name
  end

  defp unique_sessions_table do
    :"tinkex_sessions_#{System.unique_integer([:positive])}"
  end
end
