defmodule Tinkex.API.Sampling do
  @moduledoc """
  Sampling API endpoints.

  Uses :sampling pool (high concurrency).
  Pool size: 100 connections.
  """

  alias Tinkex.API.{Headers, URL}
  alias Tinkex.Error
  alias Tinkex.PoolKey
  alias Tinkex.Streaming.{ServerSentEvent, SSEDecoder}
  alias Tinkex.Types.SampleStreamChunk

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
  rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry
  so that the higher-level client can make intelligent retry decisions based
  on rate limit state.

  Note: Named `sample_async` for consistency with Elixir naming conventions
  (adjective_noun or verb_object patterns). The API endpoint remains /api/v1/asample.

  ## Examples

      Tinkex.API.Sampling.sample_async(
        %{session_id: "...", prompts: [...]},
        config: config
      )
  """
  @spec sample_async(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def sample_async(request, opts) do
    max_retries = Keyword.get(opts, :max_retries, 0)
    client = Tinkex.API.client_module(opts)

    opts =
      opts
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put(:max_retries, max_retries)
      |> Keyword.put_new(:sampling_backpressure, true)
      # Drop nil values - server rejects null for optional fields like prompt_logprobs
      |> Keyword.put_new(:transform, drop_nil?: true)

    client.post("/api/v1/asample", request, opts)
  end

  @doc """
  Streaming sample request via SSE.

  Returns a stream of `SampleStreamChunk` structs that can be consumed
  incrementally for real-time token generation.

  Uses :sampling pool (high concurrency).
  Does not retry - streaming responses cannot be reliably retried mid-stream.

  ## Examples

      {:ok, stream} = Tinkex.API.Sampling.sample_stream(request, config: config)
      Enum.each(stream, fn chunk -> IO.write(chunk.token) end)
  """
  @spec sample_stream(map(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def sample_stream(request, opts) do
    config = Keyword.fetch!(opts, :config)
    pool_name = PoolKey.resolve_pool_name(config.http_pool, config.base_url, :sampling)
    timeout = Keyword.get(opts, :timeout, config.timeout)

    url = URL.build_url(config.base_url, "/api/v1/stream_sample", %{}, %{})

    headers =
      Headers.build(:post, config, opts, timeout)
      |> Kernel.++([{"accept", "text/event-stream"}])
      |> Headers.dedupe()

    body = prepare_request_body(request)

    finch_request = Finch.build(:post, url, headers, body)

    case Finch.request(finch_request, pool_name, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        stream = parse_sse_response(response_body)
        {:ok, stream}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error,
         %Error{
           message: "Streaming sample failed with status #{status}",
           type: :api_status,
           status: status,
           category: categorize_status(status),
           data: %{body: response_body}
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

      {:error, %Mint.HTTPError{} = error} ->
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
           data: %{reason: reason}
         }}
    end
  end

  # Private helpers

  defp prepare_request_body(request) do
    request
    |> drop_nil_values()
    |> Jason.encode!()
  end

  defp drop_nil_values(map) when is_map(map) do
    map
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  rescue
    # Not a struct, just a regular map
    _error ->
      map
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
  end

  defp parse_sse_response(body) do
    # Add trailing newlines to ensure last event is parsed
    {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), body <> "\n\n")

    events
    |> Stream.map(&parse_sse_event/1)
    |> Stream.reject(&is_nil/1)
  end

  defp parse_sse_event(%ServerSentEvent{data: data}) when data in ["", nil], do: nil

  defp parse_sse_event(%ServerSentEvent{data: data}) do
    case Jason.decode(data) do
      {:ok, parsed} -> SampleStreamChunk.from_map(parsed)
      {:error, _} -> nil
    end
  end

  defp categorize_status(status) when status in 400..499, do: :user
  defp categorize_status(status) when status in 500..599, do: :server
  defp categorize_status(_), do: nil
end
