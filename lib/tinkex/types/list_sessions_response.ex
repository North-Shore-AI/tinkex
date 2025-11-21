defmodule Tinkex.Types.ListSessionsResponse do
  @moduledoc """
  Response from list_sessions API.

  Contains a list of session IDs.
  """

  @type t :: %__MODULE__{
          sessions: [String.t()]
        }

  defstruct [:sessions]

  @doc """
  Convert a map (from JSON) to a ListSessionsResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      sessions: map["sessions"] || map[:sessions] || []
    }
  end
end
