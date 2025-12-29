defmodule Tinkex.Types.FutureRetrieveRequest do
  @moduledoc """
  Request to retrieve the result of a future/async operation.

  Mirrors Python `tinker.types.FutureRetrieveRequest`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:request_id]
  defstruct [:request_id]

  @schema Schema.define([
            {:request_id, :string, [required: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          request_id: String.t()
        }

  @doc """
  Create a new FutureRetrieveRequest.
  """
  @spec new(String.t()) :: t()
  def new(request_id) when is_binary(request_id) do
    %__MODULE__{request_id: request_id}
  end

  @doc """
  Convert to JSON-encodable map.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{request_id: request_id}) do
    SchemaCodec.encode_map(%__MODULE__{request_id: request_id})
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end
