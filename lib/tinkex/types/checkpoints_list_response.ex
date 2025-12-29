defmodule Tinkex.Types.CheckpointsListResponse do
  @moduledoc """
  Response from list_checkpoints or list_user_checkpoints API.

  Contains a list of checkpoints and optional cursor for pagination.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.{Checkpoint, Cursor}

  @type t :: %__MODULE__{
          checkpoints: [Checkpoint.t()],
          cursor: Cursor.t() | nil
        }

  defstruct [:checkpoints, :cursor]

  @schema Schema.define([
            {:checkpoints, {:array, {:object, Checkpoint.schema()}},
             [optional: true, default: []]},
            {:cursor, {:nullable, {:object, Cursor.schema()}}, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Convert a map (from JSON) to a CheckpointsListResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__),
      coerce: true,
      converters: %{checkpoints: {:list, Checkpoint}, cursor: Cursor}
    )
  end
end
