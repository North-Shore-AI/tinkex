defmodule Tinkex.Telemetry.Reporter do
  @moduledoc """
  Client-side telemetry reporter that batches events and ships them to the Tinker
  backend via `/api/v1/telemetry`.

  A reporter is scoped to a single Tinker session. It:

    * Emits session start/end events.
    * Accepts generic events and exceptions via `log/4`, `log_exception/3`, and
      `log_fatal_exception/3`.
    * Optionally listens to `:telemetry` events and forwards ones that include
      matching `:session_id` metadata.
    * Batches up to 100 events per request, flushing periodically and whenever
      the queue crosses the configured threshold.
    * Retries failed sends with exponential backoff (up to 3 retries).
    * Supports wait-until-drained semantics for graceful shutdown.

  Telemetry can be disabled by setting `TINKER_TELEMETRY=0|false|no`.

  ## Typed Events

  The reporter now uses typed structs for all telemetry events. See
  `Tinkex.Types.Telemetry` for available types:

    * `Tinkex.Types.Telemetry.GenericEvent` - custom application events
    * `Tinkex.Types.Telemetry.SessionStartEvent` - session start marker
    * `Tinkex.Types.Telemetry.SessionEndEvent` - session end marker
    * `Tinkex.Types.Telemetry.UnhandledExceptionEvent` - exception reports
  """

  use GenServer
  require Logger

  alias Tinkex.API.Telemetry, as: TelemetryAPI

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent
  }

  @max_queue_size 10_000
  @max_batch_size 100
  @default_flush_interval_ms 10_000
  @default_flush_threshold 100
  @default_flush_timeout_ms 30_000
  @default_http_timeout_ms 5_000
  @default_max_retries 3
  @default_retry_base_delay_ms 1_000

  @default_events [
    [:tinkex, :http, :request, :start],
    [:tinkex, :http, :request, :stop],
    [:tinkex, :http, :request, :exception],
    [:tinkex, :queue, :state_change]
  ]

  @type severity :: :debug | :info | :warning | :error | :critical | String.t()

  @doc """
  Start a reporter for the provided session/config.

  Options:
    * `:config` (**required**) - `Tinkex.Config.t()`
    * `:session_id` (**required**) - Tinker session id
    * `:handler_id` - telemetry handler id (auto-generated)
    * `:events` - telemetry events to capture (default: HTTP + queue state)
    * `:attach_events?` - whether to attach telemetry handlers (default: true)
    * `:flush_interval_ms` - periodic flush interval (default: 10s)
    * `:flush_threshold` - flush when queue reaches this size (default: 100)
    * `:flush_timeout_ms` - max wait time for drain operations (default: 30s)
    * `:http_timeout_ms` - HTTP request timeout (default: 5s)
    * `:max_retries` - max retries per batch (default: 3)
    * `:retry_base_delay_ms` - base delay for exponential backoff (default: 1s)
    * `:max_queue_size` - drop events beyond this size (default: 10_000)
    * `:max_batch_size` - events per POST (default: 100)
    * `:enabled` - override env flag; when false returns `:ignore`
  """
  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Log a generic telemetry event.
  """
  @spec log(pid() | nil, String.t(), map(), severity()) :: boolean()
  def log(pid, name, data \\ %{}, severity \\ :info)
  def log(nil, _name, _data, _severity), do: false
  def log(pid, name, data, severity), do: safe_call(pid, {:log, name, data, severity})

  @doc """
  Log an exception (non-fatal) and trigger an async flush.
  """
  @spec log_exception(pid() | nil, Exception.t(), severity()) :: boolean()
  def log_exception(pid, exception, severity \\ :error)
  def log_exception(nil, _exception, _severity), do: false

  def log_exception(pid, exception, severity),
    do: safe_call(pid, {:log_exception, exception, severity, :nonfatal})

  @doc """
  Log a fatal exception, emit a session end event, and flush synchronously.

  Waits until all queued events are flushed (up to flush_timeout_ms) and logs
  a notification with the session ID for debugging purposes.
  """
  @spec log_fatal_exception(pid() | nil, Exception.t(), severity()) :: boolean()
  def log_fatal_exception(pid, exception, severity \\ :error)
  def log_fatal_exception(nil, _exception, _severity), do: false

  def log_fatal_exception(pid, exception, severity),
    do: safe_call(pid, {:log_exception, exception, severity, :fatal})

  @doc """
  Flush pending events.

  Options:
    * `:sync?` - when true, blocks until all batches are sent (default: false)
    * `:wait_drained?` - when true with sync?, waits until push_counter == flush_counter
  """
  @spec flush(pid() | nil, keyword()) :: :ok | boolean()
  def flush(pid, opts \\ [])
  def flush(nil, _opts), do: false

  def flush(pid, opts) do
    sync? = Keyword.get(opts, :sync?, false)
    wait_drained? = Keyword.get(opts, :wait_drained?, false)
    safe_call(pid, {:flush, sync?, wait_drained?})
  end

  @doc """
  Stop the reporter gracefully.

  Emits a session end event (if not already emitted) and flushes all pending
  events synchronously before stopping the GenServer.
  """
  @spec stop(pid() | nil, timeout()) :: :ok | boolean()
  def stop(pid, timeout \\ 5_000)
  def stop(nil, _timeout), do: false

  def stop(pid, timeout) do
    GenServer.stop(pid, :normal, timeout)
  catch
    :exit, _ -> false
  end

  @doc """
  Wait until all queued events have been flushed.

  Returns `true` if drained within timeout, `false` otherwise.
  """
  @spec wait_until_drained(pid() | nil, timeout()) :: boolean()
  def wait_until_drained(pid, timeout \\ 30_000)
  def wait_until_drained(nil, _timeout), do: false

  def wait_until_drained(pid, timeout) do
    safe_call(pid, {:wait_until_drained, timeout}, timeout + 1_000)
  end

  @impl true
  def init(opts) do
    enabled? =
      Keyword.get(
        opts,
        :enabled,
        case opts[:config] do
          %Tinkex.Config{telemetry_enabled?: value} when is_boolean(value) -> value
          _ -> telemetry_enabled?()
        end
      )

    case enabled? do
      true ->
        config = Keyword.fetch!(opts, :config)
        session_id = Keyword.fetch!(opts, :session_id)

        flush_interval_ms = Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms)
        flush_threshold = Keyword.get(opts, :flush_threshold, @default_flush_threshold)
        flush_timeout_ms = Keyword.get(opts, :flush_timeout_ms, @default_flush_timeout_ms)
        http_timeout_ms = Keyword.get(opts, :http_timeout_ms, @default_http_timeout_ms)
        max_retries = Keyword.get(opts, :max_retries, @default_max_retries)

        retry_base_delay_ms =
          Keyword.get(opts, :retry_base_delay_ms, @default_retry_base_delay_ms)

        max_queue_size = Keyword.get(opts, :max_queue_size, @max_queue_size)
        max_batch_size = Keyword.get(opts, :max_batch_size, @max_batch_size)

        handler_id =
          opts[:handler_id] || "tinkex-telemetry-reporter-#{:erlang.unique_integer([:positive])}"

        events = Keyword.get(opts, :events, @default_events)
        attach_events? = Keyword.get(opts, :attach_events?, true)

        state = %{
          config: config,
          session_id: session_id,
          handler_id: handler_id,
          attach_events?: attach_events?,
          events: events,
          flush_interval_ms: flush_interval_ms,
          flush_threshold: flush_threshold,
          flush_timeout_ms: flush_timeout_ms,
          http_timeout_ms: http_timeout_ms,
          max_retries: max_retries,
          retry_base_delay_ms: retry_base_delay_ms,
          max_queue_size: max_queue_size,
          max_batch_size: max_batch_size,
          session_index: 0,
          queue: :queue.new(),
          queue_size: 0,
          # Counters for wait-until-drained
          push_counter: 0,
          flush_counter: 0,
          session_start_native: System.monotonic_time(:microsecond),
          session_start_iso: iso_timestamp(),
          session_ended?: false,
          flush_timer: nil
        }

        {state, _accepted?} = enqueue_session_start(state)

        state =
          state
          |> maybe_schedule_flush()
          |> maybe_attach_handlers()

        {:ok, state}

      _ ->
        :ignore
    end
  end

  @impl true
  def handle_call({:log, name, data, severity}, _from, state) do
    {event, state} = build_generic_event(state, name, data, severity)
    {state, accepted?} = enqueue_event(state, event)
    {:reply, accepted?, maybe_request_flush(state)}
  end

  def handle_call({:log_exception, exception, severity, kind}, _from, state) do
    {event, state} = build_exception_event(state, exception, severity)
    {state, accepted?} = enqueue_event(state, event)

    state =
      case kind do
        :fatal ->
          state = maybe_enqueue_session_end(state)
          {state, _} = flush_now(state, :sync)
          wait_until_drained_internal(state, state.flush_timeout_ms)
          notify_exception_logged(state.session_id)
          state

        :nonfatal ->
          maybe_request_flush(state)
      end

    {:reply, accepted?, state}
  end

  def handle_call({:flush, sync?, wait_drained?}, _from, state) do
    {state, _} = flush_now(state, if(sync?, do: :sync, else: :async))

    case {sync?, wait_drained?} do
      {true, true} -> wait_until_drained_internal(state, state.flush_timeout_ms)
      _ -> :ok
    end

    {:reply, :ok, state}
  end

  def handle_call({:wait_until_drained, timeout}, _from, state) do
    result = wait_until_drained_internal(state, timeout)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:telemetry_event, event, measurements, metadata}, state) do
    state =
      case metadata[:session_id] do
        nil ->
          state

        id when id != state.session_id ->
          state

        _ ->
          {generic, state} =
            build_generic_event(
              state,
              Enum.join(event, "."),
              %{
                measurements: sanitize(measurements),
                metadata: sanitize(Map.delete(metadata, :session_id))
              },
              severity_for_event(event)
            )

          {state, _accepted?} = enqueue_event(state, generic)
          maybe_request_flush(state)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    {state, _} = flush_now(state, :async)
    {:noreply, maybe_schedule_flush(state)}
  end

  @impl true
  def terminate(_reason, state) do
    maybe_detach_handler(state)

    state = maybe_enqueue_session_end(state)
    {state, _} = flush_now(state, :sync)
    wait_until_drained_internal(state, state.flush_timeout_ms)

    :ok
  end

  # Wait until push_counter == flush_counter or timeout
  defp wait_until_drained_internal(state, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until_drained(state, deadline, System.monotonic_time(:millisecond))
  end

  defp do_wait_until_drained(%{push_counter: push, flush_counter: flush}, _deadline, _now)
       when flush >= push do
    true
  end

  defp do_wait_until_drained(_state, deadline, now) when now >= deadline, do: false

  defp do_wait_until_drained(state, deadline, _now) do
    Process.sleep(100)
    do_wait_until_drained(state, deadline, System.monotonic_time(:millisecond))
  end

  defp notify_exception_logged(session_id) do
    Logger.info("Exception logged for session ID: #{session_id}")
  end

  defp maybe_attach_handlers(%{attach_events?: false} = state), do: state

  defp maybe_attach_handlers(%{handler_id: handler_id, events: events} = state) do
    :telemetry.attach_many(handler_id, events, &__MODULE__.handle_telemetry_event/4, self())
    state
  end

  defp maybe_detach_handler(%{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  rescue
    _ -> :ok
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, reporter_pid) do
    GenServer.cast(reporter_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp enqueue_event(%{queue_size: size, max_queue_size: max} = state, _event)
       when size >= max do
    Logger.warning("Telemetry queue full (#{max}), dropping event")
    {state, false}
  end

  defp enqueue_event(state, event) do
    queue = :queue.in(event, state.queue)
    push_counter = state.push_counter + 1
    {%{state | queue: queue, queue_size: state.queue_size + 1, push_counter: push_counter}, true}
  end

  defp maybe_request_flush(%{queue_size: size, flush_threshold: threshold} = state)
       when size >= threshold do
    send(self(), :flush)
    state
  end

  defp maybe_request_flush(state), do: state

  defp maybe_schedule_flush(%{flush_interval_ms: interval} = state)
       when is_integer(interval) and interval > 0 do
    ref = Process.send_after(self(), :flush, interval)
    %{state | flush_timer: ref}
  end

  defp maybe_schedule_flush(state), do: state

  defp flush_now(%{queue_size: 0} = state, _mode), do: {state, :ok}

  defp flush_now(state, mode) do
    events = :queue.to_list(state.queue)
    batches = Enum.chunk_every(events, state.max_batch_size)
    events_count = length(events)

    Enum.each(batches, fn batch ->
      request = build_request(batch, state)
      send_batch_with_retry(request, state, mode)
    end)

    # Update flush_counter after all batches are sent
    flush_counter = state.flush_counter + events_count
    empty = %{state | queue: :queue.new(), queue_size: 0, flush_counter: flush_counter}
    {empty, :ok}
  end

  defp send_batch_with_retry(request, state, mode, attempt \\ 0) do
    result =
      try do
        opts = [config: state.config, timeout: state.http_timeout_ms]

        case mode do
          :sync -> TelemetryAPI.send_sync(request, opts)
          :async -> TelemetryAPI.send(request, opts)
        end
      rescue
        exception ->
          {:error, exception}
      end

    case result do
      {:ok, _} ->
        :ok

      :ok ->
        :ok

      {:error, reason} when attempt < state.max_retries ->
        delay = calculate_backoff_delay(attempt, state.retry_base_delay_ms)

        Logger.warning(
          "Telemetry send failed (attempt #{attempt + 1}), retrying in #{delay}ms: #{inspect(reason)}"
        )

        Process.sleep(delay)
        send_batch_with_retry(request, state, mode, attempt + 1)

      {:error, reason} ->
        Logger.warning(
          "Telemetry send failed after #{state.max_retries} retries: #{inspect(reason)}"
        )

        :error
    end
  end

  defp calculate_backoff_delay(attempt, base_delay_ms) do
    # Exponential backoff: base * 2^attempt with some jitter
    base = base_delay_ms * :math.pow(2, attempt)
    jitter = :rand.uniform(round(base * 0.1))
    round(base + jitter)
  end

  defp build_request(events, state) do
    # Convert typed structs to wire format maps
    event_maps = Enum.map(events, &event_to_map/1)

    %{
      session_id: state.session_id,
      platform: platform(),
      sdk_version: Tinkex.Version.tinker_sdk(),
      events: event_maps
    }
  end

  defp event_to_map(%GenericEvent{} = event), do: GenericEvent.to_map(event)
  defp event_to_map(%SessionStartEvent{} = event), do: SessionStartEvent.to_map(event)
  defp event_to_map(%SessionEndEvent{} = event), do: SessionEndEvent.to_map(event)
  defp event_to_map(%UnhandledExceptionEvent{} = event), do: UnhandledExceptionEvent.to_map(event)
  defp event_to_map(map) when is_map(map), do: map

  defp build_generic_event(state, name, data, severity) do
    {index, state} = next_session_index(state)

    event =
      GenericEvent.new(
        event_id: uuid(),
        event_session_index: index,
        severity: parse_severity(severity),
        timestamp: iso_timestamp(),
        event_name: name,
        event_data: sanitize(data)
      )

    {event, state}
  end

  defp enqueue_session_start(state) do
    {event, state} = build_session_start_event(state)
    enqueue_event(state, event)
  end

  defp build_session_start_event(state) do
    {index, state} = next_session_index(state)

    event =
      SessionStartEvent.new(
        event_id: uuid(),
        event_session_index: index,
        severity: :info,
        timestamp: state.session_start_iso
      )

    {event, state}
  end

  defp build_session_end_event(state) do
    {index, state} = next_session_index(state)
    duration = duration_string(state.session_start_native, System.monotonic_time(:microsecond))

    event =
      SessionEndEvent.new(
        event_id: uuid(),
        event_session_index: index,
        severity: :info,
        timestamp: iso_timestamp(),
        duration: duration
      )

    {event, state}
  end

  defp build_exception_event(state, %Tinkex.Error{} = error, severity) do
    if Tinkex.Error.user_error?(error) do
      build_user_error_event(state, error)
    else
      build_unhandled_exception(state, error, severity)
    end
  end

  defp build_exception_event(state, exception, severity) do
    # Check the exception and its cause chain for user errors
    case find_user_error_in_chain(exception) do
      {:ok, user_error} ->
        build_user_error_event(state, user_error)

      :not_found ->
        build_unhandled_exception(state, exception, severity)
    end
  end

  @doc """
  Traverse the exception cause chain to find a user error.

  Checks exception fields in order: :cause, :reason, :plug_status (4xx except 408/429),
  :__cause__, :__context__. Depth-first, first match wins.
  """
  @spec find_user_error_in_chain(term(), map()) :: {:ok, term()} | :not_found
  def find_user_error_in_chain(exception, visited \\ %{}) do
    exception_id = :erlang.phash2(exception)

    if Map.has_key?(visited, exception_id) do
      :not_found
    else
      visited = Map.put(visited, exception_id, true)

      if user_error_exception?(exception) do
        {:ok, exception}
      else
        find_in_candidates(exception, visited)
      end
    end
  end

  defp find_in_candidates(exception, visited) do
    candidates = extract_candidates(exception)

    Enum.reduce_while(candidates, :not_found, fn candidate, _acc ->
      case find_user_error_in_chain(candidate, visited) do
        {:ok, _} = found -> {:halt, found}
        :not_found -> {:cont, :not_found}
      end
    end)
  end

  defp extract_candidates(exception) do
    []
    |> maybe_add_candidate(Map.get(exception, :cause))
    |> maybe_add_candidate(Map.get(exception, :reason))
    |> maybe_add_candidate(Map.get(exception, :__cause__))
    |> maybe_add_candidate(Map.get(exception, :__context__))
  end

  defp maybe_add_candidate(list, nil), do: list
  defp maybe_add_candidate(list, candidate) when is_map(candidate), do: list ++ [candidate]
  defp maybe_add_candidate(list, _), do: list

  defp build_unhandled_exception(state, exception, severity) do
    {index, state} = next_session_index(state)
    message = exception_message(exception)

    event =
      UnhandledExceptionEvent.new(
        event_id: uuid(),
        event_session_index: index,
        severity: parse_severity(severity),
        timestamp: iso_timestamp(),
        error_type: exception |> Map.get(:__struct__, exception) |> to_string(),
        error_message: message,
        traceback: exception_traceback(exception)
      )

    {event, state}
  end

  defp build_user_error_event(state, exception) do
    data =
      %{
        error_type: exception |> Map.get(:__struct__, exception) |> to_string(),
        message: exception_message(exception)
      }
      |> maybe_put_status(exception)
      |> maybe_put_body(exception)

    build_generic_event(state, "user_error", data, :warning)
  end

  defp maybe_put_status(data, %{status: status}) when is_integer(status),
    do: Map.put(data, :status_code, status)

  defp maybe_put_status(data, %{status_code: status}) when is_integer(status),
    do: Map.put(data, :status_code, status)

  defp maybe_put_status(data, _), do: data

  defp maybe_put_body(data, %{body: body}) when is_map(body), do: Map.put(data, :body, body)
  defp maybe_put_body(data, %{data: body}) when is_map(body), do: Map.put(data, :body, body)
  defp maybe_put_body(data, _), do: data

  defp next_session_index(%{session_index: idx} = state) do
    {idx, %{state | session_index: idx + 1}}
  end

  defp maybe_enqueue_session_end(%{session_ended?: true} = state), do: state

  defp maybe_enqueue_session_end(state) do
    {event, state} = build_session_end_event(state)
    {state, _accepted?} = enqueue_event(state, event)
    %{state | session_ended?: true}
  end

  # Parse severity to atom format for typed structs
  defp parse_severity(severity) when is_atom(severity), do: severity
  defp parse_severity("DEBUG"), do: :debug
  defp parse_severity("INFO"), do: :info
  defp parse_severity("WARNING"), do: :warning
  defp parse_severity("ERROR"), do: :error
  defp parse_severity("CRITICAL"), do: :critical

  defp parse_severity(str) when is_binary(str) do
    case String.upcase(str) do
      "DEBUG" -> :debug
      "INFO" -> :info
      "WARNING" -> :warning
      "ERROR" -> :error
      "CRITICAL" -> :critical
      _ -> :info
    end
  end

  defp parse_severity(_), do: :info

  defp severity_for_event([:tinkex, :http, :request, :exception]), do: :error
  defp severity_for_event(_), do: :info

  defp sanitize(%_struct{} = struct), do: struct |> Map.from_struct() |> sanitize()

  defp sanitize(map) when is_map(map),
    do: map |> Enum.into(%{}, fn {k, v} -> {to_string(k), sanitize(v)} end)

  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  defp sanitize(value) when is_atom(value), do: Atom.to_string(value)

  defp sanitize(value)
       when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: value

  defp sanitize(value), do: inspect(value)

  defp platform do
    :os.type()
    |> Tuple.to_list()
    |> Enum.map(&to_string/1)
    |> Enum.join("/")
  end

  defp iso_timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp duration_string(start_us, end_us) do
    diff = max(end_us - start_us, 0)
    total_seconds = div(diff, 1_000_000)
    micro = rem(diff, 1_000_000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    base = "#{hours}:#{pad2(minutes)}:#{pad2(seconds)}"

    case micro do
      0 -> base
      _ -> base <> "." <> String.pad_leading(Integer.to_string(micro), 6, "0")
    end
  end

  defp pad2(int), do: int |> Integer.to_string() |> String.pad_leading(2, "0")

  defp exception_message(%Tinkex.Error{message: message}), do: message
  defp exception_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp exception_message(%{message: message}) when is_binary(message), do: message
  defp exception_message(other), do: to_string(other)

  defp exception_traceback(%{__exception__: true} = exception),
    do: format_stacktrace_with_trace(exception)

  defp exception_traceback(_), do: nil

  # Format stacktrace - try to get the current process stacktrace
  defp format_stacktrace_with_trace(exception) do
    try do
      # Try to get the stacktrace from the exception if it has one
      stacktrace = get_exception_stacktrace(exception)
      Exception.format(:error, exception, stacktrace)
    rescue
      _ -> format_stacktrace_fallback(exception)
    end
  end

  defp get_exception_stacktrace(%{stacktrace: stacktrace}) when is_list(stacktrace) do
    stacktrace
  end

  defp get_exception_stacktrace(_exception) do
    # Try to get current process stacktrace
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, trace} -> trace
      _ -> []
    end
  end

  defp format_stacktrace_fallback(exception) do
    try do
      Exception.format(:error, exception, [])
    rescue
      _ -> nil
    end
  end

  defp uuid do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @spec telemetry_enabled?() :: boolean()
  defp telemetry_enabled? do
    Tinkex.Env.telemetry_enabled?()
  end

  defp safe_call(pid, message, timeout \\ 5_000) do
    GenServer.call(pid, message, timeout)
  catch
    :exit, _ -> false
  end

  defp user_error_exception?(%{status: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{status_code: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{plug_status: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{category: :user}), do: true
  defp user_error_exception?(_), do: false
end
