defmodule Tinkex.Types.CreateModelResponse do
  @moduledoc """
  Response from create model request.

  Mirrors Python tinker.types.CreateModelResponse.
  """

  @enforce_keys [:model_id]
  defstruct [:model_id]

  @type t :: %__MODULE__{
          model_id: String.t()
        }

  @doc """
  Parse a create model response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      model_id: json["model_id"]
    }
  end
end
