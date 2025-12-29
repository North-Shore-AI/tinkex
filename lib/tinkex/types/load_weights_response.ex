defmodule Tinkex.Types.LoadWeightsResponse do
  @moduledoc """
  Response payload for load_weights.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:path, type: "load_weights"]

  @schema Schema.define([
            {:path, :string, [optional: true]},
            {:type, :string, [optional: true, default: "load_weights"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          path: String.t() | nil,
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
