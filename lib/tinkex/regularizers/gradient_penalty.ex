defmodule Tinkex.Regularizers.GradientPenalty do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Gradient penalty adapter built on NxPenalties primitives.

  Modes:
    * `:output` - Penalize gradient norm w.r.t. current logprobs
    * `:interpolated` - WGAN-GP style penalty between logprobs and a reference
  """

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    mode = Keyword.get(opts, :mode, :output)
    loss_fn = Keyword.fetch!(opts, :loss_fn)
    target_norm = Keyword.get(opts, :target_norm, 1.0)

    penalty =
      case mode do
        :output ->
          NxPenalties.GradientPenalty.gradient_penalty(loss_fn, logprobs,
            target_norm: target_norm
          )

        :interpolated ->
          reference =
            resolve_reference!(data, Keyword.get(opts, :reference_field, :reference_logprobs))

          NxPenalties.GradientPenalty.interpolated_gradient_penalty(
            loss_fn,
            logprobs,
            reference,
            target_norm: target_norm
          )

        other ->
          raise ArgumentError, "Unsupported gradient penalty mode: #{inspect(other)}"
      end

    {penalty, %{}}
  end

  @impl true
  def name, do: "gradient_penalty"

  defp resolve_reference!(data, field) do
    data
    |> List.first()
    |> case do
      nil -> raise ArgumentError, "Empty data; cannot resolve reference field #{inspect(field)}"
      %{loss_fn_inputs: inputs} -> fetch_from_inputs!(inputs, field) |> to_tensor()
      other -> raise ArgumentError, "Expected datum with loss_fn_inputs, got: #{inspect(other)}"
    end
  end

  defp fetch_from_inputs!(inputs, field) do
    cond do
      Map.has_key?(inputs, field) -> Map.fetch!(inputs, field)
      Map.has_key?(inputs, to_string(field)) -> Map.fetch!(inputs, to_string(field))
      true -> raise KeyError, "Missing reference field #{inspect(field)} in loss_fn_inputs"
    end
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t
end
