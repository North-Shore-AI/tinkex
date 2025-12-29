defmodule Tinkex.Types.CreateSamplingSessionResponse do
  @moduledoc """
  Response from create sampling session request.

  Mirrors Python tinker.types.CreateSamplingSessionResponse.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:sampling_session_id]
  defstruct [:sampling_session_id]

  @schema Schema.define([
            {:sampling_session_id, :string, [required: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          sampling_session_id: String.t()
        }

  @doc """
  Parse a create sampling session response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
