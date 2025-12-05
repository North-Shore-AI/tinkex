defmodule Tinkex.Regularizers.KLDivergence do
  @behaviour Tinkex.Regularizer

  @moduledoc """
  KL divergence adapter against a reference distribution using NxPenalties.

  Requires reference logprobs provided via opts, data field, or a callback.
  """

  alias Tinkex.Types.TensorData

  @impl true
  def compute(data, logprobs, opts \\ []) do
    if tracing?(logprobs) do
      zero = Nx.tensor(0.0, type: Nx.type(logprobs))
      {zero, %{}}
    else
      reference = resolve_reference!(data, opts)
      {logprobs, reference} = validate_shapes!(logprobs, reference)
      reduction = Keyword.get(opts, :reduction, :mean)
      direction = Keyword.get(opts, :direction, :forward)
      symmetric = Keyword.get(opts, :symmetric, false)

      value =
        NxPenalties.Divergences.kl_divergence(logprobs, reference,
          reduction: reduction,
          direction: direction,
          symmetric: symmetric
        )

      per_sample =
        NxPenalties.Divergences.kl_divergence(logprobs, reference,
          reduction: :none,
          direction: direction,
          symmetric: symmetric
        )

      metrics =
        if tracing?(logprobs) do
          %{}
        else
          %{
            "kl_divergence" => Nx.to_number(value),
            "kl_direction" => Atom.to_string(direction),
            "kl_symmetric" => symmetric,
            "kl_max" => Nx.to_number(Nx.reduce_max(per_sample)),
            "kl_min" => Nx.to_number(Nx.reduce_min(per_sample))
          }
        end

      {value, metrics}
    end
  end

  @impl true
  def name, do: "kl_divergence"

  defp resolve_reference!(data, opts) do
    cond do
      opts[:reference_logprobs] ->
        to_tensor(opts[:reference_logprobs])

      opts[:reference_field] ->
        fetch_field!(data, opts[:reference_field])

      opts[:compute_reference] ->
        data
        |> opts[:compute_reference].()
        |> to_tensor()

      true ->
        raise ArgumentError,
              "KLDivergence requires a reference via :reference_logprobs, :reference_field, or :compute_reference"
    end
  end

  defp fetch_field!(data, key) do
    data
    |> List.first()
    |> case do
      nil -> raise ArgumentError, "Empty data; cannot resolve reference field #{inspect(key)}"
      %{loss_fn_inputs: inputs} -> inputs |> Map.fetch!(key) |> to_tensor()
      other -> raise ArgumentError, "Expected datum with loss_fn_inputs, got: #{inspect(other)}"
    end
  end

  defp validate_shapes!(a, b) do
    if Nx.shape(a) != Nx.shape(b) do
      raise ArgumentError,
            "Shape mismatch in KL divergence. logprobs: #{inspect(Nx.shape(a))}, reference: #{inspect(Nx.shape(b))}"
    end

    {a, b}
  end

  defp to_tensor(%TensorData{} = td), do: TensorData.to_nx(td)
  defp to_tensor(%Nx.Tensor{} = t), do: t

  defp tracing?(%Nx.Tensor{data: %Nx.Defn.Expr{}}), do: true
  defp tracing?(_), do: false
end
