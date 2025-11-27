defmodule Tinkex.Types.SaveWeightsForSamplerResponse do
  @moduledoc """
  Response payload for save_weights_for_sampler.
  """

  defstruct [:path, :sampling_session_id, type: "save_weights_for_sampler"]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          sampling_session_id: String.t() | nil,
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    path = Map.get(json, "path") || Map.get(json, :path)

    %__MODULE__{
      path: path,
      sampling_session_id:
        Map.get(json, "sampling_session_id") || Map.get(json, :sampling_session_id),
      type: Map.get(json, "type") || Map.get(json, :type) || "save_weights_for_sampler"
    }
  end
end
