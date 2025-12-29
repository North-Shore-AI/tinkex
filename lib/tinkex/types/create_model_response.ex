defmodule Tinkex.Types.CreateModelResponse do
  @moduledoc """
  Response from create model request.

  Mirrors Python tinker.types.CreateModelResponse.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:model_id]
  defstruct [:model_id]

  @schema Schema.define([
            {:model_id, :string, [required: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t()
        }

  @doc """
  Parse a create model response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
