defmodule Tinkex.SessionManager do
  @moduledoc """
  Manages Tinkex sessions and heartbeats across multiple configs.
  """

  use GenServer
  require Logger

  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.Types.CreateSessionResponse

  @type session_id :: String.t()
  @type state :: %{
          sessions: %{session_id() => %{config: Config.t()}},
          heartbeat_interval_ms: non_neg_integer()
        }

  @doc """
  Start the SessionManager process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Create a new session for the given config.
  """
  @spec start_session(Config.t(), GenServer.server()) :: {:ok, session_id()} | {:error, term()}
  def start_session(config, server \\ __MODULE__) do
    GenServer.call(server, {:start_session, config})
  end

  @doc """
  Stop tracking a session.
  """
  @spec stop_session(session_id(), GenServer.server()) :: :ok
  def stop_session(session_id, server \\ __MODULE__) when is_binary(session_id) do
    GenServer.cast(server, {:stop_session, session_id})
  end

  @impl true
  def init(opts) do
    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 10_000)
    session_api = Keyword.get(opts, :session_api, Tinkex.API.Session)
    schedule_heartbeat(heartbeat_interval_ms)

    {:ok,
     %{sessions: %{}, heartbeat_interval_ms: heartbeat_interval_ms, session_api: session_api}}
  end

  @impl true
  def handle_call({:start_session, %Config{} = config}, _from, state) do
    case create_session(config, state.session_api) do
      {:ok, session_id} ->
        sessions = Map.put(state.sessions, session_id, %{config: config})
        {:reply, {:ok, session_id}, %{state | sessions: sessions}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:stop_session, session_id}, state) do
    {:noreply, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  @impl true
  def handle_info(:heartbeat, %{sessions: sessions} = state) do
    updated_sessions =
      Enum.reduce(sessions, sessions, fn {session_id, entry}, acc ->
        case send_heartbeat(session_id, entry.config, state.session_api) do
          :ok ->
            acc

          :drop ->
            Map.delete(acc, session_id)
        end
      end)

    schedule_heartbeat(state.heartbeat_interval_ms)
    {:noreply, %{state | sessions: updated_sessions}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp create_session(%Config{} = config, session_api) do
    request = %{
      tags: ["tinkex-elixir"],
      user_metadata: config.user_metadata,
      sdk_version: sdk_version(),
      type: "create_session"
    }

    case session_api.create(request, config: config) do
      {:ok, %{"session_id" => session_id}} ->
        {:ok, session_id}

      {:ok, %CreateSessionResponse{session_id: session_id}} ->
        {:ok, session_id}

      {:ok, %{"session_id" => session_id}} when is_binary(session_id) ->
        {:ok, session_id}

      {:ok, %{} = resp} ->
        case resp["session_id"] do
          session_id when is_binary(session_id) -> {:ok, session_id}
          _ -> {:error, :invalid_response}
        end

      {:error, _} = error ->
        error
    end
  end

  defp send_heartbeat(session_id, %Config{} = config, session_api) do
    case session_api.heartbeat(%{session_id: session_id}, config: config) do
      {:ok, _} ->
        :ok

      {:error, %Error{} = error} ->
        if Error.user_error?(error) do
          Logger.warning("Session #{session_id} expired: #{Error.format(error)}")
          :drop
        else
          Logger.debug("Heartbeat failed for #{session_id}: #{Error.format(error)}")
          :ok
        end
    end
  end

  defp schedule_heartbeat(interval_ms) do
    Process.send_after(self(), :heartbeat, interval_ms)
  end

  defp sdk_version do
    Tinkex.Version.current()
  end
end
