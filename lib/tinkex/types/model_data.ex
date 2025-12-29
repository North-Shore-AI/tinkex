defmodule Tinkex.Types.ModelData do
  @moduledoc """
  Model metadata including architecture, display name, and tokenizer id.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:arch, :model_name, :tokenizer_id]

  @schema Schema.define([
            {:arch, :string, [optional: true]},
            {:model_name, :string, [optional: true]},
            {:tokenizer_id, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          arch: String.t() | nil,
          model_name: String.t() | nil,
          tokenizer_id: String.t() | nil
        }

  @doc """
  Parse model metadata from a JSON map (string or atom keys).
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
