defmodule Tinkex.Types.SaveWeightsResponse do
  @moduledoc """
  Response payload for save_weights.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:path]
  defstruct [:path, type: "save_weights"]

  @schema Schema.define([
            {:path, :string, [required: true]},
            {:type, :string, [optional: true, default: "save_weights"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          path: String.t(),
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
