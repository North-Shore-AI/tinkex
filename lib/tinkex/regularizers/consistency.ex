defmodule Tinkex.Regularizers.Consistency do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Consistency regularizer adapter using NxPenalties constraints.

  Expects paired outputs in `loss_fn_inputs` (e.g., `"original_logprobs"`).
  """

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    if tracing?(logprobs) do
      zero = Nx.tensor(0.0, type: Nx.type(logprobs))
      {zero, %{}}
    else
      pair_field = Keyword.get(opts, :pair_field, "original_logprobs")
      reference = resolve_reference!(data, pair_field)
      metric = Keyword.get(opts, :metric, :mse)
      reduction = Keyword.get(opts, :reduction, :mean)

      loss =
        NxPenalties.Constraints.consistency(logprobs, reference,
          metric: metric,
          reduction: reduction
        )

      metrics =
        if tracing?(logprobs) do
          %{}
        else
          %{"consistency_metric" => Atom.to_string(metric)}
        end

      {loss, metrics}
    end
  end

  @impl true
  def name, do: "consistency"

  defp resolve_reference!(data, field) do
    data
    |> List.first()
    |> case do
      nil -> raise ArgumentError, "Empty data; cannot resolve pair field #{inspect(field)}"
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

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
