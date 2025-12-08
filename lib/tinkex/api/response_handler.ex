defmodule Tinkex.API.ResponseHandler do
  @moduledoc """
  HTTP response handling and error parsing for Tinkex API.

  Handles:
  - Status code-based response processing
  - JSON decoding
  - Error categorization
  - Response wrapping for different modes
  - Retry-After header parsing
  """

  require Logger

  alias Tinkex.Error
  alias Tinkex.API.{Response, Compression, Headers}
  alias Tinkex.Types.RequestErrorCategory

  @doc """
  Handles a Finch response or error, returning standardized result.

  Supports different response modes via opts[:response]:
  - nil or :raw: Returns decoded JSON data
  - :wrapped: Returns `Tinkex.API.Response` struct with metadata

  ## Options

  - `:response` - Response mode (:wrapped or nil)
  - `:method` - HTTP method (for response metadata)
  - `:url` - Request URL (for response metadata)
  - `:retries` - Number of retries performed
  - `:elapsed_native` - Request duration in native time units
  """
  @spec handle(
          {:ok, Finch.Response.t()} | {:error, term()},
          keyword()
        ) :: {:ok, map() | Response.t()} | {:error, Error.t()}
  def handle({:ok, %Finch.Response{} = response}, opts) do
    response = Compression.decompress(response)
    handle_by_status(response, opts)
  end

  def handle({:error, %Mint.TransportError{} = exception}, _opts) do
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

  def handle({:error, %Mint.HTTPError{} = exception}, _opts) do
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

  def handle({:error, exception}, _opts) do
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

  @doc """
  Parses Retry-After headers into milliseconds.

  Supports both formats:
  - retry-after-ms: Direct milliseconds value
  - retry-after: Seconds value (converted to ms)

  Returns 1000ms (1 second) as default if header is missing or invalid.
  """
  @spec parse_retry_after([{String.t(), String.t()}]) :: non_neg_integer()
  def parse_retry_after(headers) do
    parse_retry_after_ms(headers) || parse_retry_after_seconds(headers) || 1_000
  end

  # Private functions

  defp handle_by_status(%Finch.Response{status: status, headers: headers} = response, opts)
       when status in [301, 302, 307, 308] do
    case Headers.find_value(headers, "location") do
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
        expires = Headers.find_value(headers, "expires")
        payload = %{"url" => location, "status" => status, "expires" => expires}
        wrap_success(payload, response, opts)
    end
  end

  defp handle_by_status(%Finch.Response{status: status, body: body} = response, opts)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, data} ->
        wrap_success(data, response, opts)

      {:error, _} when body in [nil, ""] ->
        wrap_success(%{}, response, opts)

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

  defp handle_by_status(%Finch.Response{status: 429, headers: headers, body: body}, _opts) do
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

  defp handle_by_status(%Finch.Response{status: status, headers: headers, body: body}, _opts) do
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

  defp parse_retry_after_ms(headers) do
    headers
    |> Headers.get_normalized("retry-after-ms")
    |> parse_integer(:ms, log: false)
  end

  defp parse_retry_after_seconds(headers) do
    headers
    |> Headers.get_normalized("retry-after")
    |> parse_integer(:seconds, log: true)
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
end
