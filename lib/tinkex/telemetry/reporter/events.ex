defmodule Tinkex.Telemetry.Reporter.Events do
  @moduledoc """
  Event building for different telemetry event types.

  Responsible for constructing typed event structs (GenericEvent, SessionStartEvent,
  SessionEndEvent, UnhandledExceptionEvent) with proper indexing and timestamps.
  """

  alias Tinkex.Telemetry.Reporter.{ExceptionHandler, Queue, Serializer}

  alias Tinkex.Types.Telemetry.{
    GenericEvent,
    SessionEndEvent,
    SessionStartEvent,
    UnhandledExceptionEvent
  }

  @doc """
  Build a generic telemetry event.

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_generic_event(map(), String.t(), map(), atom()) :: {GenericEvent.t(), map()}
  def build_generic_event(state, name, data, severity) do
    {index, state} = next_session_index(state)

    event =
      GenericEvent.new(
        event_id: uuid(),
        event_session_index: index,
        severity: parse_severity(severity),
        timestamp: iso_timestamp(),
        event_name: name,
        event_data: Serializer.sanitize(data)
      )

    {event, state}
  end

  @doc """
  Build a session start event.

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_session_start_event(map()) :: {SessionStartEvent.t(), map()}
  def build_session_start_event(state) do
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

  @doc """
  Build a session end event with duration.

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_session_end_event(map()) :: {SessionEndEvent.t(), map()}
  def build_session_end_event(state) do
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

  @doc """
  Build an exception event (either user error or unhandled exception).

  Delegates to ExceptionHandler to determine the exception type and builds
  the appropriate event.

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_exception_event(map(), Exception.t(), atom()) :: {term(), map()}
  def build_exception_event(state, exception, severity) do
    case ExceptionHandler.classify_exception(exception) do
      {:user_error, user_error} ->
        build_user_error_event(state, user_error)

      :unhandled ->
        build_unhandled_exception(state, exception, severity)
    end
  end

  @doc """
  Build an unhandled exception event.

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_unhandled_exception(map(), Exception.t(), atom()) ::
          {UnhandledExceptionEvent.t(), map()}
  def build_unhandled_exception(state, exception, severity) do
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

  @doc """
  Build a user error event (as a generic event with warning severity).

  Returns `{event, updated_state}` where session_index has been incremented.
  """
  @spec build_user_error_event(map(), Exception.t()) :: {GenericEvent.t(), map()}
  def build_user_error_event(state, exception) do
    data =
      %{
        error_type: exception |> Map.get(:__struct__, exception) |> to_string(),
        message: exception_message(exception)
      }
      |> maybe_put_status(exception)
      |> maybe_put_body(exception)

    build_generic_event(state, "user_error", data, :warning)
  end

  @doc """
  Enqueue a session start event.

  Returns `{updated_state, accepted?}`.
  """
  @spec enqueue_session_start(map()) :: {map(), boolean()}
  def enqueue_session_start(state) do
    {event, state} = build_session_start_event(state)
    Queue.enqueue_event(state, event)
  end

  @doc """
  Maybe enqueue a session end event if not already enqueued.

  Returns updated_state.
  """
  @spec maybe_enqueue_session_end(map()) :: map()
  def maybe_enqueue_session_end(%{session_ended?: true} = state), do: state

  def maybe_enqueue_session_end(state) do
    {event, state} = build_session_end_event(state)
    {state, _accepted?} = Queue.enqueue_event(state, event)
    %{state | session_ended?: true}
  end

  @doc """
  Determine severity for a telemetry event based on event name.
  """
  @spec severity_for_event(list()) :: atom()
  def severity_for_event([:tinkex, :http, :request, :exception]), do: :error
  def severity_for_event(_), do: :info

  # Private helpers

  defp next_session_index(%{session_index: idx} = state) do
    {idx, %{state | session_index: idx + 1}}
  end

  defp maybe_put_status(data, %{status: status}) when is_integer(status),
    do: Map.put(data, :status_code, status)

  defp maybe_put_status(data, %{status_code: status}) when is_integer(status),
    do: Map.put(data, :status_code, status)

  defp maybe_put_status(data, _), do: data

  defp maybe_put_body(data, %{body: body}) when is_map(body), do: Map.put(data, :body, body)
  defp maybe_put_body(data, %{data: body}) when is_map(body), do: Map.put(data, :body, body)
  defp maybe_put_body(data, _), do: data

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
    # Try to get the stacktrace from the exception if it has one
    stacktrace = get_exception_stacktrace(exception)
    Exception.format(:error, exception, stacktrace)
  rescue
    _ -> format_stacktrace_fallback(exception)
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
    Exception.format(:error, exception, [])
  rescue
    _ -> nil
  end

  defp uuid do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
