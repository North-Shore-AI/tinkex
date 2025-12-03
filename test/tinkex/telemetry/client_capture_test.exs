defmodule Tinkex.Telemetry.ClientCaptureTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  import ExUnit.CaptureLog

  alias Tinkex.Config
  alias Tinkex.ServiceClient

  defmodule StubSessionManager do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    def start_session(config, server), do: GenServer.call(server, {:start_session, config})
    def stop_session(id, server), do: GenServer.call(server, {:stop_session, id})

    def init(:ok), do: {:ok, nil}

    def handle_call({:start_session, _config}, _from, state) do
      {:reply, {:ok, "session-1"}, state}
    end

    def handle_call({:stop_session, _id}, _from, state) do
      {:reply, :ok, state}
    end
  end

  defmodule MockReporter do
    use GenServer

    def start_link(opts \\ []) do
      owner = Keyword.get(opts, :owner, self())
      GenServer.start_link(__MODULE__, %{fatal: [], owner: owner}, opts)
    end

    def init(state), do: {:ok, state}

    def get_fatal(pid), do: GenServer.call(pid, :get_fatal)

    def handle_call(:get_fatal, _from, state) do
      {:reply, state.fatal, state}
    end

    def handle_call({:log_exception, exception, severity, :fatal}, _from, state) do
      {:reply, true, %{state | fatal: [{exception, severity} | state.fatal]}}
    end

    def handle_call({:log_exception, _exception, _severity, _kind}, _from, state) do
      {:reply, true, state}
    end

    def terminate(_reason, %{fatal: fatal, owner: owner}) do
      send(owner, {:mock_reporter_fatal, fatal})
      :ok
    end
  end

  test "service client wraps fatal exceptions with telemetry capture" do
    capture_log(fn ->
      previous_flag = Process.flag(:trap_exit, true)
      on_exit(fn -> Process.flag(:trap_exit, previous_flag) end)

      {:ok, reporter} = MockReporter.start_link(owner: self())
      {:ok, session_manager} = start_supervised(StubSessionManager)

      config = Config.new(api_key: "key", telemetry_enabled?: false)

      {:ok, pid} =
        ServiceClient.start_link(
          config: config,
          session_manager: session_manager,
          client_supervisor: :local
        )

      :sys.replace_state(pid, fn state ->
        %{state | telemetry: reporter, client_supervisor: :invalid_supervisor}
      end)

      assert catch_exit(ServiceClient.create_sampling_client(pid, base_model: "model"))

      fatal =
        if Process.alive?(reporter) do
          MockReporter.get_fatal(reporter)
        else
          assert_receive {:mock_reporter_fatal, fatal_events}
          fatal_events
        end

      assert length(fatal) == 1
    end)
  end
end
