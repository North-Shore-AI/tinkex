defmodule Tinkex.Ports.Streaming do
  @moduledoc """
  Port for SSE decoding and streaming helpers.
  """

  alias Tinkex.Streaming.ServerSentEvent

  @type input :: binary() | Enumerable.t()
  @type event :: ServerSentEvent.t()

  @callback decode(input(), keyword()) :: Enumerable.t()
end
