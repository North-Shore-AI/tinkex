defmodule Tinkex.Types.ForwardBackwardOutput do
  @moduledoc """
  Output from forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardOutput.

  NOTE: There is NO `loss` field. Loss is accessed via `metrics["loss"]`.
  """

  defstruct [:loss_fn_output_type, :loss_fn_outputs, :metrics]

  @type t :: %__MODULE__{
          loss_fn_output_type: String.t(),
          loss_fn_outputs: [map()],
          metrics: %{String.t() => float()}
        }

  @doc """
  Parse a forward-backward output from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      loss_fn_output_type: json["loss_fn_output_type"],
      loss_fn_outputs: json["loss_fn_outputs"] || [],
      metrics: json["metrics"] || %{}
    }
  end

  @doc """
  Get the loss value from metrics.
  """
  @spec loss(t()) :: float() | nil
  def loss(%__MODULE__{metrics: metrics}) do
    Map.get(metrics, "loss")
  end
end
