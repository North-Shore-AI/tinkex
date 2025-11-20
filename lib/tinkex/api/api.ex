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
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    metadata = %{
      method: :post,
      path: path,
      pool_type: pool_type,
      base_url: config.base_url
    }

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    pool_key = PoolKey.build(config.base_url, pool_type)

    {result, _retry_count} =
      execute_with_telemetry(
        &with_retries/5,
        [request, config.http_pool, timeout, pool_key, max_retries],
        metadata
      )

    handle_response(result)
  end

  @impl true
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    metadata = %{
      method: :get,
      path: path,
      pool_type: pool_type,
      base_url: config.base_url
    }

    request = Finch.build(:get, url, headers)

    pool_key = PoolKey.build(config.base_url, pool_type)

    {result, _retry_count} =
      execute_with_telemetry(
        &with_retries/5,
        [request, config.http_pool, timeout, pool_key, max_retries],
        metadata
      )

    handle_response(result)
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

      {result, retry_count}
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

  defp build_url(base_url, "/" <> _ = path), do: URI.merge(base_url, path) |> URI.to_string()

  defp build_url(base_url, path), do: URI.merge(base_url, "/" <> path) |> URI.to_string()

  defp build_headers(api_key, opts) do
    base_headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key}
    ]

    base_headers ++ Keyword.get(opts, :headers, [])
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok, data}

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

  defp handle_response({:ok, %Finch.Response{status: 429, headers: headers, body: body}}) do
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

  defp handle_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
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

  defp handle_response({:error, %Mint.TransportError{} = exception}) do
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

  defp handle_response({:error, %Mint.HTTPError{} = exception}) do
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

  defp handle_response({:error, exception}) do
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

  defp decode_error_body(body) do
    case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end
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

  @spec with_retries(Finch.Request.t(), atom(), timeout(), term(), non_neg_integer()) ::
          {{:ok, Finch.Response.t()} | {:error, term()}, non_neg_integer()}
  defp with_retries(request, pool, timeout, pool_key, max_retries) do
    start_time = System.monotonic_time(:millisecond)
    do_retry(request, pool, timeout, pool_key, max_retries, 0, start_time)
  end

  defp do_retry(request, pool, timeout, pool_key, max_retries, attempt, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= @max_retry_duration_ms do
      Logger.warning("Retry timeout exceeded after #{elapsed}ms")

      error =
        {:error,
         %Error{
           message: "Retry timeout exceeded (#{@max_retry_duration_ms}ms)",
           type: :api_connection,
           data: %{elapsed_ms: elapsed, attempts: attempt}
         }}

      {error, attempt}
    else
      case Finch.request(request, pool, receive_timeout: timeout, pool: pool_key) do
        {:ok, %Finch.Response{status: status, headers: headers}} = response ->
          decision =
            if attempt >= max_retries do
              :no_retry
            else
              case normalized_header(headers, "x-should-retry") do
                "false" ->
                  :no_retry

                "true" ->
                  {:retry, retry_delay(attempt)}

                _ ->
                  cond do
                    status == 429 ->
                      {:retry, parse_retry_after(headers)}

                    status == 408 ->
                      {:retry, retry_delay(attempt)}

                    status in 500..599 ->
                      {:retry, retry_delay(attempt)}

                    true ->
                      :no_retry
                  end
              end
            end

          case decision do
            {:retry, delay_ms} ->
              Logger.debug(
                "Retrying request (attempt #{attempt + 1}/#{max_retries}) status=#{status} delay=#{delay_ms}ms"
              )

              Process.sleep(delay_ms)
              do_retry(request, pool, timeout, pool_key, max_retries, attempt + 1, start_time)

            :no_retry ->
              {response, attempt}
          end

        {:error, %Mint.TransportError{reason: reason}} = error ->
          handle_retryable_error(
            error,
            reason,
            request,
            pool,
            timeout,
            pool_key,
            max_retries,
            attempt,
            start_time
          )

        {:error, %Mint.HTTPError{reason: reason}} = error ->
          handle_retryable_error(
            error,
            reason,
            request,
            pool,
            timeout,
            pool_key,
            max_retries,
            attempt,
            start_time
          )

        other ->
          {other, attempt}
      end
    end
  end

  defp handle_retryable_error(
         error,
         reason,
         request,
         pool,
         timeout,
         pool_key,
         max_retries,
         attempt,
         start_time
       ) do
    if attempt < max_retries do
      delay = retry_delay(attempt)
      Logger.debug("Retrying after #{inspect(reason)} delay=#{delay}ms")
      Process.sleep(delay)
      do_retry(request, pool, timeout, pool_key, max_retries, attempt + 1, start_time)
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
    case normalized_header(headers, "retry-after-ms") do
      nil ->
        case normalized_header(headers, "retry-after") do
          nil ->
            1_000

          value ->
            case Integer.parse(value) do
              {seconds, _} ->
                seconds * 1_000

              :error ->
                Logger.warning("Unsupported Retry-After format: #{value}. Using default 1s.")
                1_000
            end
        end

      value ->
        case Integer.parse(value) do
          {ms, _} -> ms
          :error -> 1_000
        end
    end
  end

  defp normalized_header(headers, name) do
    name_lower = String.downcase(name)

    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(k) == name_lower, do: String.downcase(String.trim(v))
    end)
  end
end
