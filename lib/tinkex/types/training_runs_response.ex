defmodule Tinkex.Types.TrainingRunsResponse do
  @moduledoc """
  Paginated training run response.
  """

  alias Tinkex.Types.{Cursor, TrainingRun}

  @enforce_keys [:training_runs]
  defstruct [:training_runs, :cursor]

  @type t :: %__MODULE__{
          training_runs: [TrainingRun.t()],
          cursor: Cursor.t() | nil
        }

  @doc """
  Parse from a JSON map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    runs =
      map
      |> fetch("training_runs")
      |> List.wrap()
      |> Enum.map(&TrainingRun.from_map/1)

    %__MODULE__{
      training_runs: runs,
      cursor: map |> fetch("cursor") |> Cursor.from_map()
    }
  end

  defp fetch(map, key) do
    map[key] || map[String.to_atom(key)] || []
  end
end
