defmodule Tinkex.SessionManagerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Plug.Conn
  alias Tinkex.{Config, SessionManager}

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    finch_name = start_test_finch(base_url)
    manager_name = :"session_manager_#{System.unique_integer([:positive])}"

    {:ok, _} =
      start_supervised({SessionManager, name: manager_name, heartbeat_interval_ms: 1_000_000})

    config = Config.new(api_key: "test-key", base_url: base_url, http_pool: finch_name)

    {:ok, _} = Application.ensure_all_started(:tinkex)

    on_exit(fn ->
      Bypass.down(bypass)
    end)

    {:ok, bypass: bypass, config: config, manager: manager_name}
  end

  test "start_session registers and heartbeats succeeding keep session", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    test_pid = self()

    expect_create_session(bypass, "session-1")

    Bypass.stub(bypass, "POST", "/api/v1/heartbeat", fn conn ->
      send(test_pid, :heartbeat_called)
      Conn.resp(conn, 200, ~s({"ok":true}))
    end)

    assert {:ok, "session-1"} = SessionManager.start_session(config, manager)

    send(manager, :heartbeat)
    assert_receive :heartbeat_called, 1_000
    assert Map.has_key?(sessions(manager), "session-1")

    SessionManager.stop_session("session-1", manager)
  end

  test "user-error heartbeats drop the session", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    test_pid = self()
    expect_create_session(bypass, "session-2")

    Bypass.stub(bypass, "POST", "/api/v1/heartbeat", fn conn ->
      send(test_pid, :heartbeat_error)
      Conn.resp(conn, 401, ~s({"error":"expired"}))
    end)

    assert {:ok, "session-2"} = SessionManager.start_session(config, manager)

    send(manager, :heartbeat)
    assert_receive :heartbeat_error, 1_000

    refute Map.has_key?(sessions(manager), "session-2")
  end

  test "transient heartbeat errors keep the session", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    test_pid = self()
    expect_create_session(bypass, "session-3")

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.stub(bypass, "POST", "/api/v1/heartbeat", fn conn ->
      count = Agent.get_and_update(counter, fn current -> {current + 1, current + 1} end)

      status = if count == 1, do: 500, else: 200
      send(test_pid, {:heartbeat_status, status})
      Conn.resp(conn, status, ~s({"count":#{count}}))
    end)

    assert {:ok, "session-3"} = SessionManager.start_session(config, manager)

    send(manager, :heartbeat)
    assert_receive {:heartbeat_status, 500}, 1_000
    assert Map.has_key?(sessions(manager), "session-3")

    send(manager, :heartbeat)
    assert_receive {:heartbeat_status, 200}, 1_000
    assert Map.has_key?(sessions(manager), "session-3")

    SessionManager.stop_session("session-3", manager)
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

  defp sessions(manager) do
    :sys.get_state(manager).sessions
  end
end
