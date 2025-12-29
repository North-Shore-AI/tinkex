defmodule Tinkex.Types.TrainingRunsResponse do
  @moduledoc """
  Paginated training run response.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.{Cursor, TrainingRun}

  @enforce_keys [:training_runs]
  defstruct [:training_runs, :cursor]

  @schema Schema.define([
            {:training_runs, {:array, {:object, TrainingRun.schema()}},
             [optional: true, default: []]},
            {:cursor, {:nullable, {:object, Cursor.schema()}}, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          training_runs: [TrainingRun.t()],
          cursor: Cursor.t() | nil
        }

  @doc """
  Parse from a JSON map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__),
      coerce: true,
      converters: %{training_runs: {:list, TrainingRun}, cursor: Cursor}
    )
  end
end
