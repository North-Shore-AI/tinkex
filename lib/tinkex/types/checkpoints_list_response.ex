defmodule Tinkex.Types.CheckpointsListResponse do
  @moduledoc """
  Response from list_checkpoints or list_user_checkpoints API.

  Contains a list of checkpoints and optional cursor for pagination.
  """

  alias Tinkex.Types.{Checkpoint, Cursor}

  @type t :: %__MODULE__{
          checkpoints: [Checkpoint.t()],
          cursor: Cursor.t() | nil
        }

  defstruct [:checkpoints, :cursor]

  @doc """
  Convert a map (from JSON) to a CheckpointsListResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    checkpoints =
      (map["checkpoints"] || map[:checkpoints] || [])
      |> Enum.map(&Checkpoint.from_map/1)

    %__MODULE__{
      checkpoints: checkpoints,
      cursor: (map["cursor"] || map[:cursor]) |> Cursor.from_map()
    }
  end
end
