defmodule Tinkex.Types.GetSessionResponse do
  @moduledoc """
  Response from get_session API.

  Contains the training run IDs and sampler IDs associated with a session.
  """

  @type t :: %__MODULE__{
          training_run_ids: [String.t()],
          sampler_ids: [String.t()]
        }

  defstruct [:training_run_ids, :sampler_ids]

  @doc """
  Convert a map (from JSON) to a GetSessionResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      training_run_ids: map["training_run_ids"] || map[:training_run_ids] || [],
      sampler_ids: map["sampler_ids"] || map[:sampler_ids] || []
    }
  end
end
