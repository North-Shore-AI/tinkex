defmodule Tinkex.Telemetry do
  @moduledoc """
  Convenience helpers for wiring Tinkex telemetry into simple console logging or
  lightweight dashboards.
  """

  require Logger

  @default_events [
    [:tinkex, :http, :request, :start],
    [:tinkex, :http, :request, :stop],
    [:tinkex, :http, :request, :exception],
    [:tinkex, :queue, :state_change]
  ]

  @doc """
  Attach a logger that prints HTTP and queue-state telemetry events to the console.

  Returns the handler id so callers can detach it manually.
  """
  @spec attach_logger(keyword()) :: term()
  def attach_logger(opts \\ []) do
    handler_id = opts[:handler_id] || "tinkex-telemetry-#{:erlang.unique_integer([:positive])}"
    events = opts[:events] || @default_events
    level = opts[:level] || :info

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, %{level: level})
    handler_id
  end

  @doc """
  Detach a previously attached handler.
  """
  @spec detach(term()) :: :ok | {:error, :not_found}
  def detach(handler_id), do: :telemetry.detach(handler_id)

  @doc false
  def handle_event([:tinkex, :http, :request, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "HTTP #{metadata.method} #{metadata.path} start (pool=#{metadata.pool_type} base=#{metadata.base_url})"
    end)
  end

  def handle_event([:tinkex, :http, :request, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.log(config.level, fn ->
      "HTTP #{metadata.method} #{metadata.path} #{metadata.result} in #{duration_ms}ms " <>
        "retries=#{metadata[:retry_count] || 0} base=#{metadata.base_url}"
    end)
  end

  def handle_event([:tinkex, :http, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "HTTP #{metadata.method} #{metadata.path} exception after #{duration_ms}ms reason=#{inspect(metadata.reason)}"
    )
  end

  def handle_event([:tinkex, :queue, :state_change], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Queue state changed to #{metadata.queue_state} (request_id=#{metadata.request_id})"
    end)
  end

  def handle_event(event, _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Unhandled telemetry #{inspect(event)} #{inspect(metadata)}"
    end)
  end
end
