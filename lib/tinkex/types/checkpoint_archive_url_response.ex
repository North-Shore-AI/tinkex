defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @moduledoc """
  Response containing a download URL for a checkpoint archive.
  """

  @type t :: %__MODULE__{
          url: String.t()
        }

  defstruct [:url]

  @doc """
  Convert a map (from JSON) to a CheckpointArchiveUrlResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      url: map["url"] || map[:url]
    }
  end
end
