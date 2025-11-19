defmodule Tinkex.Types.OptimStepResponse do
  @moduledoc """
  Response from optimizer step request.

  Mirrors Python tinker.types.OptimStepResponse.
  """

  defstruct [:metrics]

  @type t :: %__MODULE__{
          metrics: %{String.t() => float()} | nil
        }

  @doc """
  Parse an optim step response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      metrics: json["metrics"]
    }
  end

  @doc """
  Convenience helper to check if the step succeeded.
  """
  @spec success?(t()) :: boolean()
  def success?(_response), do: true
end
