defmodule Tinkex.Types.ForwardBackwardOutput do
  @moduledoc """
  Output from forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardOutput.

  NOTE: There is NO `loss` field. Loss is accessed via `metrics["loss"]`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:loss_fn_output_type]
  defstruct [:loss_fn_output_type, loss_fn_outputs: [], metrics: %{}]

  @schema Schema.define([
            {:loss_fn_output_type, {:nullable, :string}, [required: true]},
            {:loss_fn_outputs, {:array, :map}, [optional: true, default: []]},
            {:metrics, :map, [optional: true, default: %{}]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          loss_fn_output_type: String.t() | nil,
          loss_fn_outputs: [map()],
          metrics: %{String.t() => float()}
        }

  @doc """
  Parse a forward-backward output from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    json = ensure_loss_fn_output_type(json)
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end

  defp ensure_loss_fn_output_type(json) when is_map(json) do
    if Map.has_key?(json, "loss_fn_output_type") or Map.has_key?(json, :loss_fn_output_type) do
      json
    else
      Map.put(json, "loss_fn_output_type", nil)
    end
  end

  @doc """
  Get the loss value from metrics.
  """
  @spec loss(t()) :: float() | nil
  def loss(%__MODULE__{metrics: metrics}) do
    Map.get(metrics, "loss")
  end
end
