defmodule Tinkex.Context do
  @moduledoc """
  Build Pristine contexts with Tinkex defaults.
  """

  alias Pristine.Adapters.CircuitBreaker.Foundation, as: CircuitBreaker
  alias Pristine.Adapters.Future.Polling, as: Future
  alias Pristine.Adapters.PoolManager
  alias Pristine.Adapters.RateLimit.BackoffWindow, as: RateLimiter
  alias Pristine.Adapters.Retry.Foundation, as: Retry
  alias Pristine.Adapters.Semaphore.Counting, as: Semaphore
  alias Pristine.Adapters.Serializer.JSON, as: Serializer
  alias Pristine.Adapters.Streaming.SSE, as: Streaming
  alias Pristine.Adapters.Telemetry.Raw, as: Telemetry
  alias Pristine.Adapters.Transport.Finch, as: Transport
  alias Pristine.Adapters.Transport.FinchStream, as: StreamTransport
  alias Pristine.Core.Context, as: PristineContext

  alias Tinkex.API.Response
  alias Tinkex.{Config, Env, Manifest, Version}
  alias Tinkex.Telemetry.Otel

  @type t :: PristineContext.t()

  @spec new(Config.t(), keyword()) :: t()
  def new(%Config{} = config, opts \\ []) do
    manifest = Manifest.load!()

    PristineContext.new(
      config: config,
      base_url: config.base_url,
      pool_base: config.http_pool,
      headers: base_headers(config),
      default_query: config.default_query,
      default_timeout: config.timeout,
      transport: Keyword.get(opts, :transport, Transport),
      stream_transport: Keyword.get(opts, :stream_transport, StreamTransport),
      retry: Keyword.get(opts, :retry, Retry),
      retry_opts: Keyword.get(opts, :retry_opts, max_retries: config.max_retries),
      retry_policies: Map.get(manifest, :retry_policies, %{}),
      circuit_breaker: Keyword.get(opts, :circuit_breaker, CircuitBreaker),
      rate_limiter: Keyword.get(opts, :rate_limiter, RateLimiter),
      semaphore: Keyword.get(opts, :semaphore, Semaphore),
      serializer: Keyword.get(opts, :serializer, Serializer),
      streaming: Keyword.get(opts, :streaming, Streaming),
      telemetry: Keyword.get(opts, :telemetry, Telemetry),
      telemetry_events: telemetry_events(),
      telemetry_metadata: config.user_metadata || %{},
      pool_manager: Keyword.get(opts, :pool_manager, PoolManager),
      future: Keyword.get(opts, :future, Future),
      package_version: Version.tinker_sdk(),
      error_module: Tinkex.Error,
      response_wrapper: Response,
      dump_headers?: config.dump_headers?,
      redact_headers: &redact_headers/1,
      extra_headers: &extra_headers/3
    )
  end

  defp base_headers(%Config{} = config) do
    %{
      "accept" => "application/json",
      "user-agent" => user_agent(),
      "connection" => "keep-alive",
      "accept-encoding" => "gzip",
      "x-api-key" => config.api_key
    }
    |> Map.merge(normalize_default_headers(config.default_headers))
  end

  defp normalize_default_headers(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_default_headers(_), do: %{}

  defp telemetry_events do
    %{
      request_start: [:tinkex, :http, :request, :start],
      request_stop: [:tinkex, :http, :request, :stop],
      request_exception: [:tinkex, :http, :request, :exception],
      stream_start: [:tinkex, :http, :stream, :start],
      stream_connected: [:tinkex, :http, :stream, :connected],
      stream_error: [:tinkex, :http, :stream, :error]
    }
  end

  defp extra_headers(endpoint, %PristineContext{config: %Config{} = config} = context, opts) do
    timeout_ms = Keyword.get(opts, :timeout) || context.default_timeout || endpoint.timeout

    headers =
      %{}
      |> maybe_put("x-stainless-read-timeout", stainless_read_timeout(timeout_ms))
      |> maybe_put("x-tinker-request-iteration", opts[:tinker_request_iteration])
      |> maybe_put("x-tinker-request-type", opts[:tinker_request_type])
      |> maybe_put_roundtrip(opts[:tinker_create_roundtrip_time])
      |> maybe_put("x-tinker-sampling-backpressure", sampling_backpressure(opts))
      |> maybe_put("x-stainless-raw-response", raw_response_header(opts))
      |> maybe_put("CF-Access-Client-Id", cf_access_client_id(config, opts))
      |> maybe_put("CF-Access-Client-Secret", cf_access_client_secret(config, opts))

    inject_otel_headers(headers, config)
  end

  defp extra_headers(_endpoint, _context, _opts), do: %{}

  defp sampling_backpressure(opts) do
    if Keyword.get(opts, :sampling_backpressure, false), do: "1"
  end

  defp raw_response_header(opts) do
    if Keyword.get(opts, :raw_response?, false), do: "raw"
  end

  defp cf_access_client_id(config, opts) do
    Keyword.get(opts, :cf_access_client_id, config.cf_access_client_id)
  end

  defp cf_access_client_secret(config, opts) do
    Keyword.get(opts, :cf_access_client_secret, config.cf_access_client_secret)
  end

  defp inject_otel_headers(headers, %Config{} = config) do
    if Otel.enabled?(config) do
      headers
      |> Map.to_list()
      |> Otel.inject_headers(config)
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        Map.put(acc, to_string(key), value)
      end)
    else
      headers
    end
  end

  defp maybe_put(headers, _key, nil), do: headers
  defp maybe_put(headers, key, value), do: Map.put(headers, key, to_string(value))

  defp maybe_put_roundtrip(headers, nil), do: headers

  defp maybe_put_roundtrip(headers, value) do
    Map.put(headers, "x-tinker-create-promise-roundtrip-time", to_string(value))
  end

  defp user_agent do
    Application.get_env(:tinkex, :user_agent, "AsyncTinkex/Elixir #{Version.tinker_sdk()}")
  end

  defp stainless_read_timeout(nil), do: nil

  defp stainless_read_timeout(timeout_ms) when is_integer(timeout_ms) do
    timeout_ms
    |> Kernel./(1000)
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp redact_headers(headers) do
    Enum.map(headers, fn
      {name, value} ->
        lowered = String.downcase(to_string(name))

        cond do
          lowered == "x-api-key" -> {name, Env.mask_secret(to_string(value))}
          lowered == "cf-access-client-secret" -> {name, Env.mask_secret(to_string(value))}
          lowered == "authorization" -> {name, Env.mask_secret(to_string(value))}
          lowered == "proxy-authorization" -> {name, Env.mask_secret(to_string(value))}
          true -> {name, value}
        end

      other ->
        other
    end)
  end
end
