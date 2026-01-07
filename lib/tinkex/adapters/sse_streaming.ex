defmodule Tinkex.Adapters.SSEStreaming do
  @moduledoc """
  SSE decoder adapter built on `Tinkex.Streaming.SSEDecoder`.
  """

  @behaviour Tinkex.Ports.Streaming

  alias Tinkex.Streaming.SSEDecoder

  @impl true
  def decode(input, opts \\ [])

  def decode(body, _opts) when is_binary(body) do
    {events, _decoder} = SSEDecoder.feed(SSEDecoder.new(), body <> "\n\n")
    Stream.concat([events])
  end

  def decode(stream, _opts) do
    Stream.transform(stream, SSEDecoder.new(), fn chunk, decoder ->
      chunk = IO.iodata_to_binary(chunk)
      {events, decoder} = SSEDecoder.feed(decoder, chunk)
      {events, decoder}
    end)
  end
end
