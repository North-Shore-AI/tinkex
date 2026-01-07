defmodule Tinkex.Domain.Sampling.Client do
  @moduledoc """
  Sampling client that performs lock-free reads via ETS.

  Init runs in a GenServer to create the sampling session and register state in
  `Tinkex.SamplingRegistry`. Once initialized, `sample/4` reads configuration
  directly from ETS without touching the GenServer, avoiding bottlenecks under
  high load.

  For plain-text prompts, build a `Tinkex.Types.ModelInput` via
  `Tinkex.Types.ModelInput.from_text/2` with the target model name. Chat
  templates are not applied automatically.

  ## Queue State Observer

  This client implements `Tinkex.QueueStateObserver` and automatically logs
  human-readable warnings when queue state changes indicate rate limiting
  or capacity issues:

      [warning] Sampling is paused for session-123. Reason: concurrent sampler weights limit hit

  Logs are debounced to once per 60 seconds per session to avoid spam.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver

  require Logger

  alias Pristine.Core.Context

  alias Tinkex.API.{Sampling, Service}
  alias Tinkex.Context, as: ContextBuilder
  alias Tinkex.QueueStateLogger

  alias Tinkex.{
    ByteEstimator,
    Error,
    Future,
    PoolKey,
    SamplingDispatch,
    SamplingRegistry
  }

  alias Tinkex.Telemetry.Capture, as: TelemetryCapture
  alias Tinkex.Telemetry.Reporter
  require TelemetryCapture

  alias Tinkex.Types.{
    CreateSamplingSessionRequest,
    CreateSamplingSessionResponse,
    SampleRequest,
    SampleResponse,
    SamplingParams
  }

  alias Tinkex.Types.QueueState

  @type t :: pid()
  @default_dispatch_concurrency 400
  @throttled_dispatch_concurrency 10
  @default_byte_budget 5 * 1024 * 1024
  @default_retry_max_retries :infinity
  @default_retry_base_delay_ms 500
  @default_retry_max_delay_ms 10_000
  @default_retry_jitter_pct 0.25
  @default_retry_progress_timeout_ms 7_200_000
  @default_retry_max_connections 1000
  @default_retry_enable_retry_logic true
  @retry_semaphore_backoff_base_ms 2
  @retry_semaphore_backoff_max_ms 50
  @retry_semaphore_backoff_jitter 0.25
  @retry_semaphore_registry :tinkex_retry_semaphores

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Create a sampling client asynchronously.

  This is a convenience function that delegates to `ServiceClient.create_sampling_client_async/2`.

  ## Examples

      task = SamplingClient.create_async(service_pid, base_model: "meta-llama/Llama-3.2-1B")
      {:ok, sampling_pid} = Task.await(task)
  """
  @spec create_async(pid(), keyword()) :: Task.t()
  def create_async(service_client, opts \\ []) do
    Tinkex.ServiceClient.create_sampling_client_async(service_client, opts)
  end

  @doc """
  Submit a sampling request.

  Returns a `Task.t()` that yields `{:ok, %SampleResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec sample(t(), map(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def sample(client, prompt, sampling_params, opts \\ []) do
    reporter = telemetry_reporter_for(client)

    {:ok,
     TelemetryCapture.async_capture reporter: reporter, fatal?: true do
       do_sample(client, prompt, sampling_params, opts)
     end}
  end

  @doc """
  Stream a sampling request, yielding tokens incrementally via SSE.

  Returns `{:ok, stream}` where stream is an `Enumerable.t()` of
  `Tinkex.Types.SampleStreamChunk` structs, or `{:error, %Tinkex.Error{}}`.

  ## Examples

      {:ok, stream} = SamplingClient.sample_stream(client, prompt, params)
      Enum.each(stream, fn chunk ->
        IO.write(chunk.token)
      end)
  """
  @spec sample_stream(t(), map(), map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def sample_stream(client, prompt, sampling_params, opts \\ []) do
    case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
      [{{:config, ^client}, entry}] ->
        do_sample_stream(entry, prompt, sampling_params, opts)

      [] ->
        {:error, Error.new(:validation, "SamplingClient not initialized")}
    end
  end

  @doc """
  Convenience helper to compute prompt token log probabilities.

  Returns a Task that yields `{:ok, [float() | nil]}` or `{:error, %Tinkex.Error{}}`.
  """
  @spec compute_logprobs(t(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def compute_logprobs(client, prompt, opts \\ []) do
    params = %SamplingParams{max_tokens: 1}
    reporter = telemetry_reporter_for(client)

    {:ok,
     TelemetryCapture.async_capture reporter: reporter, fatal?: true do
       case do_sample(client, prompt, params,
              num_samples: 1,
              prompt_logprobs: true,
              topk_prompt_logprobs: Keyword.get(opts, :topk_prompt_logprobs, 0)
            ) do
         {:ok, %SampleResponse{prompt_logprobs: logprobs}} ->
           {:ok, logprobs}

         {:error, %Error{} = error} ->
           {:error, error}
       end
     end}
  end

  @impl true
  def init(opts) do
    context = resolve_context(opts)
    config = context.config
    session_id = Keyword.fetch!(opts, :session_id)
    sampling_client_id = Keyword.fetch!(opts, :sampling_client_id)
    base_model = Keyword.get(opts, :base_model)
    model_path = Keyword.get(opts, :model_path)
    sampling_session_id_override = Keyword.get(opts, :sampling_session_id)
    service_api = Keyword.get(opts, :service_api, Service)
    sampling_api = Keyword.get(opts, :sampling_api, Sampling)
    retry_config = build_retry_config(context, opts[:retry_config])

    telemetry_metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.new()
      |> Map.put_new(:session_id, session_id)

    limiter = rate_limiter_for(context, config.base_url, config.api_key)
    request_counter = :atomics.new(1, signed: false)

    dispatch_limit =
      normalize_dispatch_limit(
        Keyword.get(opts, :dispatch_concurrency, @default_dispatch_concurrency)
      )

    with :ok <- validate_sampling_inputs(base_model, model_path),
         {:ok, sampling_session_id} <-
           resolve_sampling_session_id(
             sampling_session_id_override,
             session_id,
             sampling_client_id,
             base_model,
             model_path,
             config,
             telemetry_metadata,
             service_api
           ),
         {:ok, dispatch} <-
           SamplingDispatch.start_link(
             rate_limiter: limiter,
             base_url: config.base_url,
             api_key: config.api_key,
             concurrency: dispatch_limit,
             throttled_concurrency:
               Keyword.get(opts, :throttled_dispatch_concurrency, @throttled_dispatch_concurrency),
             byte_budget: Keyword.get(opts, :byte_budget, @default_byte_budget)
           ) do
      telemetry_metadata =
        opts
        |> Keyword.get(:telemetry_metadata, %{})
        |> Map.new()
        |> Map.put_new(:session_id, session_id)
        |> Map.put_new(:sampling_session_id, sampling_session_id)

      entry = %{
        sampling_session_id: sampling_session_id,
        http_pool: config.http_pool,
        request_id_counter: request_counter,
        rate_limiter: limiter,
        dispatch: dispatch,
        config: config,
        context: context,
        retry_config: retry_config,
        sampling_api: sampling_api,
        telemetry_metadata: telemetry_metadata,
        session_id: session_id,
        last_queue_state_logged: nil
      }

      :ok = SamplingRegistry.register(self(), entry)

      telemetry = Keyword.get(opts, :telemetry)
      put_telemetry(telemetry)

      {:ok,
       %{
         sampling_session_id: sampling_session_id,
         request_id_counter: request_counter,
         rate_limiter: limiter,
         dispatch: dispatch,
         config: config,
         context: context,
         retry_config: retry_config,
         sampling_api: sampling_api,
         telemetry_metadata: telemetry_metadata,
         telemetry: telemetry,
         session_id: session_id
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    clear_queue_state_debounce(state[:sampling_session_id])
    Reporter.stop(state[:telemetry])
    :ok
  end

  defp resolve_context(opts) do
    case Keyword.get(opts, :context) do
      %Context{} = context -> context
      _ -> ContextBuilder.new(Keyword.fetch!(opts, :config))
    end
  end

  @impl true
  def get_telemetry do
    :erlang.get({__MODULE__, :telemetry})
  end

  def get_telemetry(client) when is_pid(client) do
    GenServer.call(client, :get_telemetry)
  end

  defp telemetry_reporter_for(client) do
    get_telemetry(client)
  catch
    _, _ -> nil
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    {:reply, state.telemetry, state}
  end

  # QueueStateObserver implementation
  # This callback is invoked by Future.poll when queue state changes (e.g., rate limit hit).
  # We use metadata to identify the session and ETS to track debouncing per session.
  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state, metadata \\ %{}) do
    session_id = metadata[:sampling_session_id] || metadata[:session_id] || "unknown"
    server_reason = metadata[:queue_state_reason]

    # Look up the last logged timestamp from ETS registry
    # Use :persistent_term for debounce tracking keyed by session_id
    debounce_key = {:sampling_queue_state_debounce, session_id}

    last_logged =
      case :persistent_term.get(debounce_key, nil) do
        nil -> nil
        ts -> ts
      end

    new_timestamp =
      QueueStateLogger.maybe_log(queue_state, :sampling, session_id, last_logged, server_reason)

    # Update the debounce timestamp if it changed
    if new_timestamp != last_logged do
      :persistent_term.put(debounce_key, new_timestamp)
    end

    :ok
  end

  @doc """
  Clear debounce state for a sampling session to avoid unbounded growth.
  """
  @spec clear_queue_state_debounce(String.t()) :: :ok
  def clear_queue_state_debounce(session_id) when is_binary(session_id) do
    debounce_key = {:sampling_queue_state_debounce, session_id}

    try do
      :persistent_term.erase(debounce_key)
    rescue
      ArgumentError ->
        :ok
    end

    :ok
  end

  defp do_sample(client, prompt, sampling_params, opts) do
    case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
      [{{:config, ^client}, entry}] ->
        execute_sample(entry, prompt, sampling_params, opts)

      [] ->
        {:error, Error.new(:validation, "SamplingClient not initialized")}
    end
  end

  defp execute_sample(entry, prompt, sampling_params, opts) do
    estimated_bytes = ByteEstimator.estimate_model_input_bytes(prompt)

    dispatch_fun =
      build_sample_dispatch_fun(entry, prompt, sampling_params, estimated_bytes, opts)

    SamplingDispatch.with_rate_limit(entry.dispatch, estimated_bytes, dispatch_fun)
  end

  defp build_sample_dispatch_fun(entry, prompt, sampling_params, estimated_bytes, opts) do
    fn ->
      if entry.retry_config.enable_retry_logic do
        do_sample_with_retry(entry, prompt, sampling_params, estimated_bytes, opts)
      else
        do_sample_once(entry, prompt, sampling_params, estimated_bytes, opts)
      end
    end
  end

  defp create_sampling_session(
         session_id,
         sampling_client_id,
         base_model,
         model_path,
         config,
         telemetry_metadata,
         service_api
       ) do
    request = %CreateSamplingSessionRequest{
      session_id: session_id,
      sampling_session_seq_id: sampling_client_id,
      base_model: base_model,
      model_path: model_path
    }

    case service_api.create_sampling_session(request,
           config: config,
           telemetry_metadata: telemetry_metadata
         ) do
      {:ok, %CreateSamplingSessionResponse{sampling_session_id: sampling_session_id}} ->
        {:ok, sampling_session_id}

      {:ok, %{"sampling_session_id" => sampling_session_id}} ->
        {:ok, sampling_session_id}

      {:ok, %{sampling_session_id: sampling_session_id}} ->
        {:ok, sampling_session_id}

      {:error, _} = error ->
        error
    end
  end

  defp validate_sampling_inputs(nil, nil) do
    {:error,
     Error.new(:validation, "Either model_path or base_model must be provided", category: :user)}
  end

  defp validate_sampling_inputs(_base_model, _model_path), do: :ok

  defp resolve_sampling_session_id(
         nil,
         session_id,
         sampling_client_id,
         base_model,
         model_path,
         config,
         telemetry_metadata,
         service_api
       ) do
    create_sampling_session(
      session_id,
      sampling_client_id,
      base_model,
      model_path,
      config,
      telemetry_metadata,
      service_api
    )
  end

  defp resolve_sampling_session_id(
         sampling_session_id,
         _session_id,
         _sampling_client_id,
         _base_model,
         _model_path,
         _config,
         _telemetry_metadata,
         _service_api
       )
       when is_binary(sampling_session_id) do
    {:ok, sampling_session_id}
  end

  defp next_seq_id(counter) do
    :atomics.add_get(counter, 1, 1) - 1
  end

  defp handle_sample_response(%{"request_id" => _} = future, entry, seq_id, opts) do
    poll_sample_future(future, entry, seq_id, opts)
  end

  defp handle_sample_response(%{request_id: _} = future, entry, seq_id, opts) do
    poll_sample_future(future, entry, seq_id, opts)
  end

  defp handle_sample_response(resp, _entry, _seq_id, _opts) do
    {:ok, SampleResponse.from_json(resp)}
  end

  defp poll_sample_future(future, entry, seq_id, opts) do
    # Use __MODULE__ as observer by default for automatic queue state logging
    # Users can override with their own observer via opts[:queue_state_observer]
    observer = Keyword.get(opts, :queue_state_observer, __MODULE__)

    poll_opts =
      [
        config: entry.config,
        timeout: Keyword.get(opts, :timeout, :infinity),
        telemetry_metadata: merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata]),
        queue_state_observer: observer,
        sleep_fun: opts[:sleep_fun],
        tinker_request_type: "Sample",
        tinker_request_iteration: seq_id
      ]
      |> maybe_put_http_timeout(opts[:http_timeout])

    poll_task = Future.poll(future, poll_opts)

    case Future.await(poll_task, Keyword.get(opts, :await_timeout, :infinity)) do
      {:ok, result} -> {:ok, SampleResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp merge_metadata(base, override) do
    base = base || %{}
    override = override || %{}

    base
    |> Map.new()
    |> Map.merge(Map.new(override))
  end

  defp maybe_put_http_timeout(opts, timeout) when is_integer(timeout) and timeout > 0 do
    Keyword.put(opts, :http_timeout, timeout)
  end

  defp maybe_put_http_timeout(opts, _timeout), do: opts

  defp normalize_dispatch_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_dispatch_limit(_), do: @default_dispatch_concurrency

  defp put_telemetry(nil), do: :ok
  defp put_telemetry(pid), do: :erlang.put({__MODULE__, :telemetry}, pid)

  defp rate_limiter_for(context, base_url, api_key) do
    key = rate_limit_key(base_url, api_key)
    context.rate_limiter.for_key(key, registry: :tinkex_rate_limiters)
  end

  defp rate_limit_key(base_url, api_key) do
    normalized_base = PoolKey.normalize_base_url(base_url)
    {:limiter, {normalized_base, api_key}}
  end

  defp with_retry_semaphore(context, key, max_connections, fun) when is_function(fun, 0) do
    name = retry_semaphore_name(key, max_connections)
    backoff = retry_semaphore_backoff(context)

    :ok =
      context.semaphore.acquire_blocking(
        @retry_semaphore_registry,
        name,
        max_connections,
        backoff
      )

    try do
      fun.()
    after
      context.semaphore.release(@retry_semaphore_registry, name)
    end
  end

  defp retry_semaphore_name(key, max_connections) do
    {:tinkex_retry, key, max_connections}
  end

  defp retry_semaphore_backoff(context) do
    context.retry.build_backoff(
      strategy: :exponential,
      base_ms: @retry_semaphore_backoff_base_ms,
      max_ms: @retry_semaphore_backoff_max_ms,
      jitter_strategy: :factor,
      jitter: @retry_semaphore_backoff_jitter
    )
  end

  defp build_retry_config(context, nil), do: default_retry_config(context)

  defp build_retry_config(context, %{max_attempts: _} = policy),
    do: default_retry_config(context, policy)

  defp build_retry_config(context, opts) when is_list(opts) do
    max_connections = Keyword.get(opts, :max_connections, @default_retry_max_connections)
    enable_retry_logic = Keyword.get(opts, :enable_retry_logic, @default_retry_enable_retry_logic)

    validate_retry_max_connections!(max_connections)
    validate_retry_enable_retry_logic!(enable_retry_logic)

    policy =
      opts
      |> Keyword.drop([:max_connections, :enable_retry_logic])
      |> build_retry_policy(context)

    %{
      policy: policy,
      max_connections: max_connections,
      enable_retry_logic: enable_retry_logic
    }
  end

  defp build_retry_config(_context, other) do
    raise ArgumentError,
          "retry_config must be a retry policy struct or keyword list, got: #{inspect(other)}"
  end

  defp default_retry_config(context, policy \\ nil)

  defp default_retry_config(context, nil) do
    default_retry_config(context, default_retry_policy(context))
  end

  defp default_retry_config(_context, policy) do
    %{
      policy: policy,
      max_connections: @default_retry_max_connections,
      enable_retry_logic: @default_retry_enable_retry_logic
    }
  end

  defp default_retry_policy(context) do
    build_retry_policy([], context)
  end

  defp build_retry_policy(opts, context) when is_list(opts) do
    max_attempts = normalize_max_attempts(opts)
    retry_on = Keyword.get(opts, :retry_on, &default_retry_on/1)
    backoff = build_retry_backoff(opts, context)

    progress_timeout_ms =
      Keyword.get(opts, :progress_timeout_ms, @default_retry_progress_timeout_ms)

    context.retry.build_policy(
      max_attempts: max_attempts,
      backoff: backoff,
      retry_on: retry_on,
      progress_timeout_ms: progress_timeout_ms
    )
  end

  defp normalize_max_attempts(opts) do
    cond do
      Keyword.has_key?(opts, :max_attempts) ->
        Keyword.fetch!(opts, :max_attempts)

      Keyword.has_key?(opts, :max_retries) ->
        to_max_attempts(Keyword.fetch!(opts, :max_retries))

      true ->
        to_max_attempts(@default_retry_max_retries)
    end
  end

  defp to_max_attempts(:infinity), do: :infinity

  defp to_max_attempts(max_retries) when is_integer(max_retries) and max_retries >= 0 do
    max_retries
  end

  defp to_max_attempts(max_retries) do
    raise ArgumentError,
          "max_retries must be a non-negative integer or :infinity, got: #{inspect(max_retries)}"
  end

  defp build_retry_backoff(opts, context) do
    case Keyword.get(opts, :backoff) do
      %{} = backoff ->
        backoff

      _ ->
        base_delay_ms = Keyword.get(opts, :base_delay_ms, @default_retry_base_delay_ms)
        max_delay_ms = Keyword.get(opts, :max_delay_ms, @default_retry_max_delay_ms)
        jitter_pct = Keyword.get(opts, :jitter_pct, @default_retry_jitter_pct)
        {jitter_strategy, jitter} = jitter_settings(jitter_pct)

        context.retry.build_backoff(
          strategy: :exponential,
          base_ms: base_delay_ms,
          max_ms: max_delay_ms,
          jitter_strategy: jitter_strategy,
          jitter: jitter
        )
    end
  end

  defp jitter_settings(jitter_pct) when is_number(jitter_pct) and jitter_pct > 0 do
    {:range, {1.0 - jitter_pct, 1.0 + jitter_pct}}
  end

  defp jitter_settings(_jitter_pct), do: {:none, 0.0}

  defp default_retry_on({:error, %Error{} = error}), do: Error.retryable?(error)
  defp default_retry_on({:error, {:exception, _exception}}), do: true
  defp default_retry_on({:error, {:exception, _exception, _stacktrace}}), do: true
  defp default_retry_on({:error, _reason}), do: true
  defp default_retry_on(_result), do: false

  defp validate_retry_max_connections!(max_connections) do
    unless is_integer(max_connections) and max_connections > 0 do
      raise ArgumentError,
            "max_connections must be a positive integer, got: #{inspect(max_connections)}"
    end
  end

  defp validate_retry_enable_retry_logic!(enable_retry_logic) do
    unless is_boolean(enable_retry_logic) do
      raise ArgumentError,
            "enable_retry_logic must be a boolean, got: #{inspect(enable_retry_logic)}"
    end
  end

  defp do_sample_with_retry(entry, prompt, sampling_params, estimated_bytes, opts) do
    execute = fn ->
      run_with_retry(
        entry.context,
        fn -> do_sample_once(entry, prompt, sampling_params, estimated_bytes, opts) end,
        entry.retry_config.policy
      )
    end

    if entry.retry_config.max_connections > 0 do
      with_retry_semaphore(
        entry.context,
        entry.session_id,
        entry.retry_config.max_connections,
        execute
      )
    else
      execute.()
    end
  end

  defp run_with_retry(context, fun, policy) when is_function(fun, 0) do
    result =
      context.retry.with_retry(
        fn ->
          try do
            fun.()
          rescue
            exception ->
              {:error, {:exception, exception, __STACKTRACE__}}
          end
        end,
        policy: policy
      )

    normalize_retry_result(result)
  end

  defp normalize_retry_result({:error, :progress_timeout}) do
    {:error, Error.new(:api_timeout, "Progress timeout exceeded")}
  end

  defp normalize_retry_result({:error, :max_elapsed}) do
    {:error, Error.new(:api_timeout, "Retry max elapsed exceeded")}
  end

  defp normalize_retry_result({:error, {:exception, exception, _stacktrace}}) do
    {:error, Error.new(:request_failed, Exception.message(exception))}
  end

  defp normalize_retry_result({:error, {:exception, exception}}) do
    {:error, Error.new(:request_failed, Exception.message(exception))}
  end

  defp normalize_retry_result(result), do: result

  defp do_sample_once(entry, prompt, sampling_params, estimated_bytes, opts) do
    entry.context.rate_limiter.wait(entry.rate_limiter)
    seq_id = next_seq_id(entry.request_id_counter)

    request =
      %SampleRequest{
        sampling_session_id: entry.sampling_session_id,
        seq_id: seq_id,
        prompt: prompt,
        sampling_params: sampling_params,
        num_samples: Keyword.get(opts, :num_samples, 1),
        prompt_logprobs: Keyword.get(opts, :prompt_logprobs),
        topk_prompt_logprobs: Keyword.get(opts, :topk_prompt_logprobs, 0)
      }

    api_opts =
      opts
      |> Keyword.put(:config, entry.config)
      |> Keyword.put(:tinker_request_type, "Sample")
      |> Keyword.put(:tinker_request_iteration, seq_id)
      |> Keyword.put(
        :telemetry_metadata,
        merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata])
      )

    case entry.sampling_api.sample_async(request, api_opts) do
      {:ok, resp} ->
        entry.context.rate_limiter.clear(entry.rate_limiter)
        handle_sample_response(resp, entry, seq_id, opts)

      {:error, %Error{status: 429} = error} ->
        maybe_log_queue_state_from_error(entry, error)
        SamplingDispatch.set_backoff(entry.dispatch, backoff_duration(estimated_bytes))
        {:error, error}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp backoff_duration(estimated_bytes) when estimated_bytes <= 128 * 1024, do: 1_000
  defp backoff_duration(_estimated_bytes), do: 5_000

  defp maybe_log_queue_state_from_error(entry, %Error{data: data}) when is_map(data) do
    queue_state =
      Map.get(data, "queue_state") ||
        Map.get(data, :queue_state)

    reason =
      Map.get(data, "queue_state_reason") ||
        Map.get(data, :queue_state_reason)

    request_id = Map.get(data, "request_id") || Map.get(data, :request_id)

    case QueueState.parse(queue_state) do
      :unknown ->
        :ok

      parsed_state ->
        metadata =
          %{
            sampling_session_id: entry.sampling_session_id,
            session_id: entry.session_id,
            request_id: request_id,
            queue_state_reason: reason
          }

        on_queue_state_change(parsed_state, metadata)
    end
  end

  defp maybe_log_queue_state_from_error(_entry, _), do: :ok

  defp do_sample_stream(entry, prompt, sampling_params, opts) do
    seq_id = next_seq_id(entry.request_id_counter)

    request = %{
      sampling_session_id: entry.sampling_session_id,
      seq_id: seq_id,
      prompt: prompt,
      sampling_params: sampling_params,
      num_samples: Keyword.get(opts, :num_samples, 1)
    }

    api_opts =
      opts
      |> Keyword.put(:config, entry.config)
      |> Keyword.put(:tinker_request_type, "StreamSample")
      |> Keyword.put(:tinker_request_iteration, seq_id)
      |> Keyword.put(
        :telemetry_metadata,
        merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata])
      )

    Sampling.sample_stream(request, api_opts)
  end
end
