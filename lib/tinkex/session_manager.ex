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
  @type session_entry :: %{
          config: Config.t(),
          last_success_ms: non_neg_integer(),
          last_error: term() | nil
        }

  @type state :: %{
          sessions: %{session_id() => session_entry()},
          heartbeat_interval_ms: non_neg_integer(),
          heartbeat_warning_after_ms: non_neg_integer(),
          session_api: module(),
          timer_ref: reference() | nil
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
  def start_session(%Config{} = config, server \\ __MODULE__) do
    timeout = config.timeout + timeout_buffer(config.timeout)
    GenServer.call(server, {:start_session, config}, timeout)
  end

  @doc """
  Stop tracking a session.

  This is a synchronous call to ensure the session is removed from heartbeat
  tracking before returning. This prevents race conditions where a heartbeat
  fires after the caller has shut down but before the session was removed.
  """
  @spec stop_session(session_id(), GenServer.server()) :: :ok
  def stop_session(session_id, server \\ __MODULE__) when is_binary(session_id) do
    GenServer.call(server, {:stop_session, session_id}, 5_000)
  catch
    :exit, _ -> :ok
  end

  defp timeout_buffer(timeout_ms) when timeout_ms < 5_000, do: 5_000
  defp timeout_buffer(_timeout_ms), do: 1_000

  @impl true
  def init(opts) do
    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 10_000)
    heartbeat_warning_after_ms = Keyword.get(opts, :heartbeat_warning_after_ms, 120_000)
    session_api = Keyword.get(opts, :session_api, Tinkex.API.Session)

    {:ok,
     %{
       sessions: load_sessions_from_ets(),
       heartbeat_interval_ms: heartbeat_interval_ms,
       heartbeat_warning_after_ms: heartbeat_warning_after_ms,
       session_api: session_api,
       timer_ref: schedule_heartbeat(heartbeat_interval_ms)
     }}
  end

  @impl true
  def handle_call({:start_session, %Config{} = config}, _from, state) do
    case create_session(config, state.session_api) do
      {:ok, session_id} ->
        now_ms = now_ms()
        entry = %{config: config, last_success_ms: now_ms, last_error: nil}
        persist_session(session_id, entry)
        sessions = Map.put(state.sessions, session_id, entry)
        {:reply, {:ok, session_id}, %{state | sessions: sessions}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_session, session_id}, _from, state) do
    :ets.delete(:tinkex_sessions, session_id)
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  @impl true
  def handle_info(:heartbeat, %{sessions: sessions} = state) do
    now_ms = now_ms()

    updated_sessions =
      Enum.reduce(sessions, %{}, fn {session_id, entry}, acc ->
        case send_heartbeat(session_id, entry.config, state.session_api) do
          :ok ->
            updated_entry = %{entry | last_success_ms: now_ms, last_error: nil}
            persist_session(session_id, updated_entry)
            Map.put(acc, session_id, updated_entry)

          {:error, last_error} ->
            maybe_warn(session_id, entry.last_success_ms, now_ms, last_error, state)
            updated_entry = %{entry | last_error: last_error}
            persist_session(session_id, updated_entry)
            Map.put(acc, session_id, updated_entry)
        end
      end)

    timer_ref = schedule_heartbeat(state.heartbeat_interval_ms)
    {:noreply, %{state | sessions: updated_sessions, timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{timer_ref: ref}) do
    maybe_cancel_timer(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp create_session(%Config{} = config, session_api) do
    request = %{
      tags: config.tags || ["tinkex-elixir"],
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
    # We align to Python behavior: keep heartbeating on all failures, warn after sustained
    # failure windows instead of silently dropping sessions.
    case safe_heartbeat(session_id, config, session_api) do
      {:ok, _} ->
        :ok

      {:error, %Error{} = error} ->
        Logger.debug("Heartbeat failed for #{session_id}: #{Error.format(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.debug("Heartbeat failed for #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_heartbeat(interval_ms), do: Process.send_after(self(), :heartbeat, interval_ms)

  defp safe_heartbeat(session_id, config, session_api) do
    session_api.heartbeat(%{session_id: session_id}, config: config)
  rescue
    exception ->
      {:error,
       Error.new(:request_failed, Exception.message(exception),
         data: %{exception: exception, stacktrace: __STACKTRACE__}
       )}
  catch
    :exit, reason ->
      {:error,
       Error.new(:request_failed, "Heartbeat exited: #{inspect(reason)}",
         data: %{exit_reason: reason}
       )}
  end

  defp sdk_version do
    Tinkex.Version.current()
  end

  defp maybe_warn(session_id, last_success_ms, now_ms, last_error, state) do
    if now_ms - last_success_ms >= state.heartbeat_warning_after_ms do
      Logger.warning(
        "Heartbeat has failed for #{now_ms - last_success_ms}ms for session #{session_id}. " <>
          "Last error: #{format_error(last_error)}"
      )
    end
  end

  defp format_error(%Error{} = error), do: Error.format(error)
  defp format_error(reason), do: inspect(reason)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp load_sessions_from_ets do
    try do
      if :ets.whereis(:tinkex_sessions) == :undefined do
        %{}
      else
        :ets.foldl(
          fn {session_id, entry}, acc -> Map.put(acc, session_id, entry) end,
          %{},
          :tinkex_sessions
        )
      end
    rescue
      ArgumentError -> %{}
    end
  end

  defp persist_session(session_id, entry) do
    try do
      :ets.insert(:tinkex_sessions, {session_id, entry})
    rescue
      ArgumentError -> :ok
    end
  end

  defp maybe_cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp maybe_cancel_timer(_), do: :ok
end
