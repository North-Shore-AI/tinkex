defmodule Tinkex.SessionManager do
  @moduledoc """
  Manages Tinkex sessions and heartbeats across multiple configs.
  """

  use GenServer
  require Logger

  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.PoolKey
  alias Tinkex.Types.CreateSessionResponse

  @type session_id :: String.t()
  @type session_entry :: %{
          config: Config.t(),
          last_success_ms: non_neg_integer(),
          last_error: term() | nil,
          failure_count: non_neg_integer()
        }

  @type state :: %{
          sessions: %{session_id() => session_entry()},
          sessions_table: atom(),
          heartbeat_interval_ms: non_neg_integer(),
          heartbeat_warning_after_ms: non_neg_integer(),
          max_failure_count: non_neg_integer() | :infinity,
          max_failure_duration_ms: non_neg_integer() | :infinity,
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
    table = Keyword.get(opts, :sessions_table, sessions_table())
    ensure_sessions_table(table)

    heartbeat_interval_ms = Keyword.get(opts, :heartbeat_interval_ms, 10_000)

    heartbeat_warning_after_ms =
      Keyword.get(opts, :heartbeat_warning_after_ms, 120_000)

    max_failure_count =
      opts
      |> Keyword.get(:max_failure_count)
      |> resolve_limit(Application.get_env(:tinkex, :max_failure_count, :infinity))

    max_failure_duration_ms =
      opts
      |> Keyword.get(:max_failure_duration_ms)
      |> resolve_limit(Application.get_env(:tinkex, :max_failure_duration_ms, :infinity))

    session_api = Keyword.get(opts, :session_api, Tinkex.API.Session)

    {:ok,
     %{
       sessions: load_sessions_from_ets(table),
       sessions_table: table,
       heartbeat_interval_ms: heartbeat_interval_ms,
       heartbeat_warning_after_ms: heartbeat_warning_after_ms,
       max_failure_count: max_failure_count,
       max_failure_duration_ms: max_failure_duration_ms,
       session_api: session_api,
       timer_ref: schedule_heartbeat(heartbeat_interval_ms)
     }}
  end

  @impl true
  def handle_call({:start_session, %Config{} = config}, _from, state) do
    case create_session(config, state.session_api) do
      {:ok, session_id} ->
        now_ms = now_ms()
        entry = %{config: config, last_success_ms: now_ms, last_error: nil, failure_count: 0}
        persist_session(state.sessions_table, session_id, entry)
        sessions = Map.put(state.sessions, session_id, entry)
        {:reply, {:ok, session_id}, %{state | sessions: sessions}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_session, session_id}, _from, state) do
    safe_delete(state.sessions_table, session_id)
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  @impl true
  def handle_info(:heartbeat, %{sessions: sessions} = state) do
    now_ms = now_ms()

    updated_sessions =
      Enum.reduce(sessions, %{}, fn {session_id, entry}, acc ->
        case send_heartbeat(session_id, entry.config, state.session_api) do
          :ok ->
            updated_entry = %{entry | last_success_ms: now_ms, last_error: nil, failure_count: 0}
            persist_session(state.sessions_table, session_id, updated_entry)
            Map.put(acc, session_id, updated_entry)

          {:error, last_error} ->
            maybe_warn(session_id, entry.last_success_ms, now_ms, last_error, state)
            updated_entry = %{entry | last_error: last_error}

            case maybe_remove_or_track_failure(
                   state.sessions_table,
                   session_id,
                   updated_entry,
                   now_ms,
                   state
                 ) do
              :remove ->
                acc

              tracked ->
                persist_session(state.sessions_table, session_id, tracked)
                Map.put(acc, session_id, tracked)
            end
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
      sdk_version: Tinkex.Version.tinker_sdk(),
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
    case maybe_heartbeat(session_id, config, session_api) do
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

  defp load_sessions_from_ets(table) do
    try do
      case :ets.whereis(table) do
        :undefined ->
          %{}

        _ ->
          :ets.foldl(
            fn {session_id, entry}, acc ->
              maybe_warn_about_pool(session_id, entry)
              Map.put(acc, session_id, normalize_entry(entry))
            end,
            %{},
            table
          )
      end
    rescue
      ArgumentError -> %{}
    end
  end

  defp persist_session(table, session_id, entry) do
    try do
      :ets.insert(table, {session_id, entry})
    rescue
      ArgumentError -> :ok
    end
  end

  defp maybe_cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp maybe_cancel_timer(_), do: :ok

  def sessions_table do
    Application.get_env(:tinkex, :sessions_table, :tinkex_sessions)
  end

  defp ensure_sessions_table(table) do
    try do
      :ets.new(table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])
    rescue
      ArgumentError -> table
    end
  end

  defp maybe_heartbeat(
         session_id,
         %Config{http_pool: pool, base_url: base_url} = config,
         session_api
       ) do
    resolved_pool = PoolKey.resolve_pool_name(pool, base_url, :session)

    case Process.whereis(resolved_pool) do
      nil ->
        Logger.warning(
          "Skipping heartbeat for #{session_id}: http_pool #{inspect(resolved_pool)} is not running"
        )

        {:error, :http_pool_not_alive}

      _pid ->
        safe_heartbeat(session_id, config, session_api)
    end
  end

  defp maybe_remove_or_track_failure(table, session_id, entry, now_ms, state) do
    failure_count = entry.failure_count + 1
    time_since_success = now_ms - entry.last_success_ms

    cond do
      exceeds_count?(failure_count, state.max_failure_count) ->
        Logger.warning(
          "Removing session #{session_id} after #{failure_count} consecutive heartbeat failures"
        )

        safe_delete(table, session_id)
        :remove

      exceeds_duration?(time_since_success, state.max_failure_duration_ms) ->
        Logger.warning(
          "Removing session #{session_id} after #{time_since_success}ms without a successful heartbeat"
        )

        safe_delete(table, session_id)
        :remove

      true ->
        %{entry | failure_count: failure_count}
    end
  end

  defp exceeds_count?(_count, :infinity), do: false
  defp exceeds_count?(count, max) when is_integer(max), do: count > max

  defp exceeds_duration?(_duration, :infinity), do: false
  defp exceeds_duration?(duration, max) when is_integer(max), do: duration > max

  defp normalize_entry(%{failure_count: _} = entry), do: entry
  defp normalize_entry(entry), do: Map.put(entry, :failure_count, 0)

  defp resolve_limit(nil, default), do: default
  defp resolve_limit(:infinity, _default), do: :infinity
  defp resolve_limit(value, _default), do: value

  defp maybe_warn_about_pool(session_id, %{config: %Config{http_pool: pool, base_url: base_url}}) do
    resolved_pool = PoolKey.resolve_pool_name(pool, base_url, :session)

    if Process.whereis(resolved_pool) == nil do
      Logger.warning(
        "Loaded session #{session_id} referencing missing http_pool #{inspect(resolved_pool)}; will retry when pool is available"
      )
    end
  end

  defp safe_delete(table, key) do
    try do
      :ets.delete(table, key)
    rescue
      ArgumentError -> :ok
    end
  end
end
