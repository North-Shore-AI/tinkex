defmodule Tinkex.API do
  @moduledoc """
  High-level HTTP API client for Tinkex.

  Centralizes retry logic, telemetry, pool routing, and error categorization.
  Every function requires an explicit `Tinkex.Config` via `opts[:config]`.
  """

  @behaviour Tinkex.HTTPClient

  require Logger

  alias Tinkex.Error
  alias Tinkex.PoolKey

  alias Tinkex.API.{
    Compression,
    Headers,
    Request,
    ResponseHandler,
    Retry,
    StreamResponse,
    URL
  }

  alias Tinkex.Streaming.{ServerSentEvent, SSEDecoder}

  @telemetry_start [:tinkex, :http, :request, :start]
  @telemetry_stop [:tinkex, :http, :request, :stop]
  @telemetry_exception [:tinkex, :http, :request, :exception]

  @typep retry_result :: {{:ok, Finch.Response.t()} | {:error, term()}, non_neg_integer()}
  @typep response_result :: {:ok, Finch.Response.t()} | {:error, term()}

  @impl true
  @spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)

    query_params = URL.normalize_query_params(Keyword.get(opts, :query))
    url = URL.build_url(config.base_url, path, config.default_query, query_params)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = Headers.build(:post, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, pool_type)
    response_mode = Keyword.get(opts, :response)
    transform_opts = Keyword.get(opts, :transform, [])
    files = Keyword.get(opts, :files)

    metadata =
      %{
        method: :post,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_config_metadata(config)
      |> merge_telemetry_metadata(opts)

    with {:ok, prepared_headers, prepared_body} <-
           Request.prepare_body(body, headers, files, transform_opts),
         request <- Finch.build(:post, url, prepared_headers, prepared_body) do
      {result, retry_count, duration} =
        execute_with_telemetry(
          fn ->
            Retry.execute(request, pool_name, timeout, max_retries, config.dump_headers?)
          end,
          metadata
        )

      ResponseHandler.handle(result,
        method: :post,
        url: url,
        retries: retry_count,
        elapsed_native: duration,
        response: response_mode
      )
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         %Error{
           message: "Failed to prepare request: #{Request.format_error(reason)}",
           type: :validation,
           status: nil,
           category: :user,
           data: %{reason: reason}
         }}
    end
  end

  @impl true
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    query_params = URL.normalize_query_params(Keyword.get(opts, :query))
    url = URL.build_url(config.base_url, path, config.default_query, query_params)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = Headers.build(:get, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, pool_type)
    response_mode = Keyword.get(opts, :response)

    metadata =
      %{
        method: :get,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_config_metadata(config)
      |> merge_telemetry_metadata(opts)

    request = Finch.build(:get, url, headers)

    {result, retry_count, duration} =
      execute_with_telemetry(
        fn ->
          Retry.execute(request, pool_name, timeout, max_retries, config.dump_headers?)
        end,
        metadata
      )

    ResponseHandler.handle(result,
      method: :get,
      url: url,
      retries: retry_count,
      elapsed_native: duration,
      response: response_mode
    )
  end

  @impl true
  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(path, opts) do
    config = Keyword.fetch!(opts, :config)

    query_params = URL.normalize_query_params(Keyword.get(opts, :query))
    url = URL.build_url(config.base_url, path, config.default_query, query_params)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = Headers.build(:delete, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, pool_type)
    response_mode = Keyword.get(opts, :response)

    metadata =
      %{
        method: :delete,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_config_metadata(config)
      |> merge_telemetry_metadata(opts)

    request = Finch.build(:delete, url, headers)

    {result, retry_count, duration} =
      execute_with_telemetry(
        fn ->
          Retry.execute(request, pool_name, timeout, max_retries, config.dump_headers?)
        end,
        metadata
      )

    ResponseHandler.handle(result,
      method: :delete,
      url: url,
      retries: retry_count,
      elapsed_native: duration,
      response: response_mode
    )
  end

  @spec stream_get(String.t(), keyword()) ::
          {:ok, StreamResponse.t()} | {:error, Error.t()}
  def stream_get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    query_params = URL.normalize_query_params(Keyword.get(opts, :query))
    url = URL.build_url(config.base_url, path, config.default_query, query_params)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = Headers.build(:get, config, opts, timeout)
    parser = Keyword.get(opts, :event_parser, :json)
    pool_type = Keyword.get(opts, :pool_type, :default)
    pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, pool_type)

    request = Finch.build(:get, url, headers)

    case Finch.request(request, pool_name, receive_timeout: timeout) do
      {:ok, %Finch.Response{} = response} ->
        response = Compression.decompress(response)
        {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), response.body <> "\n\n")

        parsed_events =
          events
          |> Enum.map(&decode_event(&1, parser))
          |> Enum.reject(&(&1 in [nil, ""]))

        {:ok,
         %StreamResponse{
           stream: Stream.concat([parsed_events]),
           status: response.status,
           headers: Headers.to_map(response.headers),
           method: :get,
           url: url
         }}

      {:error, %Mint.HTTPError{} = error} ->
        {:error,
         %Error{
           message: Exception.message(error),
           type: :api_connection,
           status: nil,
           category: nil,
           data: %{exception: error}
         }}

      {:error, %Mint.TransportError{} = error} ->
        {:error,
         %Error{
           message: Exception.message(error),
           type: :api_connection,
           status: nil,
           category: nil,
           data: %{exception: error}
         }}

      {:error, reason} ->
        {:error,
         %Error{
           message: inspect(reason),
           type: :api_connection,
           status: nil,
           category: nil,
           data: %{exception: reason}
         }}
    end
  end

  @doc """
  Resolve the HTTP client module for a request based on options/config.
  """
  @spec client_module(keyword()) :: module()
  def client_module(opts) do
    cond do
      is_atom(opts[:http_client]) and not is_nil(opts[:http_client]) ->
        opts[:http_client]

      match?(%Tinkex.Config{http_client: client} when is_atom(client), Keyword.get(opts, :config)) ->
        Keyword.fetch!(opts, :config).http_client

      true ->
        __MODULE__
    end
  end

  # Private helper functions

  @spec execute_with_telemetry((-> retry_result), map()) ::
          {response_result, non_neg_integer(), integer()}
  defp execute_with_telemetry(fun, metadata) do
    start_native = System.monotonic_time()

    :telemetry.execute(@telemetry_start, %{system_time: System.system_time()}, metadata)

    try do
      {result, retry_count} = fun.()
      duration = System.monotonic_time() - start_native

      result_type =
        case result do
          {:ok, %Finch.Response{status: status}} when status in 200..299 -> :ok
          _ -> :error
        end

      :telemetry.execute(
        @telemetry_stop,
        %{duration: duration},
        metadata
        |> Map.put(:result, result_type)
        |> Map.put(:retry_count, retry_count)
      )

      {result, retry_count, duration}
    rescue
      exception ->
        duration = System.monotonic_time() - start_native

        :telemetry.execute(
          @telemetry_exception,
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: exception, stacktrace: __STACKTRACE__})
        )

        reraise exception, __STACKTRACE__
    end
  end

  defp merge_telemetry_metadata(metadata, opts) do
    case Keyword.get(opts, :telemetry_metadata) do
      meta when is_map(meta) -> Map.merge(metadata, meta)
      _ -> metadata
    end
  end

  defp merge_config_metadata(metadata, %Tinkex.Config{user_metadata: %{} = meta}) do
    Map.merge(metadata, meta)
  end

  defp merge_config_metadata(metadata, _config), do: metadata

  # SSE event decoding helpers
  defp decode_event(%ServerSentEvent{} = event, :raw), do: event

  defp decode_event(%ServerSentEvent{} = event, parser) when is_function(parser, 1),
    do: parser.(event)

  defp decode_event(%ServerSentEvent{} = event, _parser), do: ServerSentEvent.json(event)
end
