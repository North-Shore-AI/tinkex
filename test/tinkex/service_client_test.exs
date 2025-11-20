defmodule Tinkex.ServiceClientTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Plug.Conn
  alias Tinkex.{Config, ServiceClient}

  defmodule TrainingClientStub do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, Map.new(opts)}
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

    {:ok, child1} = ServiceClient.create_lora_training_client(pid, base_model: "m1")
    {:ok, child2} = ServiceClient.create_lora_training_client(pid, base_model: "m2")

    assert %{model_seq_id: 0, session_id: "service-session-2"} = :sys.get_state(child1)
    assert %{model_seq_id: 1, session_id: "service-session-2"} = :sys.get_state(child2)

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

    {:ok, child1} = ServiceClient.create_sampling_client(pid, model: "m1")
    {:ok, child2} = ServiceClient.create_sampling_client(pid, model: "m2")

    assert %{sampling_client_id: 0, session_id: "service-session-3"} = :sys.get_state(child1)
    assert %{sampling_client_id: 1, session_id: "service-session-3"} = :sys.get_state(child2)

    GenServer.stop(pid)
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
    Bypass.stub(bypass, "POST", "/api/v1/heartbeat", fn conn ->
      Conn.resp(conn, 200, ~s({"ok":true}))
    end)
  end

  defp expect_create_session(bypass, session_id) do
    Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
      Conn.resp(conn, 200, ~s({"session_id":"#{session_id}"}))
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

  defp start_session_manager do
    name = :"session_manager_#{System.unique_integer([:positive])}"

    spec = %{
      id: {Tinkex.SessionManager, name},
      start:
        {Tinkex.SessionManager, :start_link, [[name: name, heartbeat_interval_ms: 1_000_000]]}
    }

    {:ok, _} = start_supervised(spec)
    name
  end
end
