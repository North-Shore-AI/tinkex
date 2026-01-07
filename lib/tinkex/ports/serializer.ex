defmodule Tinkex.Ports.Serializer do
  @moduledoc """
  Port for encoding/decoding payloads.
  """

  @callback encode(term(), keyword()) :: {:ok, binary()} | {:error, term()}
  @callback decode(binary(), term() | nil, keyword()) :: {:ok, term()} | {:error, term()}
end
