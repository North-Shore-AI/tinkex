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

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

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

  @schema Schema.define([
            {:name, :string, [required: true]},
            {:value, :float, [required: true]},
            {:weight, :float, [required: true]},
            {:contribution, :float, [required: true]},
            {:grad_norm, :float, [optional: true]},
            {:grad_norm_weighted, :float, [optional: true]},
            {:custom, :map, [optional: true, default: %{}]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Parse a regularizer output from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end

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
    output
    |> Tinkex.SchemaCodec.omit_nil_fields([:grad_norm, :grad_norm_weighted])
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
