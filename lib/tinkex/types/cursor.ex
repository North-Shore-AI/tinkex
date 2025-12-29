defmodule Tinkex.Types.Cursor do
  @moduledoc """
  Pagination cursor for paged responses.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:offset, :limit, :total_count]
  defstruct [:offset, :limit, :total_count]

  @schema Schema.define([
            {:offset, :integer, [optional: true, default: 0]},
            {:limit, :integer, [optional: true, default: 0]},
            {:total_count, :integer, [optional: true, default: 0]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          limit: non_neg_integer(),
          total_count: non_neg_integer()
        }

  @doc """
  Parse a Cursor from a map.
  """
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil
  def from_map(map) when not is_map(map), do: nil

  def from_map(map) when is_map(map) do
    case SchemaCodec.validate(schema(), map, coerce: true) do
      {:ok, validated} ->
        SchemaCodec.to_struct(struct(__MODULE__), validated)

      {:error, _} ->
        %__MODULE__{offset: 0, limit: 0, total_count: 0}
    end
  end
end
