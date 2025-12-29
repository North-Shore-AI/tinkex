defmodule Tinkex.Types.SaveWeightsForSamplerResponse do
  @moduledoc """
  Response payload for save_weights_for_sampler.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:path, :sampling_session_id, type: "save_weights_for_sampler"]

  @schema Schema.define([
            {:path, :string, [optional: true]},
            {:sampling_session_id, :string, [optional: true]},
            {:type, :string, [optional: true, default: "save_weights_for_sampler"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          path: String.t() | nil,
          sampling_session_id: String.t() | nil,
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
