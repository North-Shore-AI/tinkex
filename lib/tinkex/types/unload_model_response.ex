defmodule Tinkex.Types.UnloadModelResponse do
  @moduledoc """
  Response confirming a model unload request.
  """

  @enforce_keys [:model_id]
  defstruct [:model_id, :type]

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t() | nil
        }

  @doc """
  Parse from a JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      type: json["type"] || json[:type]
    }
  end
end
