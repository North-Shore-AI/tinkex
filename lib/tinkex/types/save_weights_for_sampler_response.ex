defmodule Tinkex.Types.SaveWeightsForSamplerResponse do
  @moduledoc """
  Response payload for save_weights_for_sampler.
  """

  @enforce_keys [:path]
  defstruct [:path, :sampling_session_id, type: "save_weights_for_sampler"]

  @type t :: %__MODULE__{
          path: String.t(),
          sampling_session_id: String.t() | nil,
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"path" => path} = json) do
    %__MODULE__{
      path: path,
      sampling_session_id: json["sampling_session_id"],
      type: json["type"] || "save_weights_for_sampler"
    }
  end

  def from_json(%{path: path} = json) do
    %__MODULE__{
      path: path,
      sampling_session_id: json[:sampling_session_id],
      type: json[:type] || "save_weights_for_sampler"
    }
  end
end
