defmodule Tinkex.Regularizers.L2 do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Adapter for L2/Tikhonov regularization using NxPenalties primitives.

  Mirrors the ADR contract while delegating computation to
  `NxPenalties.Penalties.l2/2`.
  """

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    tensor = resolve_target!(data, logprobs, Keyword.get(opts, :target, :logprobs))
    reduction = Keyword.get(opts, :reduction, :sum)
    center = Keyword.get(opts, :center, nil)

    penalty =
      NxPenalties.Penalties.l2(tensor,
        reduction: reduction,
        lambda: Keyword.get(opts, :lambda, 1.0),
        clip: Keyword.get(opts, :clip, nil),
        center: center
      )

    metrics =
      if tracing?(logprobs) do
        %{}
      else
        %{
          "l2_raw" => Nx.to_number(penalty),
          "l2_mean" => Nx.to_number(Nx.mean(Nx.pow(tensor, 2))),
          "center" => center || "none"
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "l2_weight_decay"

  defp resolve_target!(data, logprobs, target) do
    case target do
      :logprobs -> logprobs
      :probs -> Nx.exp(logprobs)
      {:field, key} -> fetch_field!(data, key)
      other -> raise ArgumentError, "Unsupported L2 target: #{inspect(other)}"
    end
  end

  defp fetch_field!(data, key) do
    data
    |> List.first()
    |> case do
      nil -> raise ArgumentError, "Empty data; cannot resolve field #{inspect(key)}"
      %{loss_fn_inputs: inputs} -> inputs |> Map.fetch!(key) |> to_tensor()
      other -> raise ArgumentError, "Expected datum with loss_fn_inputs, got: #{inspect(other)}"
    end
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
