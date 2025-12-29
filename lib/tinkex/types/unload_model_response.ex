defmodule Tinkex.Types.UnloadModelResponse do
  @moduledoc """
  Response confirming a model unload request.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:model_id]
  defstruct [:model_id, :type]

  @schema Schema.define([
            {:model_id, :string, [required: true]},
            {:type, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t() | nil
        }

  @doc """
  Parse from a JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
