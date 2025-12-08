defmodule Tinkex.Telemetry.Reporter.Queue do
  @moduledoc """
  Queue operations for telemetry events.

  Manages enqueueing, dequeueing, and size tracking of telemetry events
  with overflow protection.
  """

  require Logger

  @doc """
  Enqueue an event to the queue.

  Returns `{state, true}` if accepted, `{state, false}` if queue is full.
  Increments the push_counter when an event is enqueued.
  """
  @spec enqueue_event(map(), term()) :: {map(), boolean()}
  def enqueue_event(%{queue_size: size, max_queue_size: max} = state, _event)
      when size >= max do
    Logger.warning("Telemetry queue full (#{max}), dropping event")
    {state, false}
  end

  def enqueue_event(state, event) do
    queue = :queue.in(event, state.queue)
    push_counter = state.push_counter + 1
    {%{state | queue: queue, queue_size: state.queue_size + 1, push_counter: push_counter}, true}
  end

  @doc """
  Check if flush should be requested based on queue size vs threshold.
  """
  @spec maybe_request_flush(map()) :: map()
  def maybe_request_flush(%{queue_size: size, flush_threshold: threshold} = state)
      when size >= threshold do
    send(self(), :flush)
    state
  end

  def maybe_request_flush(state), do: state

  @doc """
  Schedule the next flush timer.
  """
  @spec maybe_schedule_flush(map()) :: map()
  def maybe_schedule_flush(%{flush_interval_ms: interval} = state)
      when is_integer(interval) and interval > 0 do
    ref = Process.send_after(self(), :flush, interval)
    %{state | flush_timer: ref}
  end

  def maybe_schedule_flush(state), do: state

  @doc """
  Drain the queue and return all events as a list.

  Returns `{events, updated_state}` where the queue is now empty
  and flush_counter is incremented by the number of events.
  """
  @spec drain_queue(map()) :: {list(), map()}
  def drain_queue(%{queue_size: 0} = state), do: {[], state}

  def drain_queue(state) do
    events = :queue.to_list(state.queue)
    events_count = length(events)
    flush_counter = state.flush_counter + events_count
    empty_state = %{state | queue: :queue.new(), queue_size: 0, flush_counter: flush_counter}
    {events, empty_state}
  end

  @doc """
  Wait until push_counter == flush_counter or timeout.

  Returns `true` if drained within timeout, `false` otherwise.
  """
  @spec wait_until_drained(map(), timeout()) :: boolean()
  def wait_until_drained(state, timeout_ms) do
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
end
