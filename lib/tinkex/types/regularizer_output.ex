defmodule Tinkex.Types.RegularizerOutput do
  @moduledoc """
  Output metrics from a single regularizer computation.

  This struct captures both the loss contribution and optional gradient
  tracking information for monitoring regularizer dynamics.

  ## Fields

  - `:name` - Regularizer name (matches RegularizerSpec.name)
  - `:value` - Raw loss value before weighting
  - `:weight` - Weight applied to the loss
  - `:contribution` - Weighted contribution: `weight * value`
  - `:grad_norm` - L2 norm of gradients (when tracking enabled)
  - `:grad_norm_weighted` - Weighted gradient norm: `weight * grad_norm`
  - `:custom` - Custom metrics returned by the regularizer function

  ## Examples

      %RegularizerOutput{
        name: "l1_sparsity",
        value: 22.4,
        weight: 0.01,
        contribution: 0.224,
        grad_norm: 7.48,
        grad_norm_weighted: 0.0748,
        custom: %{"l1_total" => 44.8, "l1_mean" => 22.4}
      }
  """

  @enforce_keys [:name, :value, :weight, :contribution]
  defstruct [
    :name,
    :value,
    :weight,
    :contribution,
    :grad_norm,
    :grad_norm_weighted,
    custom: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          value: float(),
          weight: float(),
          contribution: float(),
          grad_norm: float() | nil,
          grad_norm_weighted: float() | nil,
          custom: %{String.t() => number()}
        }

  @doc """
  Create a RegularizerOutput from computation results.

  ## Parameters

  - `name` - Regularizer identifier
  - `loss_value` - Raw loss value (before weighting)
  - `weight` - Weight multiplier
  - `custom_metrics` - Map of custom metrics (or nil)
  - `grad_norm` - L2 norm of gradients (optional)

  ## Examples

      RegularizerOutput.from_computation("l1", 22.4, 0.01, %{"l1_mean" => 22.4}, 7.48)
  """
  @spec from_computation(
          name :: String.t(),
          loss_value :: float(),
          weight :: float(),
          custom_metrics :: map() | nil,
          grad_norm :: float() | nil
        ) :: t()
  def from_computation(name, loss_value, weight, custom_metrics, grad_norm \\ nil) do
    %__MODULE__{
      name: name,
      value: loss_value,
      weight: weight,
      contribution: weight * loss_value,
      grad_norm: grad_norm,
      grad_norm_weighted: if(grad_norm, do: weight * grad_norm),
      custom: custom_metrics || %{}
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.RegularizerOutput do
  def encode(output, opts) do
    map = %{
      name: output.name,
      value: output.value,
      weight: output.weight,
      contribution: output.contribution,
      custom: output.custom
    }

    # Only include gradient fields if present
    map =
      if output.grad_norm do
        Map.merge(map, %{
          grad_norm: output.grad_norm,
          grad_norm_weighted: output.grad_norm_weighted
        })
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
