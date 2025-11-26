defmodule Tinkex.Regularizer.Telemetry do
  @moduledoc """
  Telemetry helpers for regularizer events.

  This module provides convenience functions for attaching telemetry handlers
  to regularizer-specific events.

  ## Events

  The following events are emitted by the regularizer pipeline:

  ### Custom Loss Events

  - `[:tinkex, :custom_loss, :start]` - Emitted when custom loss computation begins
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{regularizer_count: integer, track_grad_norms: boolean}`

  - `[:tinkex, :custom_loss, :stop]` - Emitted when custom loss computation completes
    - Measurements: `%{duration: integer, loss_total: float, regularizer_total: float}`
    - Metadata: `%{regularizer_count: integer}`

  - `[:tinkex, :custom_loss, :exception]` - Emitted on failure
    - Measurements: `%{duration: integer}`
    - Metadata: `%{reason: term}`

  ### Per-Regularizer Events

  - `[:tinkex, :regularizer, :compute, :start]` - Before each regularizer
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{regularizer_name: String.t(), weight: float, async: boolean}`

  - `[:tinkex, :regularizer, :compute, :stop]` - After each regularizer
    - Measurements: `%{duration: integer, value: float, contribution: float, grad_norm: float | nil}`
    - Metadata: `%{regularizer_name: String.t(), weight: float, async: boolean}`

  - `[:tinkex, :regularizer, :compute, :exception]` - On regularizer failure
    - Measurements: `%{duration: integer}`
    - Metadata: `%{regularizer_name: String.t(), weight: float, reason: term}`

  ## Example Usage

      # Attach a logger to all regularizer events
      handler_id = Tinkex.Regularizer.Telemetry.attach_logger()

      # Attach with options
      handler_id = Tinkex.Regularizer.Telemetry.attach_logger(
        handler_id: "my-app-regularizer-logger",
        level: :debug
      )

      # Detach when done
      Tinkex.Regularizer.Telemetry.detach(handler_id)

  ## Custom Handlers

      :telemetry.attach(
        "my-handler",
        [:tinkex, :regularizer, :compute, :stop],
        fn event, measurements, metadata, config ->
          # Custom handling
          IO.inspect({event, measurements, metadata})
        end,
        %{}
      )
  """

  require Logger

  @events [
    [:tinkex, :custom_loss, :start],
    [:tinkex, :custom_loss, :stop],
    [:tinkex, :custom_loss, :exception],
    [:tinkex, :regularizer, :compute, :start],
    [:tinkex, :regularizer, :compute, :stop],
    [:tinkex, :regularizer, :compute, :exception]
  ]

  @doc """
  Returns the list of regularizer telemetry events.

  Useful for programmatic attachment of handlers.
  """
  @spec events() :: list(list(atom()))
  def events, do: @events

  @doc """
  Attach a logger that prints regularizer telemetry events to the console.

  ## Options

  - `:handler_id` - Custom handler ID (default: auto-generated)
  - `:level` - Log level (default: `:info`)

  ## Returns

  The handler ID for later detachment.

  ## Examples

      handler_id = Tinkex.Regularizer.Telemetry.attach_logger()

      handler_id = Tinkex.Regularizer.Telemetry.attach_logger(
        handler_id: "my-regularizer-logger",
        level: :debug
      )
  """
  @spec attach_logger(keyword()) :: term()
  def attach_logger(opts \\ []) do
    handler_id =
      opts[:handler_id] ||
        "tinkex-regularizer-#{:erlang.unique_integer([:positive])}"

    level = opts[:level] || :info

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        &handle_event/4,
        %{level: level}
      )

    handler_id
  end

  @doc """
  Detach a previously attached handler.
  """
  @spec detach(term()) :: :ok | {:error, :not_found}
  def detach(handler_id), do: :telemetry.detach(handler_id)

  @doc false
  def handle_event([:tinkex, :custom_loss, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Custom loss starting: " <>
        "regularizers=#{metadata.regularizer_count} " <>
        "track_grad_norms=#{metadata.track_grad_norms}"
    end)
  end

  def handle_event([:tinkex, :custom_loss, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.log(config.level, fn ->
      "Custom loss computed in #{duration_ms}ms " <>
        "total=#{Float.round(measurements.loss_total, 4)} " <>
        "regularizer_total=#{Float.round(measurements.regularizer_total, 4)} " <>
        "regularizers=#{metadata.regularizer_count}"
    end)
  end

  def handle_event([:tinkex, :custom_loss, :exception], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.log(config.level, fn ->
      "Custom loss failed after #{duration_ms}ms: #{inspect(metadata.reason)}"
    end)
  end

  def handle_event([:tinkex, :regularizer, :compute, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      async_str = if metadata.async, do: " (async)", else: ""
      "Regularizer #{metadata.regularizer_name} starting#{async_str}"
    end)
  end

  def handle_event([:tinkex, :regularizer, :compute, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    grad_str =
      if measurements.grad_norm do
        " grad_norm=#{Float.round(measurements.grad_norm, 4)}"
      else
        ""
      end

    Logger.log(config.level, fn ->
      "Regularizer #{metadata.regularizer_name} " <>
        "value=#{Float.round(measurements.value, 4)} " <>
        "contribution=#{Float.round(measurements.contribution, 4)} " <>
        "in #{duration_ms}ms#{grad_str}"
    end)
  end

  def handle_event([:tinkex, :regularizer, :compute, :exception], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.log(config.level, fn ->
      "Regularizer #{metadata.regularizer_name} failed after #{duration_ms}ms: " <>
        "#{inspect(metadata.reason)}"
    end)
  end

  # Fallback for any unhandled events
  def handle_event(event, measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "Unhandled regularizer telemetry #{inspect(event)}: " <>
        "measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    end)
  end
end
