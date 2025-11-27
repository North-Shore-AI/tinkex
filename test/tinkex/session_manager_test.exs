defmodule Tinkex.SessionManagerTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Plug.Conn
  alias Tinkex.{Config, SessionManager}
  import ExUnit.CaptureLog

  defmodule SlowSessionAPI do
    def create(_request, config: _config) do
      delay = Application.get_env(:tinkex, :session_api_delay, 0)
      Process.sleep(delay)
      {:ok, %{"session_id" => "session-timeout"}}
    end

    def heartbeat(_request, config: _config), do: {:ok, %{}}
  end

  defmodule NoopSessionAPI do
    def create(_request, config: _config), do: {:ok, %{"session_id" => "session-missing"}}
    def heartbeat(_request, config: _config), do: {:ok, %{}}
  end

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    finch_name = start_test_finch(base_url)
    manager_name = start_session_manager(heartbeat_interval_ms: 1_000_000)

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

    Bypass.stub(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
      send(test_pid, :heartbeat_called)
      Conn.resp(conn, 200, ~s({"ok":true}))
    end)

    assert {:ok, "session-1"} = SessionManager.start_session(config, manager)

    send(manager, :heartbeat)
    assert_receive :heartbeat_called, 1_000
    assert Map.has_key?(sessions(manager), "session-1")

    SessionManager.stop_session("session-1", manager)
  end

  test "user-error heartbeats warn after sustained failure and keep the session", %{
    bypass: bypass,
    config: config
  } do
    test_pid = self()
    expect_create_session(bypass, "session-2")

    Bypass.stub(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
      send(test_pid, :heartbeat_error)
      Conn.resp(conn, 401, ~s({"error":"expired"}))
    end)

    manager =
      start_session_manager(
        heartbeat_interval_ms: 1_000_000,
        heartbeat_warning_after_ms: 50
      )

    assert {:ok, "session-2"} = SessionManager.start_session(config, manager)

    send(manager, :heartbeat)
    assert_receive :heartbeat_error, 1_000
    assert Map.has_key?(sessions(manager), "session-2")

    # Wait for warning threshold (50ms) to be exceeded using receive timeout
    # This is more idiomatic than Process.sleep per Supertester guidelines
    receive do
    after
      60 -> :ok
    end

    log =
      capture_log([level: :warning], fn ->
        send(manager, :heartbeat)
        assert_receive :heartbeat_error, 1_000
        # Sync with manager state to ensure heartbeat is fully processed
        _ = :sys.get_state(manager)
      end)

    assert log =~ "session-2"
    assert log =~ "Heartbeat has failed"
    assert Map.has_key?(sessions(manager), "session-2")
  end

  test "transient heartbeat errors keep the session", %{
    bypass: bypass,
    config: config,
    manager: manager
  } do
    test_pid = self()
    expect_create_session(bypass, "session-3")

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.stub(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
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

  test "heartbeat skips missing pool and retains session", %{config: config} do
    manager = start_session_manager(heartbeat_interval_ms: 1_000_000, session_api: NoopSessionAPI)
    config = %{config | http_pool: :missing_pool}

    {:ok, session_id} = SessionManager.start_session(config, manager)

    assert Process.whereis(config.http_pool) == nil

    log =
      capture_log([level: :warning], fn ->
        send(manager, :heartbeat)
        # Sync with manager state to ensure heartbeat is fully processed
        _ = :sys.get_state(manager)
      end)

    assert log =~ "Skipping heartbeat"
    assert Map.has_key?(sessions(manager), session_id)
  end

  test "removes session after configured failure count", %{bypass: bypass, config: config} do
    expect_create_session(bypass, "session-removal")

    Bypass.stub(bypass, "POST", "/api/v1/session_heartbeat", fn conn ->
      Conn.resp(conn, 500, ~s({"error":"fail"}))
    end)

    manager =
      start_session_manager(
        heartbeat_interval_ms: 1_000_000,
        max_failure_count: 0,
        heartbeat_warning_after_ms: 0
      )

    {:ok, session_id} = SessionManager.start_session(config, manager)

    capture_log([level: :warning], fn ->
      send(manager, :heartbeat)
      # Sync with manager state to ensure heartbeat is fully processed and session removed
      _ = :sys.get_state(manager)
    end)

    refute Map.has_key?(sessions(manager), session_id)
    table = sessions_table(manager)
    assert :ets.lookup(table, session_id) == []
  end

  defp expect_create_session(bypass, session_id, delay_ms \\ 0) do
    Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
      Process.sleep(delay_ms)
      Conn.resp(conn, 200, ~s({"session_id":"#{session_id}"}))
    end)
  end

  defp start_session_manager(opts) do
    name = Keyword.get(opts, :name, :"session_manager_#{System.unique_integer([:positive])}")
    sessions_table = Keyword.get(opts, :sessions_table, unique_sessions_table())
    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 1_000_000)
    heartbeat_warning_after_ms = Keyword.get(opts, :heartbeat_warning_after_ms, 120_000)
    session_api = Keyword.get(opts, :session_api, Tinkex.API.Session)
    max_failure_count = Keyword.get(opts, :max_failure_count)
    max_failure_duration_ms = Keyword.get(opts, :max_failure_duration_ms)

    manager_opts =
      [
        name: name,
        sessions_table: sessions_table,
        heartbeat_interval_ms: heartbeat_interval_ms,
        heartbeat_warning_after_ms: heartbeat_warning_after_ms,
        session_api: session_api
      ]
      |> maybe_put(:max_failure_count, max_failure_count)
      |> maybe_put(:max_failure_duration_ms, max_failure_duration_ms)

    spec =
      Supervisor.child_spec(
        {SessionManager, manager_opts},
        id: {SessionManager, name}
      )

    {:ok, _} = start_supervised(spec)
    name
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

  defp sessions_table(manager) do
    :sys.get_state(manager).sessions_table
  end

  defp unique_sessions_table do
    :"tinkex_sessions_#{System.unique_integer([:positive])}"
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  test "start_session respects config timeout", %{
    config: config
  } do
    short_config = %{config | timeout: 200}
    Application.put_env(:tinkex, :session_api_delay, short_config.timeout)

    child_spec =
      Supervisor.child_spec(
        {SessionManager,
         name: :"session_manager_timeout_#{System.unique_integer([:positive])}",
         heartbeat_interval_ms: 1_000_000,
         sessions_table: unique_sessions_table(),
         session_api: SlowSessionAPI},
        id: {:session_manager_timeout, System.unique_integer([:positive])}
      )

    {:ok, manager_pid} = start_supervised(child_spec)

    on_exit(fn -> Application.delete_env(:tinkex, :session_api_delay) end)

    assert {:ok, "session-timeout"} = SessionManager.start_session(short_config, manager_pid)
  end
end
