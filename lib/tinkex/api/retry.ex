defmodule Tinkex.API.Retry do
  @moduledoc """
  Retry logic with exponential backoff for Tinkex API requests.

  Implements Python SDK parity for retry behavior:
  - Exponential backoff with jitter
  - Configurable max retries
  - Status-based retry decisions (429, 408, 409, 5xx)
  - Retry-After header support
  - x-should-retry header override
  """

  require Logger

  alias Tinkex.Config
  alias Tinkex.API.{Headers, ResponseHandler}

  # Python SDK parity constants from _constants.py
  @initial_retry_delay 500
  @max_retry_delay 10_000

  @typep retry_result :: {{:ok, Finch.Response.t()} | {:error, term()}, non_neg_integer()}

  @doc """
  Executes a request with automatic retry logic.

  Retries are governed by:
  1. max_retries configuration (no wall-clock timeout)
  2. Status codes (429, 408, 409, 5xx)
  3. Connection errors (transport, HTTP)
  4. x-should-retry header override

  ## Options

  - `request` - Finch request to execute
  - `pool` - Connection pool name
  - `timeout` - Per-request timeout in milliseconds
  - `max_retries` - Maximum number of retry attempts
  - `dump_headers?` - Whether to log request details

  ## Returns

  `{result, retry_count}` where result is `{:ok, response}` or `{:error, reason}`
  and retry_count is the number of retries performed.
  """
  @spec execute(Finch.Request.t(), atom(), timeout(), non_neg_integer(), boolean()) ::
          retry_result
  def execute(request, pool, timeout, max_retries, dump_headers?) do
    timeout = normalize_timeout(timeout)
    max_retries = normalize_max_retries(max_retries)
    dump_headers? = !!dump_headers?

    context = %{
      request: request,
      pool: pool,
      timeout: timeout,
      dump_headers?: dump_headers?
    }

    perform_retry(context, max_retries, 0)
  end

  @doc """
  Calculates retry delay with exponential backoff and jitter.

  Python parity implementation:
  - Base delay: INITIAL_RETRY_DELAY * 2^attempt
  - Capped at: MAX_RETRY_DELAY
  - Jitter: random value in range [0.75, 1.0]

  ## Examples

      iex> delay = calculate_delay(0)
      iex> delay >= 375 and delay <= 500
      true

      iex> delay = calculate_delay(5)
      iex> delay >= 7500 and delay <= 10000
      true
  """
  @spec calculate_delay(non_neg_integer()) :: non_neg_integer()
  def calculate_delay(attempt) do
    base_delay = @initial_retry_delay * :math.pow(2, attempt)
    capped_delay = min(base_delay, @max_retry_delay)
    # Python jitter: 1 - 0.25 * random() gives [0.75, 1.0]
    jitter = 0.75 + :rand.uniform() * 0.25
    round(capped_delay * jitter)
  end

  # Private functions

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(_timeout), do: Config.default_timeout()

  defp normalize_max_retries(max_retries) when is_integer(max_retries) and max_retries >= 0,
    do: max_retries

  defp normalize_max_retries(_max_retries), do: 0

  defp perform_retry(context, max_retries, attempt) do
    request = Headers.put_retry_headers(context.request, attempt, context.timeout)
    maybe_dump_request(request, attempt, context.dump_headers?)

    case Finch.request(request, context.pool, receive_timeout: context.timeout) do
      {:ok, %Finch.Response{} = response} = response_tuple ->
        handle_success(response_tuple, response, context, max_retries, attempt)

      {:error, %Mint.TransportError{reason: reason}} = error ->
        handle_retryable_error(error, reason, context, max_retries, attempt)

      {:error, %Mint.HTTPError{reason: reason}} = error ->
        handle_retryable_error(error, reason, context, max_retries, attempt)

      other ->
        {other, attempt}
    end
  end

  defp handle_success(
         response_tuple,
         %Finch.Response{status: status, headers: headers},
         context,
         max_retries,
         attempt
       ) do
    case retry_decision(status, headers, max_retries, attempt) do
      {:retry, delay_ms} ->
        Logger.debug(
          "Retrying request (attempt #{attempt + 1}/#{max_retries}) status=#{status} delay=#{delay_ms}ms"
        )

        Process.sleep(delay_ms)
        perform_retry(context, max_retries, attempt + 1)

      :no_retry ->
        {response_tuple, attempt}
    end
  end

  defp retry_decision(_status, _headers, max_retries, attempt) when attempt >= max_retries,
    do: :no_retry

  defp retry_decision(status, headers, _max_retries, attempt) do
    case Headers.get_normalized(headers, "x-should-retry") do
      "false" ->
        :no_retry

      "true" ->
        {:retry, calculate_delay(attempt)}

      _ ->
        status_based_decision(status, headers, attempt)
    end
  end

  # Python parity: retries on 429 with Retry-After header
  defp status_based_decision(429, headers, _attempt),
    do: {:retry, ResponseHandler.parse_retry_after(headers)}

  # Python parity: retries on 408 (Request Timeout)
  defp status_based_decision(408, _headers, attempt),
    do: {:retry, calculate_delay(attempt)}

  # Python parity: retries on 409 (Conflict/Lock Timeout) - _base_client.py line 724-727
  defp status_based_decision(409, _headers, attempt),
    do: {:retry, calculate_delay(attempt)}

  # Python parity: retries on 5xx (Server Errors)
  defp status_based_decision(status, _headers, attempt) when status in 500..599,
    do: {:retry, calculate_delay(attempt)}

  defp status_based_decision(_status, _headers, _attempt), do: :no_retry

  defp handle_retryable_error(error, reason, context, max_retries, attempt) do
    if attempt < max_retries do
      delay = calculate_delay(attempt)
      Logger.debug("Retrying after #{inspect(reason)} delay=#{delay}ms")
      Process.sleep(delay)
      perform_retry(context, max_retries, attempt + 1)
    else
      {error, attempt}
    end
  end

  defp maybe_dump_request(%Finch.Request{} = request, attempt, dump_headers?) do
    if dump_headers? do
      url = build_request_url(request)
      headers = Headers.redact(request.headers)
      body = dump_body(request.body)

      Logger.info(
        "HTTP #{String.upcase(to_string(request.method))} #{url} attempt=#{attempt} headers=#{inspect(headers)} body=#{body}"
      )
    end
  end

  defp build_request_url(%Finch.Request{} = request) do
    scheme = request.scheme |> to_string()
    port = request.port
    default_port? = (scheme == "https" and port == 443) or (scheme == "http" and port == 80)
    port_segment = if default_port?, do: "", else: ":#{port}"
    query_segment = if request.query in [nil, ""], do: "", else: "?#{request.query}"

    "#{scheme}://#{request.host}#{port_segment}#{request.path}#{query_segment}"
  end

  defp dump_body(nil), do: "nil"

  defp dump_body(body) do
    try do
      IO.iodata_to_binary(body)
    rescue
      _ -> inspect(body)
    end
  end
end
