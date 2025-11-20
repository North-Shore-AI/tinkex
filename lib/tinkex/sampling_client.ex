defmodule Tinkex.SamplingClient do
  @moduledoc """
  Sampling client that performs lock-free reads via ETS.

  Init runs in a GenServer to create the sampling session and register state in
  `Tinkex.SamplingRegistry`. Once initialized, `sample/4` reads configuration
  directly from ETS without touching the GenServer, avoiding bottlenecks under
  high load.
  """

  use GenServer

  alias Tinkex.API.{Sampling, Service}
  alias Tinkex.Error
  alias Tinkex.RateLimiter
  alias Tinkex.SamplingRegistry

  alias Tinkex.Types.{
    CreateSamplingSessionRequest,
    CreateSamplingSessionResponse,
    SampleRequest,
    SampleResponse
  }

  @type t :: pid()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Submit a sampling request.

  Returns a `Task.t()` that yields `{:ok, %SampleResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec sample(t(), map(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def sample(client, prompt, sampling_params, opts \\ []) do
    {:ok, Task.async(fn -> do_sample(client, prompt, sampling_params, opts) end)}
  end

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    session_id = Keyword.fetch!(opts, :session_id)
    sampling_client_id = Keyword.fetch!(opts, :sampling_client_id)
    base_model = Keyword.get(opts, :base_model)
    model_path = Keyword.get(opts, :model_path)
    service_api = Keyword.get(opts, :service_api, Service)
    sampling_api = Keyword.get(opts, :sampling_api, Sampling)

    with {:ok, sampling_session_id} <-
           create_sampling_session(
             session_id,
             sampling_client_id,
             base_model,
             model_path,
             config,
             service_api
           ) do
      limiter = RateLimiter.for_key({config.base_url, config.api_key})
      request_counter = :atomics.new(1, signed: false)

      entry = %{
        sampling_session_id: sampling_session_id,
        http_pool: config.http_pool,
        request_id_counter: request_counter,
        rate_limiter: limiter,
        config: config,
        sampling_api: sampling_api
      }

      :ok = SamplingRegistry.register(self(), entry)

      {:ok,
       %{
         sampling_session_id: sampling_session_id,
         request_id_counter: request_counter,
         rate_limiter: limiter,
         config: config,
         sampling_api: sampling_api
       }}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  defp do_sample(client, prompt, sampling_params, opts) do
    case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
      [{{:config, ^client}, entry}] ->
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

        api_opts = Keyword.put(opts, :config, entry.config)

        case entry.sampling_api.sample_async(request, api_opts) do
          {:ok, resp} ->
            RateLimiter.clear_backoff(entry.rate_limiter)
            {:ok, SampleResponse.from_json(resp)}

          {:error, %Error{status: 429} = error} ->
            maybe_set_backoff(entry.rate_limiter, error)
            {:error, error}

          {:error, %Error{} = error} ->
            {:error, error}
        end

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
         service_api
       ) do
    request = %CreateSamplingSessionRequest{
      session_id: session_id,
      sampling_session_seq_id: sampling_client_id,
      base_model: base_model,
      model_path: model_path
    }

    case service_api.create_sampling_session(request, config: config) do
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

  defp next_seq_id(counter) do
    :atomics.add_get(counter, 1, 1) - 1
  end

  defp maybe_set_backoff(limiter, %Error{retry_after_ms: retry_after_ms})
       when is_integer(retry_after_ms) do
    RateLimiter.set_backoff(limiter, retry_after_ms)
  end

  defp maybe_set_backoff(_limiter, _error), do: :ok
end
