defmodule Tinkex.Types.OptimStepResponse do
  @moduledoc """
  Response from optimizer step request.

  Mirrors Python tinker.types.OptimStepResponse.
  """

  defstruct [:success]

  @type t :: %__MODULE__{
          success: boolean()
        }

  @doc """
  Parse an optim step response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      success: json["success"] || true
    }
  end
end
