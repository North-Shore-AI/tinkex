defmodule Tinkex.Future do
  @moduledoc """
  Client-side future abstraction responsible for polling server-side futures.

  `poll/2` returns `Task.t({:ok, map()} | {:error, Tinkex.Error.t()})`. Callers
  can `Task.await/2` or supervise the task to integrate with their concurrency
  model.

  ## Queue state telemetry

  The polling loop emits `[:tinkex, :queue, :state_change]` events whenever the
  queue state transitions (e.g., `:active` -> `:paused_rate_limit`). Telemetry
  metadata always includes `%{queue_state: atom, request_id: binary}` so
  observers can react:

      :telemetry.attach(
        "tinkex-queue-state-logger",
        [:tinkex, :queue, :state_change],
        fn _event, _measurements, %{queue_state: queue_state}, _config ->
          Logger.info("Queue state changed: \#{inspect(queue_state)}")
        end,
        nil
      )

  Provide `opts[:queue_state_observer]` with a module that implements
  `Tinkex.QueueStateObserver` to receive direct callbacks when transitions
  occur. TrainingClient/SamplingClient will implement this behaviour downstream.
  """

  require Logger

  alias Foundation.Backoff
  alias Tinkex.API.Futures
  alias Tinkex.Config
  alias Tinkex.Error

  alias Tinkex.Types.{
    FutureCompletedResponse,
    FutureFailedResponse,
    FuturePendingResponse,
    FutureRetrieveResponse,
    QueueState,
    RequestErrorCategory,
    TryAgainResponse
  }

  @queue_state_event [:tinkex, :queue, :state_change]
  @telemetry_timeout [:tinkex, :future, :timeout]
  @telemetry_api_error [:tinkex, :future, :api_error]
  @telemetry_connection_error [:tinkex, :future, :connection_error]
  @telemetry_request_failed [:tinkex, :future, :request_failed]
  @telemetry_validation_error [:tinkex, :future, :validation_error]
  @default_polling_http_timeout 45_000
  @initial_backoff 1_000
  @max_backoff 30_000

  @type sleep_fun :: (non_neg_integer() -> any())
  @type poll_backoff_policy ::
          :none
          | {:exponential, pos_integer(), pos_integer()}
          | (non_neg_integer() -> non_neg_integer())
  @type poll_result :: {:ok, map()} | {:error, Error.t()}
  @type poll_task :: Task.t()

  defmodule State do
    @moduledoc false
    @enforce_keys [:request_id, :request_payload, :config, :start_time_ms]
    defstruct request_id: nil,
              request_payload: nil,
              prev_queue_state: nil,
              prev_queue_state_reason: nil,
              config: nil,
              metadata: %{},
              request_type: nil,
              observer: nil,
              sleep_fun: nil,
              http_timeout: nil,
              poll_timeout: :infinity,
              poll_backoff: :none,
              create_roundtrip_time: nil,
              raw_response?: true,
              start_time_ms: nil,
              last_failed_error: nil

    @type t :: %__MODULE__{
            request_id: String.t(),
            request_payload: map(),
            prev_queue_state: QueueState.t() | nil,
            prev_queue_state_reason: String.t() | nil,
            config: Config.t(),
            metadata: map(),
            request_type: String.t() | nil,
            observer: module() | nil,
            sleep_fun: Tinkex.Future.sleep_fun(),
            http_timeout: pos_integer(),
            poll_timeout: pos_integer() | :infinity,
            poll_backoff: Tinkex.Future.poll_backoff_policy(),
            create_roundtrip_time: number() | nil,
            raw_response?: boolean(),
            start_time_ms: integer(),
            last_failed_error: Error.t() | nil
          }
  end

  @doc """
  Begin polling a future request.

  Accepts either the request id string or a map that contains `"request_id"` /
  `:request_id`. Per-request HTTP timeouts can be supplied via `:http_timeout`,
  while `:timeout` controls the overall polling deadline (`:infinity` by
  default). Tests can inject a custom `:sleep_fun` (defaults to `&Process.sleep/1`).

  Use `:poll_backoff` to control backoff for 408/5xx polling retries. Supported
  values: `:exponential`, `{:exponential, initial_ms, max_ms}`, or a 1-arity
  function that returns a non-negative delay in milliseconds. Defaults to no
  backoff unless configured.
  """
  @spec poll(String.t() | %{request_id: String.t()} | %{String.t() => String.t()}, keyword()) ::
          poll_task()
  def poll(request_or_payload, opts \\ []) do
    config = Keyword.fetch!(opts, :config)
    request_id = normalize_request_id(request_or_payload)

    sleep_fun =
      opts
      |> Keyword.get(:sleep_fun, &Process.sleep/1)
      |> ensure_sleep_fun()

    state = %State{
      request_id: request_id,
      request_payload: %{request_id: request_id},
      prev_queue_state: opts[:initial_queue_state],
      config: config,
      metadata:
        opts[:telemetry_metadata]
        |> build_metadata(request_id)
        |> merge_user_metadata(config),
      request_type: opts[:tinker_request_type],
      observer: opts[:queue_state_observer],
      sleep_fun: sleep_fun,
      http_timeout: Keyword.get(opts, :http_timeout, @default_polling_http_timeout),
      poll_timeout: Keyword.get(opts, :timeout, :infinity),
      poll_backoff: resolve_poll_backoff(opts, config),
      create_roundtrip_time: opts[:tinker_create_roundtrip_time],
      raw_response?: Keyword.get(opts, :raw_response?, true),
      start_time_ms: System.monotonic_time(:millisecond)
    }

    Task.async(fn -> poll_loop(state, 0) end)
  end

  @doc """
  Await the result of a polling task.

  Wraps `Task.await/2`, converting exits or timeouts into `{:error, %Tinkex.Error{}}`
  tuples with type `:api_timeout`. The timeout here controls how long the caller
  is willing to wait on the task process and is independent from the polling
  timeout configured in `poll/2`.
  """
  @spec await(poll_task(), timeout()) :: poll_result()
  def await(%Task{} = task, timeout \\ :infinity) do
    Task.await(task, timeout)
  catch
    :exit, {:timeout, _} ->
      Task.shutdown(task, :brutal_kill)
      {:error, build_await_timeout_error(timeout)}

    :exit, reason ->
      {:error, build_await_exit_error(reason)}
  end

  @doc """
  Await multiple polling tasks, returning the underlying results in input order.

  Each entry mirrors the Task's return value (`{:ok, result}` or
  `{:error, %Tinkex.Error{}}`). When a task exits or times out we convert it to
  `{:error, %Tinkex.Error{type: :api_timeout}}` rather than raising.
  """
  @spec await_many([poll_task()], timeout()) :: [poll_result()]
  def await_many(tasks, timeout \\ :infinity) when is_list(tasks) do
    Enum.map(tasks, &await(&1, timeout))
  end

  defp poll_loop(state, iteration) do
    case ensure_within_timeout(state) do
      {:error, error} ->
        emit_telemetry(
          @telemetry_timeout,
          %{elapsed_time: elapsed_since_start(state)},
          merge_user_metadata(
            %{
              request_id: state.request_id,
              request_type: state.request_type,
              iteration: iteration
            },
            state.config
          )
        )

        {:error, error}

      :ok ->
        do_poll(state, iteration)
    end
  end

  # Pass max_retries: 0 to disable HTTP-level retries for polling.
  # The polling loop handles retries for 408/5xx, matching Python SDK behavior.
  defp do_poll(state, iteration) do
    case Futures.retrieve(state.request_payload,
           config: state.config,
           timeout: state.http_timeout,
           max_retries: 0,
           tinker_request_iteration: iteration,
           tinker_request_type: state.request_type,
           tinker_create_roundtrip_time: state.create_roundtrip_time,
           raw_response?: state.raw_response?
         ) do
      {:ok, response} ->
        response
        |> FutureRetrieveResponse.from_json()
        |> handle_response(state, iteration)

      {:error, %Error{status: 410} = error} ->
        handle_expired_error(error, state, iteration)

      # Continue polling on 408 (Request Timeout).
      # Backoff is configurable to avoid tight loops during outages.
      {:error, %Error{status: 408} = error} ->
        emit_error_telemetry(@telemetry_api_error, error, iteration, state)
        retry_with_optional_backoff(%{state | last_failed_error: error}, iteration)

      # Continue polling on 5xx (Server Errors).
      # These are transient and should be retried until poll_timeout.
      {:error, %Error{status: status} = error}
      when is_integer(status) and status >= 500 and status < 600 ->
        emit_error_telemetry(@telemetry_api_error, error, iteration, state)
        retry_with_optional_backoff(%{state | last_failed_error: error}, iteration)

      # Python SDK parity: Continue polling on connection errors with backoff.
      {:error, %Error{type: :api_connection} = error} ->
        emit_error_telemetry(telemetry_event_for_error(error), error, iteration, state)

        sleep_and_continue(
          %{state | last_failed_error: error},
          calc_backoff(iteration),
          iteration
        )

      {:error, %Error{} = error} ->
        emit_error_telemetry(telemetry_event_for_error(error), error, iteration, state)
        {:error, error}
    end
  end

  defp handle_expired_error(error, state, iteration) do
    expired_error =
      Error.new(
        :api_status,
        "Promise expired for request #{state.request_id}; submit a new request.",
        status: 410,
        category: error.category || :server,
        data: %{request_id: state.request_id, original_error: error}
      )

    emit_error_telemetry(@telemetry_api_error, expired_error, iteration, state)
    {:error, expired_error}
  end

  defp handle_response(%FutureCompletedResponse{result: result}, _state, _iteration) do
    {:ok, result}
  end

  defp handle_response(%FuturePendingResponse{}, state, iteration) do
    sleep_and_continue(state, calc_backoff(iteration), iteration)
  end

  defp handle_response(%FutureFailedResponse{error: error_map}, state, iteration) do
    category =
      error_map
      |> error_category()
      |> RequestErrorCategory.parse()

    error = build_failed_error(state.request_id, category, error_map)

    case category do
      :user ->
        emit_error_telemetry(@telemetry_request_failed, error, iteration, state)
        {:error, error}

      _ ->
        emit_error_telemetry(@telemetry_request_failed, error, iteration, state)
        state = %{state | last_failed_error: error}
        sleep_and_continue(state, calc_backoff(iteration), iteration)
    end
  end

  defp handle_response(%TryAgainResponse{} = response, state, iteration) do
    state =
      maybe_emit_queue_state_change(
        state,
        response.queue_state,
        response.queue_state_reason
      )

    sleep_ms = try_again_sleep_ms(response, iteration)
    sleep_and_continue(state, sleep_ms, iteration)
  end

  defp sleep_and_continue(state, sleep_ms, iteration) do
    state.sleep_fun.(sleep_ms)
    poll_loop(state, iteration + 1)
  end

  defp retry_with_optional_backoff(state, iteration) do
    case state.poll_backoff do
      :none ->
        poll_loop(state, iteration + 1)

      {:exponential, initial_ms, max_ms} ->
        sleep_and_continue(state, calc_backoff(iteration, initial_ms, max_ms), iteration)

      fun when is_function(fun, 1) ->
        sleep_ms = fun.(iteration) |> normalize_sleep_ms()
        sleep_and_continue(state, sleep_ms, iteration)
    end
  end

  defp ensure_within_timeout(%State{poll_timeout: :infinity}), do: :ok

  defp ensure_within_timeout(%State{poll_timeout: timeout} = state)
       when is_integer(timeout) and timeout > 0 do
    elapsed = System.monotonic_time(:millisecond) - state.start_time_ms
    evaluate_timeout(elapsed, timeout, state)
  end

  defp timeout_error(%State{last_failed_error: %Error{} = error}), do: error

  defp timeout_error(%State{} = state) do
    Error.new(
      :api_timeout,
      "Timed out while polling future #{state.request_id}",
      data: %{request_id: state.request_id}
    )
  end

  defp evaluate_timeout(elapsed, timeout, state) when elapsed > timeout,
    do: {:error, timeout_error(state)}

  defp evaluate_timeout(_elapsed, _timeout, _state), do: :ok

  @max_backoff_exponent 30

  defp calc_backoff(iteration, initial_ms \\ @initial_backoff, max_ms \\ @max_backoff)
       when is_integer(iteration) and iteration >= 0 do
    capped_iteration = min(iteration, max_exponent(initial_ms, max_ms))
    capped_iteration = min(capped_iteration, @max_backoff_exponent)

    policy =
      Backoff.Policy.new(
        strategy: :exponential,
        base_ms: initial_ms,
        max_ms: max_ms,
        jitter_strategy: :none
      )

    Backoff.delay(policy, capped_iteration)
  end

  defp try_again_sleep_ms(%TryAgainResponse{retry_after_ms: ms}, _iteration)
       when is_integer(ms),
       do: ms

  defp try_again_sleep_ms(%TryAgainResponse{queue_state: state}, _iteration)
       when state in [:paused_rate_limit, :paused_capacity] do
    1_000
  end

  defp try_again_sleep_ms(_response, iteration), do: calc_backoff(iteration)

  defp resolve_poll_backoff(opts, %Config{} = config) do
    opts
    |> Keyword.get(:poll_backoff, config.poll_backoff)
    |> normalize_poll_backoff()
  end

  defp normalize_poll_backoff(nil), do: :none
  defp normalize_poll_backoff(false), do: :none
  defp normalize_poll_backoff(:none), do: :none
  defp normalize_poll_backoff(true), do: {:exponential, @initial_backoff, @max_backoff}
  defp normalize_poll_backoff(:exponential), do: {:exponential, @initial_backoff, @max_backoff}

  defp normalize_poll_backoff({:exponential, initial_ms, max_ms})
       when is_integer(initial_ms) and initial_ms > 0 and is_integer(max_ms) and
              max_ms >= initial_ms do
    {:exponential, initial_ms, max_ms}
  end

  defp normalize_poll_backoff(fun) when is_function(fun, 1), do: fun
  defp normalize_poll_backoff(_), do: :none

  defp normalize_sleep_ms(value) when is_integer(value) and value >= 0, do: value
  defp normalize_sleep_ms(value) when is_float(value) and value >= 0, do: trunc(value)
  defp normalize_sleep_ms(_), do: 0

  defp max_exponent(initial_ms, max_ms)
       when is_integer(initial_ms) and initial_ms > 0 and is_integer(max_ms) and
              max_ms > initial_ms do
    ratio = max_ms / initial_ms
    trunc(:math.log(ratio) / :math.log(2)) + 1
  end

  defp max_exponent(_initial_ms, _max_ms), do: 0

  defp build_failed_error(request_id, category, error_map) do
    message =
      Map.get(error_map, "message") ||
        Map.get(error_map, :message) ||
        "Future request #{request_id} failed"

    Error.new(:request_failed, message,
      category: category,
      data: %{
        request_id: request_id,
        error: error_map
      }
    )
  end

  defp maybe_emit_queue_state_change(state, queue_state, queue_state_reason) do
    cond do
      not valid_queue_state?(queue_state) ->
        state

      state.prev_queue_state == queue_state and
          state.prev_queue_state_reason == queue_state_reason ->
        state

      true ->
        metadata =
          state.metadata
          |> Map.put(:queue_state, queue_state)
          |> Map.put(:queue_state_reason, queue_state_reason)

        :telemetry.execute(@queue_state_event, %{}, metadata)
        notify_observer(state.observer, queue_state, metadata)

        %{
          state
          | prev_queue_state: queue_state,
            prev_queue_state_reason: queue_state_reason
        }
    end
  end

  defp notify_observer(nil, _queue_state, _metadata), do: :ok

  defp notify_observer(observer, queue_state, metadata) when is_atom(observer) do
    # Prefer 2-arity callback with metadata for context (session_id, model_id, etc.)
    # Fall back to 1-arity for backward compatibility with existing observers
    if function_exported?(observer, :on_queue_state_change, 2) do
      observer.on_queue_state_change(queue_state, metadata)
    else
      observer.on_queue_state_change(queue_state)
    end
  rescue
    _e in UndefinedFunctionError ->
      :ok

    exception ->
      Logger.warning(
        "QueueStateObserver #{inspect(observer)} crashed: #{Exception.message(exception)}"
      )

      :ok
  end

  defp notify_observer(_observer, _queue_state, _metadata), do: :ok

  defp valid_queue_state?(state) when is_atom(state) do
    state in [:active, :paused_rate_limit, :paused_capacity, :unknown]
  end

  defp valid_queue_state?(_), do: false

  defp build_metadata(nil, request_id), do: %{request_id: request_id}

  defp build_metadata(metadata, request_id) do
    metadata
    |> Map.new()
    |> Map.put_new(:request_id, request_id)
  end

  defp merge_user_metadata(metadata, %Config{user_metadata: %{} = user_metadata}) do
    Map.merge(metadata, user_metadata)
  end

  defp merge_user_metadata(metadata, _config), do: metadata

  defp telemetry_event_for_error(%Error{type: :api_connection}), do: @telemetry_connection_error
  defp telemetry_event_for_error(%Error{type: :validation}), do: @telemetry_validation_error
  defp telemetry_event_for_error(%Error{type: :request_failed}), do: @telemetry_request_failed
  defp telemetry_event_for_error(%Error{}), do: @telemetry_api_error

  defp emit_error_telemetry(event, %Error{} = error, iteration, state) do
    emit_telemetry(
      event,
      %{elapsed_time: elapsed_since_start(state)},
      merge_user_metadata(
        %{
          request_id: state.request_id,
          request_type: state.request_type,
          iteration: iteration,
          status: error.status,
          category: error.category,
          error_type: error.type
        },
        state.config
      )
    )
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  defp elapsed_since_start(%State{start_time_ms: start_time_ms}) do
    System.monotonic_time(:millisecond) - start_time_ms
  end

  defp error_category(error_map) do
    Map.get(error_map, "category") || Map.get(error_map, :category)
  end

  defp normalize_request_id(%{request_id: id}), do: ensure_binary!(id)
  defp normalize_request_id(%{"request_id" => id}), do: ensure_binary!(id)
  defp normalize_request_id(request_id) when is_binary(request_id), do: request_id

  defp normalize_request_id(other) do
    raise ArgumentError,
          "expected request id string or map with request_id, got: #{inspect(other)}"
  end

  defp ensure_binary!(value) when is_binary(value), do: value

  defp ensure_binary!(value) do
    raise ArgumentError, "expected request_id to be binary, got: #{inspect(value)}"
  end

  defp ensure_sleep_fun(fun) when is_function(fun, 1), do: fun
  defp ensure_sleep_fun(_), do: &Process.sleep/1

  defp build_await_timeout_error(:infinity) do
    Error.new(:api_timeout, "Future task timed out while awaiting result")
  end

  defp build_await_timeout_error(timeout) when is_integer(timeout) and timeout >= 0 do
    Error.new(:api_timeout, "Future task did not complete within #{timeout}ms",
      data: %{timeout: timeout}
    )
  end

  defp build_await_timeout_error(timeout) do
    Error.new(:api_timeout, "Future task timed out after #{inspect(timeout)}",
      data: %{timeout: timeout}
    )
  end

  defp build_await_exit_error(reason) do
    Error.new(
      :api_timeout,
      "Future task exited while awaiting result: #{Exception.format_exit(reason)}",
      data: %{exit_reason: reason}
    )
  end
end
