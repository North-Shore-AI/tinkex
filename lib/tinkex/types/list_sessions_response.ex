defmodule Tinkex.Types.ListSessionsResponse do
  @moduledoc """
  Response from list_sessions API.

  Contains a list of session IDs.
  """

  @type t :: %__MODULE__{
          sessions: [String.t()]
        }

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:sessions]

  @schema Schema.define([
            {:sessions, {:array, :string}, [optional: true, default: []]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Convert a map (from JSON) to a ListSessionsResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__), coerce: true)
  end
end
