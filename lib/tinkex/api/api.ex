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
  alias Tinkex.Transform
  alias Tinkex.Env
  alias Tinkex.API.Response
  alias Tinkex.API.StreamResponse
  alias Tinkex.Streaming.{SSEDecoder, ServerSentEvent}
  alias Tinkex.Types.RequestErrorCategory

  @initial_retry_delay 500
  @max_retry_delay 8_000
  @max_retry_duration_ms 30_000

  @telemetry_start [:tinkex, :http, :request, :start]
  @telemetry_stop [:tinkex, :http, :request, :stop]
  @telemetry_exception [:tinkex, :http, :request, :exception]

  @impl true
  @spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = build_headers(:post, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    response_mode = Keyword.get(opts, :response)
    transform_opts = Keyword.get(opts, :transform, [])

    metadata =
      %{
        method: :post,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_telemetry_metadata(opts)

    request = Finch.build(:post, url, headers, prepare_body(body, transform_opts))

    pool_key = PoolKey.build(config.base_url, pool_type)

    {result, retry_count, duration} =
      execute_with_telemetry(
        &with_retries/6,
        [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
        metadata
      )

    handle_response(result,
      method: :post,
      url: url,
      retries: retry_count,
      elapsed_native: duration,
      response: response_mode
    )
  end

  @impl true
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = build_headers(:get, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    response_mode = Keyword.get(opts, :response)

    metadata =
      %{
        method: :get,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_telemetry_metadata(opts)

    request = Finch.build(:get, url, headers)

    pool_key = PoolKey.build(config.base_url, pool_type)

    {result, retry_count, duration} =
      execute_with_telemetry(
        &with_retries/6,
        [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
        metadata
      )

    handle_response(result,
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

    url = build_url(config.base_url, path)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = build_headers(:delete, config, opts, timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)
    response_mode = Keyword.get(opts, :response)

    metadata =
      %{
        method: :delete,
        path: path,
        pool_type: pool_type,
        base_url: config.base_url
      }
      |> merge_telemetry_metadata(opts)

    request = Finch.build(:delete, url, headers)

    pool_key = PoolKey.build(config.base_url, pool_type)

    {result, retry_count, duration} =
      execute_with_telemetry(
        &with_retries/6,
        [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
        metadata
      )

    handle_response(result,
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

    url = build_url(config.base_url, path)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = build_headers(:get, config, opts, timeout)
    parser = Keyword.get(opts, :event_parser, :json)

    request = Finch.build(:get, url, headers)

    case Finch.request(request, config.http_pool, receive_timeout: timeout) do
      {:ok, %Finch.Response{} = response} ->
        response = maybe_decompress(response)
        {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), response.body <> "\n\n")

        parsed_events =
          events
          |> Enum.map(&decode_event(&1, parser))
          |> Enum.reject(&(&1 in [nil, ""]))

        {:ok,
         %StreamResponse{
           stream: Stream.concat([parsed_events]),
           status: response.status,
           headers: headers_to_map(response.headers),
           method: :get,
           url: url
         }}

      {:error, %Mint.HTTPError{} = error} ->
        {:error,
         build_error(Exception.message(error), :api_connection, nil, nil, %{exception: error})}

      {:error, %Mint.TransportError{} = error} ->
        {:error,
         build_error(Exception.message(error), :api_connection, nil, nil, %{exception: error})}

      {:error, reason} ->
        {:error, build_error(inspect(reason), :api_connection, nil, nil, %{exception: reason})}
    end
  end

  defp execute_with_telemetry(fun, args, metadata) do
    start_native = System.monotonic_time()

    :telemetry.execute(@telemetry_start, %{system_time: System.system_time()}, metadata)

    try do
      {result, retry_count} = apply(fun, args)
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

  defp build_url(base_url, path) do
    base = URI.parse(base_url)
    base_path = base.path || "/"

    {relative_path, query} =
      case String.split(path, "?", parts: 2) do
        [p, q] -> {p, q}
        [p] -> {p, nil}
      end

    merged_path =
      relative_path
      |> String.trim_leading("/")
      |> then(fn trimmed -> Path.join(base_path, trimmed) end)

    uri = %{base | path: merged_path}
    uri = if query, do: %{uri | query: query}, else: uri

    URI.to_string(uri)
  end

  defp build_headers(method, config, opts, timeout_ms) do
    [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", user_agent()},
      {"connection", "keep-alive"},
      {"accept-encoding", "gzip"},
      {"x-api-key", config.api_key}
    ]
    |> Kernel.++(stainless_headers(timeout_ms))
    |> Kernel.++(cloudflare_headers(config))
    |> Kernel.++(request_headers(opts))
    |> Kernel.++(idempotency_headers(method, opts))
    |> Kernel.++(sampling_headers(opts))
    |> Kernel.++(maybe_raw_response_header(opts))
    |> Kernel.++(Keyword.get(opts, :headers, []))
    |> dedupe_headers()
  end

  defp prepare_body(body, _transform_opts) when is_binary(body), do: body

  defp prepare_body(body, transform_opts) do
    body
    |> Transform.transform(transform_opts)
    |> Jason.encode!()
  end

  defp handle_response({:ok, %Finch.Response{} = response}, opts) do
    response = maybe_decompress(response)
    do_handle_response(response, opts)
  end

  defp handle_response({:error, %Mint.TransportError{} = exception}, _opts) do
    Logger.debug("Transport error: #{Exception.message(exception)}")

    {:error,
     build_error(
       Exception.message(exception),
       :api_connection,
       nil,
       nil,
       %{exception: exception}
     )}
  end

  defp handle_response({:error, %Mint.HTTPError{} = exception}, _opts) do
    Logger.debug("HTTP error: #{Exception.message(exception)}")

    {:error,
     build_error(
       Exception.message(exception),
       :api_connection,
       nil,
       nil,
       %{exception: exception}
     )}
  end

  defp handle_response({:error, exception}, _opts) do
    message =
      cond do
        is_struct(exception) and function_exported?(exception.__struct__, :message, 1) ->
          Exception.message(exception)

        is_atom(exception) ->
          Atom.to_string(exception)

        is_binary(exception) ->
          exception

        true ->
          inspect(exception)
      end

    Logger.debug("Request error: #{message}")

    {:error, build_error(message, :api_connection, nil, nil, %{exception: exception})}
  end

  defp do_handle_response(%Finch.Response{status: status, headers: headers} = response, opts)
       when status in [301, 302, 307, 308] do
    case find_header_value(headers, "location") do
      nil ->
        {:error,
         build_error(
           "Redirect without Location header",
           :api_status,
           status,
           :server,
           %{body: response.body}
         )}

      location ->
        expires = find_header_value(headers, "expires")
        payload = %{"url" => location, "status" => status, "expires" => expires}
        wrap_success(payload, response, opts)
    end
  end

  defp do_handle_response(%Finch.Response{status: status, body: body} = response, opts)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, data} ->
        wrap_success(data, response, opts)

      {:error, reason} ->
        {:error,
         build_error(
           "JSON decode error: #{inspect(reason)}",
           :validation,
           nil,
           :user,
           %{body: body}
         )}
    end
  end

  defp do_handle_response(%Finch.Response{status: 429, headers: headers, body: body}, _opts) do
    error_data = decode_error_body(body)
    retry_after_ms = parse_retry_after(headers)

    {:error,
     build_error(
       error_data["message"] || "Rate limited",
       :api_status,
       429,
       :server,
       error_data,
       retry_after_ms
     )}
  end

  defp do_handle_response(%Finch.Response{status: status, headers: headers, body: body}, _opts) do
    error_data = decode_error_body(body)

    category =
      case error_data["category"] do
        cat when is_binary(cat) ->
          RequestErrorCategory.parse(cat)

        _ when status in 400..499 ->
          :user

        _ when status in 500..599 ->
          :server

        _ ->
          :unknown
      end

    retry_after_ms = parse_retry_after(headers)

    {:error,
     build_error(
       error_data["message"] || error_data["error"] || "HTTP #{status}",
       :api_status,
       status,
       category,
       error_data,
       retry_after_ms
     )}
  end

  defp decode_error_body(body) do
    case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end
  end

  defp find_header_value(headers, target) do
    target = String.downcase(target)

    Enum.find_value(headers, fn
      {k, v} ->
        if String.downcase(k) == target, do: v, else: nil

      _ ->
        nil
    end)
  end

  defp headers_to_map(headers) do
    Enum.reduce(headers || [], %{}, fn
      {k, v}, acc -> Map.put(acc, String.downcase(k), v)
      _, acc -> acc
    end)
  end

  defp build_error(message, type, status, category, data, retry_after_ms \\ nil) do
    %Error{
      message: message,
      type: type,
      status: status,
      category: category,
      data: data,
      retry_after_ms: retry_after_ms
    }
  end

  @spec with_retries(Finch.Request.t(), atom(), timeout(), term(), non_neg_integer(), boolean()) ::
          {{:ok, Finch.Response.t()} | {:error, term()}, non_neg_integer()}
  defp with_retries(request, pool, timeout, _pool_key, max_retries, dump_headers?) do
    start_time = System.monotonic_time(:millisecond)

    context = %{
      request: request,
      pool: pool,
      timeout: timeout,
      max_retries: max_retries,
      start_time: start_time,
      dump_headers?: dump_headers?
    }

    do_retry(context, 0)
  end

  defp do_retry(context, attempt) do
    elapsed_ms = elapsed_since(context.start_time)

    case retry_timeout_result(elapsed_ms, attempt) do
      {:halt, result} -> result
      :continue -> perform_request(context, attempt)
    end
  end

  defp perform_request(context, attempt) do
    request = put_retry_headers(context.request, attempt, context.timeout)
    maybe_dump_request(request, attempt, context.dump_headers?)

    case Finch.request(request, context.pool, receive_timeout: context.timeout) do
      {:ok, %Finch.Response{} = response} = response_tuple ->
        handle_success(response_tuple, response, context, attempt)

      {:error, %Mint.TransportError{reason: reason}} = error ->
        handle_retryable_error(error, reason, context, attempt)

      {:error, %Mint.HTTPError{reason: reason}} = error ->
        handle_retryable_error(error, reason, context, attempt)

      other ->
        {other, attempt}
    end
  end

  defp handle_success(
         response_tuple,
         %Finch.Response{status: status, headers: headers},
         context,
         attempt
       ) do
    case retry_decision(status, headers, context.max_retries, attempt) do
      {:retry, delay_ms} ->
        Logger.debug(
          "Retrying request (attempt #{attempt + 1}/#{context.max_retries}) status=#{status} delay=#{delay_ms}ms"
        )

        Process.sleep(delay_ms)
        do_retry(context, attempt + 1)

      :no_retry ->
        {response_tuple, attempt}
    end
  end

  defp retry_decision(_status, _headers, max_retries, attempt) when attempt >= max_retries,
    do: :no_retry

  defp retry_decision(status, headers, _max_retries, attempt) do
    case normalized_header(headers, "x-should-retry") do
      "false" ->
        :no_retry

      "true" ->
        {:retry, retry_delay(attempt)}

      _ ->
        status_based_decision(status, headers, attempt)
    end
  end

  defp status_based_decision(429, headers, _attempt),
    do: {:retry, parse_retry_after(headers)}

  defp status_based_decision(408, _headers, attempt),
    do: {:retry, retry_delay(attempt)}

  defp status_based_decision(status, _headers, attempt) when status in 500..599,
    do: {:retry, retry_delay(attempt)}

  defp status_based_decision(_status, _headers, _attempt), do: :no_retry

  defp handle_retryable_error(error, reason, context, attempt) do
    if attempt < context.max_retries do
      delay = retry_delay(attempt)
      Logger.debug("Retrying after #{inspect(reason)} delay=#{delay}ms")
      Process.sleep(delay)
      do_retry(context, attempt + 1)
    else
      {error, attempt}
    end
  end

  defp retry_delay(attempt) do
    base_delay = @initial_retry_delay * :math.pow(2, attempt)
    delay = min(base_delay * :rand.uniform(), @max_retry_delay)
    round(delay)
  end

  defp parse_retry_after(headers) do
    parse_retry_after_ms(headers) || parse_retry_after_seconds(headers) || 1_000
  end

  defp normalized_header(headers, name) do
    name_lower = String.downcase(name)

    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(k) == name_lower, do: String.downcase(String.trim(v))
    end)
  end

  defp parse_retry_after_ms(headers) do
    headers
    |> normalized_header("retry-after-ms")
    |> parse_integer(:ms, log: false)
  end

  defp parse_retry_after_seconds(headers) do
    headers
    |> normalized_header("retry-after")
    |> parse_integer(:seconds, log: true)
  end

  defp decode_event(%ServerSentEvent{} = event, :raw), do: event

  defp decode_event(%ServerSentEvent{} = event, parser) when is_function(parser, 1),
    do: parser.(event)

  defp decode_event(%ServerSentEvent{} = event, _parser), do: ServerSentEvent.json(event)

  defp put_retry_headers(%Finch.Request{} = request, attempt, timeout_ms) do
    headers =
      request.headers
      |> put_header("x-stainless-retry-count", Integer.to_string(attempt))
      |> ensure_read_timeout(timeout_ms)

    %{request | headers: headers}
  end

  defp ensure_read_timeout(headers, timeout_ms) do
    case normalized_header(headers, "x-stainless-read-timeout") do
      nil -> put_header(headers, "x-stainless-read-timeout", stainless_read_timeout(timeout_ms))
      _ -> headers
    end
  end

  defp maybe_dump_request(%Finch.Request{} = request, attempt, dump_headers?) do
    if dump_headers? do
      url = request_url(request)
      headers = redact_headers(request.headers)
      body = dump_body(request.body)

      Logger.info(
        "HTTP #{String.upcase(to_string(request.method))} #{url} attempt=#{attempt} headers=#{inspect(headers)} body=#{body}"
      )
    end
  end

  defp request_url(%Finch.Request{} = request) do
    scheme = request.scheme |> to_string()
    port = request.port
    default_port? = (scheme == "https" and port == 443) or (scheme == "http" and port == 80)
    port_segment = if default_port?, do: "", else: ":#{port}"
    query_segment = if request.query in [nil, ""], do: "", else: "?#{request.query}"

    "#{scheme}://#{request.host}#{port_segment}#{request.path}#{query_segment}"
  end

  defp redact_headers(headers) do
    Enum.map(headers, fn
      {name, value} ->
        lowered = String.downcase(name)

        cond do
          lowered == "x-api-key" -> {name, Env.mask_secret(value)}
          lowered == "cf-access-client-secret" -> {name, Env.mask_secret(value)}
          true -> {name, value}
        end

      other ->
        other
    end)
  end

  defp dump_body(nil), do: "nil"

  defp dump_body(body) do
    try do
      IO.iodata_to_binary(body)
    rescue
      _ -> inspect(body)
    end
  end

  defp dedupe_headers(headers) do
    headers
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, String.downcase(k), {k, v})
    end)
    |> Map.values()
  end

  defp put_header(headers, name, value) do
    name_downcase = String.downcase(name)

    headers
    |> Enum.reject(fn {k, _} -> String.downcase(k) == name_downcase end)
    |> List.insert_at(-1, {name, value})
  end

  defp request_headers(opts) do
    []
    |> maybe_put("x-tinker-request-iteration", opts[:tinker_request_iteration])
    |> maybe_put("x-tinker-request-type", opts[:tinker_request_type])
    |> maybe_put_roundtrip(opts[:tinker_create_roundtrip_time])
  end

  defp cloudflare_headers(%{cf_access_client_id: id, cf_access_client_secret: secret}) do
    []
    |> maybe_put("CF-Access-Client-Id", id)
    |> maybe_put("CF-Access-Client-Secret", secret)
  end

  defp maybe_put(headers, _name, nil), do: headers
  defp maybe_put(headers, name, value), do: [{name, to_string(value)} | headers]

  defp maybe_put_roundtrip(headers, nil), do: headers

  defp maybe_put_roundtrip(headers, value) do
    [{"x-tinker-create-promise-roundtrip-time", to_string(value)} | headers]
  end

  defp idempotency_headers(:get, _opts), do: []

  defp idempotency_headers(_method, opts) do
    key =
      case opts[:idempotency_key] do
        nil -> build_idempotency_key()
        :omit -> nil
        value -> to_string(value)
      end

    if key, do: [{"x-idempotency-key", key}], else: []
  end

  defp sampling_headers(opts) do
    if Keyword.get(opts, :sampling_backpressure, false) do
      [{"x-tinker-sampling-backpressure", "1"}]
    else
      []
    end
  end

  defp maybe_raw_response_header(opts) do
    if Keyword.get(opts, :raw_response?, false) do
      [{"x-stainless-raw-response", "raw"}]
    else
      []
    end
  end

  defp stainless_headers(timeout_ms) do
    [
      {"x-stainless-package-version", sdk_version()},
      {"x-stainless-os", stainless_os()},
      {"x-stainless-arch", stainless_arch()},
      {"x-stainless-runtime", stainless_runtime()},
      {"x-stainless-runtime-version", stainless_runtime_version()},
      {"x-stainless-read-timeout", stainless_read_timeout(timeout_ms)}
    ]
  end

  defp stainless_read_timeout(timeout_ms) when is_integer(timeout_ms) do
    timeout_ms
    |> Kernel./(1000)
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp stainless_os do
    case :os.type() do
      {:unix, :darwin} -> "MacOS"
      {:unix, :linux} -> "Linux"
      {:unix, :freebsd} -> "FreeBSD"
      {:unix, :openbsd} -> "OpenBSD"
      {:win32, _} -> "Windows"
      _ -> "Unknown"
    end
  end

  defp stainless_arch do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.downcase()

    cond do
      String.contains?(arch, "aarch64") -> "arm64"
      String.contains?(arch, "arm") -> "arm"
      String.contains?(arch, "x86_64") or String.contains?(arch, "amd64") -> "x64"
      String.contains?(arch, "i686") or String.contains?(arch, "i386") -> "x32"
      true -> "unknown"
    end
  end

  defp stainless_runtime, do: "BEAM"

  defp stainless_runtime_version do
    otp = :erlang.system_info(:otp_release) |> to_string()
    "#{System.version()} (OTP #{otp})"
  end

  defp sdk_version do
    Tinkex.Version.current()
  end

  defp user_agent do
    Application.get_env(:tinkex, :user_agent, "AsyncTinkex/Elixir #{sdk_version()}")
  end

  defp build_idempotency_key do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp parse_integer(nil, _unit, _opts), do: nil

  defp parse_integer(value, unit, opts) do
    case Integer.parse(value) do
      {number, _} ->
        convert_retry_after(number, unit)

      :error ->
        log_invalid_retry_after?(value, opts)
        nil
    end
  end

  defp log_invalid_retry_after?(_value, log: false), do: :ok

  defp log_invalid_retry_after?(value, log: true) do
    Logger.warning("Unsupported Retry-After format: #{value}. Using default 1s.")
  end

  defp convert_retry_after(value, :ms), do: value
  defp convert_retry_after(value, :seconds), do: value * 1_000

  defp elapsed_since(start_time), do: System.monotonic_time(:millisecond) - start_time

  defp maybe_decompress(%Finch.Response{} = response) do
    case normalized_header(response.headers, "content-encoding") do
      "gzip" ->
        body =
          try do
            :zlib.gunzip(response.body)
          rescue
            _ ->
              response.body
          end

        %{response | body: body, headers: strip_content_encoding(response.headers)}

      _ ->
        response
    end
  end

  defp strip_content_encoding(headers) do
    Enum.reject(headers, fn {name, _} -> String.downcase(name) == "content-encoding" end)
  end

  defp retry_timeout_result(elapsed_ms, attempt) do
    if elapsed_ms >= @max_retry_duration_ms do
      Logger.warning("Retry timeout exceeded after #{elapsed_ms}ms")

      error =
        {:error,
         %Error{
           message: "Retry timeout exceeded (#{@max_retry_duration_ms}ms)",
           type: :api_connection,
           data: %{elapsed_ms: elapsed_ms, attempts: attempt}
         }}

      {:halt, {error, attempt}}
    else
      :continue
    end
  end

  defp merge_telemetry_metadata(metadata, opts) do
    case Keyword.get(opts, :telemetry_metadata) do
      meta when is_map(meta) -> Map.merge(metadata, meta)
      _ -> metadata
    end
  end

  defp wrap_success(data, %Finch.Response{} = response, opts) do
    case Keyword.get(opts, :response) do
      :wrapped ->
        {:ok,
         Response.new(response,
           method: Keyword.get(opts, :method),
           url: Keyword.get(opts, :url),
           retries: Keyword.get(opts, :retries, 0),
           elapsed_ms: convert_elapsed(opts[:elapsed_native]),
           data: data
         )}

      _ ->
        {:ok, data}
    end
  end

  defp convert_elapsed(nil), do: 0

  defp convert_elapsed(native_duration) when is_integer(native_duration) do
    System.convert_time_unit(native_duration, :native, :millisecond)
  end
end
