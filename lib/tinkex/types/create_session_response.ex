defmodule Tinkex.Types.CreateSessionResponse do
  @moduledoc """
  Response from create session request.

  Mirrors Python tinker.types.CreateSessionResponse.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:session_id]
  defstruct [:session_id, :info_message, :warning_message, :error_message]

  @schema Schema.define([
            {:session_id, :string, [required: true]},
            {:info_message, :string, [optional: true]},
            {:warning_message, :string, [optional: true]},
            {:error_message, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          session_id: String.t(),
          info_message: String.t() | nil,
          warning_message: String.t() | nil,
          error_message: String.t() | nil
        }

  @doc """
  Parse a create session response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
