defmodule Tinkex.Adapters.JasonSerializer do
  @moduledoc """
  Jason-based JSON serializer adapter.
  """

  @behaviour Tinkex.Ports.Serializer

  @impl true
  def encode(payload, opts \\ []) do
    Jason.encode(payload, opts)
  end

  @impl true
  def decode(payload, _schema \\ nil, opts \\ []) do
    Jason.decode(payload, opts)
  end
end
