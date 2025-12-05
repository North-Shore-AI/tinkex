defmodule Tinkex.Regularizers.Entropy do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  Entropy regularizer adapter using NxPenalties.

  `:mode` controls whether entropy is encouraged (`:maximize`) or discouraged
  (`:minimize`). The adapter maps these to NxPenalties' `:penalty`/`:bonus`
  modes so the returned tensor can be used directly as a loss term.
  """

  @impl true
  def compute(_data, logprobs, opts \\ []) do
    mode = Keyword.get(opts, :mode, :minimize)
    reduction = Keyword.get(opts, :reduction, :mean)
    normalize = Keyword.get(opts, :normalize, false)
    temperature = Keyword.get(opts, :temperature, 1.0)

    penalty_mode =
      case mode do
        :maximize -> :penalty
        :minimize -> :bonus
        other -> raise ArgumentError, "Unsupported entropy mode: #{inspect(other)}"
      end

    value =
      NxPenalties.Divergences.entropy(logprobs,
        mode: penalty_mode,
        reduction: reduction,
        normalize: normalize,
        temperature: temperature
      )

    metrics =
      if tracing?(logprobs) do
        %{}
      else
        %{
          "entropy" => Nx.to_number(value),
          "mode" => Atom.to_string(mode),
          "temperature" => temperature
        }
      end

    {value, metrics}
  end

  @impl true
  def name, do: "entropy"

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
