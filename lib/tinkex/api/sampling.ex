defmodule Tinkex.API.Sampling do
  @moduledoc """
  Sampling API endpoints.

  Uses :sampling pool (high concurrency).
  Pool size: 100 connections.
  """

  alias Pristine.Core.Context
  alias Pristine.Streaming.Event

  alias Tinkex.Context, as: ContextBuilder
  alias Tinkex.Error
  alias Tinkex.Types.SampleStreamChunk

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
  rate limiting and retry logic via BackoffWindow. The HTTP layer doesn't retry
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

    client.post("/api/v1/asample", request, Keyword.put(opts, :endpoint_id, :asample))
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
    context =
      case Keyword.get(opts, :context) do
        %Context{} = context -> context
        _ -> ContextBuilder.new(Keyword.fetch!(opts, :config))
      end

    opts =
      opts
      |> Keyword.put_new(:context, context)
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put(:max_retries, 0)
      |> Keyword.put_new(:sampling_backpressure, true)
      |> Keyword.put_new(:transform, drop_nil?: true)

    with {:ok, _response, events} <-
           Tinkex.API.stream_request(
             :post,
             "/api/v1/stream_sample",
             request,
             Keyword.put(opts, :endpoint_id, :stream_sample)
           ) do
      stream =
        events
        |> Stream.map(&parse_sse_event(&1, context))
        |> Stream.reject(&is_nil/1)

      {:ok, stream}
    end
  end

  # Private helpers

  defp parse_sse_event(%Event{data: data}, _context) when data in ["", nil], do: nil

  defp parse_sse_event(%Event{data: data}, context) do
    case context.serializer.decode(data, nil) do
      {:ok, parsed} -> SampleStreamChunk.from_map(parsed)
      {:error, _} -> nil
    end
  end
end
