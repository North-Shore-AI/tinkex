defmodule Tinkex.SamplingClient do
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

      [warning] Sampling is paused for session-123. Reason: concurrent LoRA rate limit hit

  Logs are debounced to once per 60 seconds per session to avoid spam.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver

  require Logger

  alias Tinkex.API.{Sampling, Service}
  alias Tinkex.QueueStateLogger

  alias Tinkex.{
    Error,
    Future,
    RateLimiter,
    PoolKey,
    Retry,
    RetryConfig,
    RetryHandler,
    RetrySemaphore,
    SamplingRegistry
  }

  alias Tinkex.Telemetry.Reporter
  alias Tinkex.Telemetry.Capture, as: TelemetryCapture
  require TelemetryCapture

  alias Tinkex.Types.{
    CreateSamplingSessionRequest,
    CreateSamplingSessionResponse,
    SampleRequest,
    SampleResponse,
    SamplingParams
  }

  @type t :: pid()
  @default_dispatch_concurrency 400

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
    config = Keyword.fetch!(opts, :config)
    session_id = Keyword.fetch!(opts, :session_id)
    sampling_client_id = Keyword.fetch!(opts, :sampling_client_id)
    base_model = Keyword.get(opts, :base_model)
    model_path = Keyword.get(opts, :model_path)
    sampling_session_id_override = Keyword.get(opts, :sampling_session_id)
    service_api = Keyword.get(opts, :service_api, Service)
    sampling_api = Keyword.get(opts, :sampling_api, Sampling)
    retry_config = build_retry_config(opts[:retry_config])

    telemetry_metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.new()
      |> Map.put_new(:session_id, session_id)

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
           ) do
      limiter = RateLimiter.for_key({config.base_url, config.api_key})
      request_counter = :atomics.new(1, signed: false)

      telemetry_metadata =
        opts
        |> Keyword.get(:telemetry_metadata, %{})
        |> Map.new()
        |> Map.put_new(:session_id, session_id)
        |> Map.put_new(:sampling_session_id, sampling_session_id)

      dispatch_semaphore = build_dispatch_semaphore(config, opts)

      entry = %{
        sampling_session_id: sampling_session_id,
        http_pool: config.http_pool,
        request_id_counter: request_counter,
        rate_limiter: limiter,
        dispatch_semaphore: dispatch_semaphore,
        config: config,
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
         dispatch_semaphore: dispatch_semaphore,
         config: config,
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
    Reporter.stop(state[:telemetry])
    :ok
  end

  @impl true
  def get_telemetry do
    :erlang.get({__MODULE__, :telemetry})
  end

  def get_telemetry(client) when is_pid(client) do
    GenServer.call(client, :get_telemetry)
  end

  defp telemetry_reporter_for(client) do
    try do
      get_telemetry(client)
    catch
      _, _ -> nil
    end
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

    # Look up the last logged timestamp from ETS registry
    # Use :persistent_term for debounce tracking keyed by session_id
    debounce_key = {:sampling_queue_state_debounce, session_id}

    last_logged =
      case :persistent_term.get(debounce_key, nil) do
        nil -> nil
        ts -> ts
      end

    new_timestamp = QueueStateLogger.maybe_log(queue_state, :sampling, session_id, last_logged)

    # Update the debounce timestamp if it changed
    if new_timestamp != last_logged do
      :persistent_term.put(debounce_key, new_timestamp)
    end

    :ok
  end

  defp do_sample(client, prompt, sampling_params, opts) do
    case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
      [{{:config, ^client}, entry}] ->
        with_dispatch(entry, fn ->
          if entry.retry_config.enable_retry_logic do
            do_sample_with_retry(entry, prompt, sampling_params, opts)
          else
            do_sample_once(entry, prompt, sampling_params, opts)
          end
        end)

      [] ->
        {:error, Error.new(:validation, "SamplingClient not initialized")}
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

  defp maybe_set_backoff(limiter, %Error{retry_after_ms: retry_after_ms}) do
    duration_ms =
      case retry_after_ms do
        value when is_integer(value) -> value
        _ -> 1_000
      end

    RateLimiter.set_backoff(limiter, duration_ms)
  end

  defp maybe_set_backoff(_limiter, _error), do: :ok

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

    poll_task =
      Future.poll(future,
        config: entry.config,
        timeout: Keyword.get(opts, :timeout, :infinity),
        http_timeout: Keyword.get(opts, :http_timeout, entry.config.timeout),
        telemetry_metadata: merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata]),
        queue_state_observer: observer,
        sleep_fun: opts[:sleep_fun],
        tinker_request_type: "Sample",
        tinker_request_iteration: seq_id
      )

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

  defp build_dispatch_semaphore(config, opts) do
    limit =
      opts
      |> Keyword.get(:dispatch_concurrency, @default_dispatch_concurrency)
      |> normalize_dispatch_limit()

    ensure_dispatch_semaphore_started()

    %{
      name:
        {:tinkex_sampling_dispatch, PoolKey.normalize_base_url(config.base_url), config.api_key,
         limit},
      limit: limit
    }
  end

  defp normalize_dispatch_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_dispatch_limit(_), do: @default_dispatch_concurrency

  defp with_dispatch(%{dispatch_semaphore: semaphore}, fun) do
    acquire_dispatch(semaphore.name, semaphore.limit)

    try do
      fun.()
    after
      Semaphore.release(semaphore.name)
    end
  end

  defp acquire_dispatch(name, limit) do
    case Semaphore.acquire(name, limit) do
      true ->
        :ok

      false ->
        Process.sleep(2)
        acquire_dispatch(name, limit)
    end
  end

  defp ensure_dispatch_semaphore_started do
    case Process.whereis(Semaphore) do
      nil ->
        {:ok, _pid} = Semaphore.start_link()
        :ok

      _pid ->
        :ok
    end
  end

  defp put_telemetry(nil), do: :ok
  defp put_telemetry(pid), do: :erlang.put({__MODULE__, :telemetry}, pid)

  defp build_retry_config(nil), do: RetryConfig.default()

  defp build_retry_config(%RetryConfig{} = config), do: config

  defp build_retry_config(opts) when is_list(opts), do: RetryConfig.new(opts)

  defp do_sample_with_retry(entry, prompt, sampling_params, opts) do
    handler = RetryHandler.from_config(entry.retry_config)

    execute = fn ->
      Retry.with_retry(
        fn -> do_sample_once(entry, prompt, sampling_params, opts) end,
        handler: handler,
        telemetry_metadata: entry.telemetry_metadata
      )
    end

    if entry.retry_config.max_connections > 0 do
      RetrySemaphore.with_semaphore(entry.retry_config.max_connections, execute)
    else
      execute.()
    end
  end

  defp do_sample_once(entry, prompt, sampling_params, opts) do
    RateLimiter.wait_for_backoff(entry.rate_limiter)
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
        RateLimiter.clear_backoff(entry.rate_limiter)
        handle_sample_response(resp, entry, seq_id, opts)

      {:error, %Error{status: 429} = error} ->
        maybe_set_backoff(entry.rate_limiter, error)
        {:error, error}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end
end
