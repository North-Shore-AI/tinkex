defmodule Tinkex.Regularizers.Orthogonality do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Orthogonality regularizer adapter using NxPenalties constraints.
  """

  @impl true
  def compute(_data, logprobs, opts \\ []) do
    penalty = NxPenalties.Constraints.orthogonality(logprobs, opts)

    metrics =
      if tracing?(logprobs) do
        %{}
      else
        %{"orthogonality" => Nx.to_number(penalty)}
      end

    {penalty, metrics}
  end

  @impl true
  def name, do: "orthogonality"

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
