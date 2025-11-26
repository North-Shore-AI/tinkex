defmodule Tinkex.Types.CustomLossOutput do
  @moduledoc """
  Structured output from custom loss computation with regularizers.

  This type mirrors the Python SDK's metrics schema for API compatibility,
  providing comprehensive telemetry for research workflows.

  ## Schema

      %CustomLossOutput{
        loss_total: 2.847,
        base_loss: %{
          value: 2.5,
          grad_norm: 3.14,
          custom: %{"perplexity" => 12.18}
        },
        regularizers: %{
          "sparsity" => %RegularizerOutput{...},
          "entropy" => %RegularizerOutput{...}
        },
        regularizer_total: 0.347,
        total_grad_norm: 5.67
      }

  ## Loss Composition

  The total loss is computed as:

      loss_total = base_loss + Σ(weight_i × regularizer_i_loss)

  Each regularizer's contribution is `weight * value`.
  """

  alias Tinkex.Types.RegularizerOutput

  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizer_total,
    :total_grad_norm,
    regularizers: %{}
  ]

  @type base_loss_metrics :: %{
          value: float(),
          grad_norm: float() | nil,
          custom: %{String.t() => number()}
        }

  @type t :: %__MODULE__{
          loss_total: float(),
          base_loss: base_loss_metrics() | nil,
          regularizers: %{String.t() => RegularizerOutput.t()},
          regularizer_total: float() | nil,
          total_grad_norm: float() | nil
        }

  @doc """
  Build CustomLossOutput from computation results.

  ## Parameters

  - `base_loss_value` - The primary loss value
  - `base_loss_metrics` - Custom metrics from base loss function
  - `regularizer_outputs` - List of RegularizerOutput structs
  - `opts` - Optional: `:base_grad_norm`, `:total_grad_norm`

  ## Examples

      CustomLossOutput.build(2.5, %{"nll" => 2.5}, regularizer_outputs,
        base_grad_norm: 3.14,
        total_grad_norm: 5.67
      )
  """
  @spec build(
          base_loss_value :: float(),
          base_loss_metrics :: map() | nil,
          regularizer_outputs :: list(RegularizerOutput.t()),
          opts :: keyword()
        ) :: t()
  def build(base_loss_value, base_loss_metrics, regularizer_outputs, opts \\ []) do
    base_grad_norm = Keyword.get(opts, :base_grad_norm)
    total_grad_norm = Keyword.get(opts, :total_grad_norm)

    regularizer_total =
      regularizer_outputs
      |> Enum.map(& &1.contribution)
      |> Enum.sum()

    regularizers_map =
      regularizer_outputs
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    %__MODULE__{
      loss_total: base_loss_value + regularizer_total,
      base_loss: %{
        value: base_loss_value,
        grad_norm: base_grad_norm,
        custom: base_loss_metrics || %{}
      },
      regularizers: regularizers_map,
      regularizer_total: regularizer_total,
      total_grad_norm: total_grad_norm
    }
  end

  @doc """
  Get the primary loss value (for backward compatibility).

  Equivalent to accessing `output.loss_total`.
  """
  @spec loss(t()) :: float()
  def loss(%__MODULE__{loss_total: loss_total}), do: loss_total
end

defimpl Jason.Encoder, for: Tinkex.Types.CustomLossOutput do
  def encode(output, opts) do
    base = %{
      loss_total: output.loss_total,
      regularizer_total: output.regularizer_total,
      regularizers:
        output.regularizers
        |> Enum.map(fn {name, reg} ->
          {name,
           %{
             value: reg.value,
             weight: reg.weight,
             contribution: reg.contribution,
             grad_norm: reg.grad_norm,
             grad_norm_weighted: reg.grad_norm_weighted,
             custom: reg.custom
           }}
        end)
        |> Map.new()
    }

    # Add base_loss if present
    base =
      if output.base_loss do
        Map.put(base, :base_loss, output.base_loss)
      else
        base
      end

    # Add total_grad_norm if present
    base =
      if output.total_grad_norm do
        Map.put(base, :total_grad_norm, output.total_grad_norm)
      else
        base
      end

    Jason.Encode.map(base, opts)
  end
end
