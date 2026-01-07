defmodule Tinkex.API.StreamResponse do
  @moduledoc """
  Streaming response wrapper for SSE/event-stream endpoints.
  """

  @enforce_keys [:stream, :status, :headers, :method, :url]
  defstruct [:stream, :status, :headers, :method, :url, :elapsed_ms]

  @type t :: %__MODULE__{
          stream: Enumerable.t(),
          status: integer() | nil,
          headers: map(),
          method: atom(),
          url: String.t(),
          elapsed_ms: non_neg_integer() | nil
        }
end
