defmodule Tinkex.Types.HealthResponse do
  @moduledoc """
  Health check response.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:status]
  defstruct [:status]

  @schema Schema.define([
            {:status, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{status: String.t()}

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(map) do
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__), coerce: true)
  end
end
