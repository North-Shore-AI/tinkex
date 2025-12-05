defmodule Tinkex.Regularizers.ElasticNet do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Elastic Net adapter combining L1 and L2 via NxPenalties primitives.
  """

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    tensor = resolve_target!(data, logprobs, Keyword.get(opts, :target, :logprobs))
    reduction = Keyword.get(opts, :reduction, :sum)
    l1_ratio = Keyword.get(opts, :l1_ratio, 0.5)

    penalty =
      NxPenalties.Penalties.elastic_net(tensor,
        reduction: reduction,
        lambda: Keyword.get(opts, :lambda, 1.0),
        l1_ratio: l1_ratio
      )

    metrics =
      if tracing?(logprobs) do
        %{}
      else
        %{
          "elastic_net" => Nx.to_number(penalty),
          "l1_ratio" => l1_ratio
        }
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "elastic_net"

  defp resolve_target!(data, logprobs, target) do
    case target do
      :logprobs -> logprobs
      :probs -> Nx.exp(logprobs)
      {:field, key} -> fetch_field!(data, key)
      other -> raise ArgumentError, "Unsupported ElasticNet target: #{inspect(other)}"
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
