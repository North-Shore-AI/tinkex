defmodule Tinkex.Retry do
  @moduledoc false

  alias Tinkex.Error
  alias Tinkex.RetryHandler

  @telemetry_start [:tinkex, :retry, :attempt, :start]
  @telemetry_stop [:tinkex, :retry, :attempt, :stop]
  @telemetry_retry [:tinkex, :retry, :attempt, :retry]
  @telemetry_failed [:tinkex, :retry, :attempt, :failed]

  @spec with_retry((-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    handler = Keyword.get(opts, :handler, RetryHandler.new())
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    do_retry(fun, handler, metadata)
  end

  defp do_retry(fun, handler, metadata) do
    if RetryHandler.progress_timeout?(handler) do
      {:error, Error.new(:api_timeout, "Progress timeout exceeded")}
    else
      execute_attempt(fun, handler, metadata)
    end
  end

  defp execute_attempt(fun, handler, metadata) do
    attempt_metadata = Map.put(metadata, :attempt, handler.attempt)

    :telemetry.execute(
      @telemetry_start,
      %{system_time: System.system_time()},
      attempt_metadata
    )

    start_time = System.monotonic_time()

    result =
      try do
        fun.()
      rescue
        exception ->
          {:exception, exception, __STACKTRACE__}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, value} ->
        :telemetry.execute(
          @telemetry_stop,
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, value}

      {:error, error} ->
        handle_error(fun, error, handler, metadata, attempt_metadata, duration)

      {:exception, exception, _stacktrace} ->
        handle_exception(fun, exception, handler, metadata, attempt_metadata, duration)
    end
  end

  defp handle_error(fun, error, handler, metadata, attempt_metadata, duration) do
    if RetryHandler.retry?(handler, error) do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{error: error})
      )

      Process.sleep(delay)

      handler =
        handler
        |> RetryHandler.increment_attempt()
        |> RetryHandler.record_progress()

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :failed, error: error})
      )

      {:error, error}
    end
  end

  defp handle_exception(fun, exception, handler, metadata, attempt_metadata, duration) do
    if handler.attempt < handler.max_retries do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{exception: exception})
      )

      Process.sleep(delay)

      handler =
        handler
        |> RetryHandler.increment_attempt()
        |> RetryHandler.record_progress()

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :exception, exception: exception})
      )

      {:error, Error.new(:request_failed, Exception.message(exception))}
    end
  end
end
