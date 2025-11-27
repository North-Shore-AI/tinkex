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
  @initial_backoff 1_000
  @max_backoff 30_000

  @type sleep_fun :: (non_neg_integer() -> any())
  @type poll_result :: {:ok, map()} | {:error, Error.t()}
  @type poll_task :: Task.t()

  defmodule State do
    @moduledoc false
    @enforce_keys [:request_id, :request_payload, :config, :start_time_ms]
    defstruct request_id: nil,
              request_payload: nil,
              prev_queue_state: nil,
              config: nil,
              metadata: %{},
              request_type: nil,
              observer: nil,
              sleep_fun: nil,
              http_timeout: nil,
              poll_timeout: :infinity,
              create_roundtrip_time: nil,
              raw_response?: true,
              start_time_ms: nil,
              last_failed_error: nil

    @type t :: %__MODULE__{
            request_id: String.t(),
            request_payload: map(),
            prev_queue_state: QueueState.t() | nil,
            config: Config.t(),
            metadata: map(),
            request_type: String.t() | nil,
            observer: module() | nil,
            sleep_fun: Tinkex.Future.sleep_fun(),
            http_timeout: pos_integer(),
            poll_timeout: pos_integer() | :infinity,
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
      metadata: build_metadata(opts[:telemetry_metadata], request_id),
      request_type: opts[:tinker_request_type],
      observer: opts[:queue_state_observer],
      sleep_fun: sleep_fun,
      http_timeout: Keyword.get(opts, :http_timeout, config.timeout),
      poll_timeout: Keyword.get(opts, :timeout, :infinity),
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
    try do
      Task.await(task, timeout)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, build_await_timeout_error(timeout)}

      :exit, reason ->
        {:error, build_await_exit_error(reason)}
    end
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
        {:error, error}

      :ok ->
        case Futures.retrieve(state.request_payload,
               config: state.config,
               timeout: state.http_timeout,
               tinker_request_iteration: iteration,
               tinker_request_type: state.request_type,
               tinker_create_roundtrip_time: state.create_roundtrip_time,
               raw_response?: state.raw_response?
             ) do
          {:ok, response} ->
            response
            |> FutureRetrieveResponse.from_json()
            |> handle_response(state, iteration)

          {:error, %Error{} = error} ->
            {:error, error}
        end
    end
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
        {:error, error}

      _ ->
        state = %{state | last_failed_error: error}
        sleep_and_continue(state, calc_backoff(iteration), iteration)
    end
  end

  defp handle_response(%TryAgainResponse{} = response, state, iteration) do
    state = maybe_emit_queue_state_change(state, response.queue_state)
    sleep_ms = try_again_sleep_ms(response, iteration)
    sleep_and_continue(state, sleep_ms, iteration)
  end

  defp sleep_and_continue(state, sleep_ms, iteration) do
    state.sleep_fun.(sleep_ms)
    poll_loop(state, iteration + 1)
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

  defp calc_backoff(iteration) when is_integer(iteration) and iteration >= 0 do
    backoff = trunc(:math.pow(2, iteration)) * @initial_backoff
    min(backoff, @max_backoff)
  end

  defp try_again_sleep_ms(%TryAgainResponse{retry_after_ms: ms}, _iteration)
       when is_integer(ms),
       do: ms

  defp try_again_sleep_ms(%TryAgainResponse{queue_state: state}, _iteration)
       when state in [:paused_rate_limit, :paused_capacity] do
    1_000
  end

  defp try_again_sleep_ms(_response, iteration), do: calc_backoff(iteration)

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

  defp maybe_emit_queue_state_change(state, queue_state) do
    cond do
      not valid_queue_state?(queue_state) ->
        state

      state.prev_queue_state == queue_state ->
        state

      true ->
        metadata = Map.put(state.metadata, :queue_state, queue_state)
        :telemetry.execute(@queue_state_event, %{}, metadata)
        notify_observer(state.observer, queue_state, metadata)
        %{state | prev_queue_state: queue_state}
    end
  end

  defp notify_observer(nil, _queue_state, _metadata), do: :ok

  defp notify_observer(observer, queue_state, metadata) when is_atom(observer) do
    try do
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
