defmodule Tinkex.Types.RequestFailedResponse do
  @moduledoc """
  Response indicating a request has failed.

  Mirrors Python `tinker.types.RequestFailedResponse`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.RequestErrorCategory

  @enforce_keys [:error, :category]
  defstruct [:error, :category]

  @schema Schema.define([
            {:error, :string, [required: true]},
            {:category, :string, [required: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          error: String.t(),
          category: RequestErrorCategory.t()
        }

  @doc """
  Create a new RequestFailedResponse.
  """
  @spec new(String.t(), RequestErrorCategory.t()) :: t()
  def new(error, category) when is_binary(error) do
    %__MODULE__{error: error, category: category}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__),
      coerce: true,
      converters: %{category: &RequestErrorCategory.parse/1}
    )
  end
end
