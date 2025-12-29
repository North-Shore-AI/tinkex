defmodule Tinkex.Retry do
  @moduledoc false

  alias Foundation.Backoff
  alias Foundation.Retry, as: FoundationRetry
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

    policy = build_policy(handler)
    state = build_state(handler)

    do_retry(fun, policy, state, metadata)
  end

  defp do_retry(fun, policy, state, metadata) do
    case FoundationRetry.check_timeouts(state, policy) do
      {:error, :progress_timeout} ->
        {:error, Error.new(:api_timeout, "Progress timeout exceeded")}

      {:error, :max_elapsed} ->
        {:error, Error.new(:api_timeout, "Retry deadline exceeded")}

      :ok ->
        execute_attempt(fun, policy, state, metadata)
    end
  end

  defp execute_attempt(fun, policy, state, metadata) do
    attempt_metadata = Map.put(metadata, :attempt, state.attempt)

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

    case FoundationRetry.step(state, policy, result) do
      {:retry, delay, next_state} ->
        emit_retry_event(result, duration, delay, attempt_metadata)
        Process.sleep(delay)
        do_retry(fun, policy, next_state, metadata)

      {:halt, {:error, :progress_timeout}, _state} ->
        emit_timeout_event(duration, attempt_metadata)
        {:error, Error.new(:api_timeout, "Progress timeout exceeded")}

      {:halt, {:error, :max_elapsed}, _state} ->
        emit_timeout_event(duration, attempt_metadata)
        {:error, Error.new(:api_timeout, "Retry deadline exceeded")}

      {:halt, {:ok, value}, _state} ->
        :telemetry.execute(
          @telemetry_stop,
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, value}

      {:halt, {:error, error}, _state} ->
        :telemetry.execute(
          @telemetry_failed,
          %{duration: duration},
          Map.merge(attempt_metadata, %{result: :failed, error: error})
        )

        {:error, error}

      {:halt, {:exception, exception, _stacktrace}, _state} ->
        :telemetry.execute(
          @telemetry_failed,
          %{duration: duration},
          Map.merge(attempt_metadata, %{result: :exception, exception: exception})
        )

        {:error, Error.new(:request_failed, Exception.message(exception))}
    end
  end

  defp emit_retry_event({:error, error}, duration, delay, attempt_metadata) do
    :telemetry.execute(
      @telemetry_retry,
      %{duration: duration, delay_ms: delay},
      Map.merge(attempt_metadata, %{error: error})
    )
  end

  defp emit_retry_event({:exception, exception, _stacktrace}, duration, delay, attempt_metadata) do
    :telemetry.execute(
      @telemetry_retry,
      %{duration: duration, delay_ms: delay},
      Map.merge(attempt_metadata, %{exception: exception})
    )
  end

  defp emit_retry_event(_result, duration, delay, attempt_metadata) do
    :telemetry.execute(
      @telemetry_retry,
      %{duration: duration, delay_ms: delay},
      attempt_metadata
    )
  end

  defp emit_timeout_event(duration, attempt_metadata) do
    :telemetry.execute(
      @telemetry_failed,
      %{duration: duration},
      Map.merge(attempt_metadata, %{result: :failed})
    )
  end

  defp build_policy(%RetryHandler{} = handler) do
    backoff =
      Backoff.Policy.new(
        strategy: :exponential,
        base_ms: handler.base_delay_ms,
        max_ms: handler.max_delay_ms,
        jitter_strategy: :range,
        jitter: {1.0 - handler.jitter_pct, 1.0 + handler.jitter_pct}
      )

    FoundationRetry.Policy.new(
      max_attempts: handler.max_retries,
      progress_timeout_ms: handler.progress_timeout_ms,
      backoff: backoff,
      retry_on: &retryable_result?/1
    )
  end

  defp build_state(%RetryHandler{} = handler) do
    FoundationRetry.State.new(
      attempt: handler.attempt,
      start_time_ms: handler.start_time,
      last_progress_ms: handler.last_progress_at
    )
  end

  defp retryable_result?({:error, %Error{} = error}), do: Error.retryable?(error)
  defp retryable_result?({:error, _}), do: true
  defp retryable_result?({:exception, _exception, _stacktrace}), do: true
  defp retryable_result?(_), do: false
end
