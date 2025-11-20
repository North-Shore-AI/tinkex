defmodule Tinkex.MetricsReduction do
  @moduledoc """
  Metric reduction for chunked forward/backward results.

  Mirrors Python's `chunked_fwdbwd_helpers._metrics_reduction` helper by
  reducing metrics based on the suffix that comes after the last `:` in the
  metric name. Only metrics present in the first chunk are considered, and keys
  missing from later chunks are ignored (they are not treated as zero).
  """

  alias Tinkex.Types.ForwardBackwardOutput

  @type metrics :: %{String.t() => number()}

  @reducers %{
    "sum" => :sum,
    "min" => :min,
    "max" => :max,
    "mean" => :mean,
    "slack" => :slack,
    "unique" => :unique
  }

  @doc """
  Reduce metrics from chunked forward/backward results.

  * Weights use the number of `loss_fn_outputs` for each chunk.
  * Unknown suffixes fall back to the weighted mean reducer.
  * `:unique` metrics retain every value by emitting suffixed keys (`key_2`, `key_3`, ...).
  * Weighted reducers return `0.0` when the total weight is `0`.
  """
  @spec reduce([ForwardBackwardOutput.t()]) :: metrics()
  def reduce([]), do: %{}

  def reduce([first | _] = results) do
    metrics_with_weights =
      Enum.map(results, fn %ForwardBackwardOutput{} = result ->
        metrics = result.metrics || %{}
        outputs = result.loss_fn_outputs || []
        weight = length(outputs)
        {metrics, weight}
      end)

    first_metrics = first.metrics || %{}

    first_metrics
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      pairs =
        Enum.reduce(metrics_with_weights, [], fn {metrics, weight}, pair_acc ->
          case Map.fetch(metrics, key) do
            {:ok, value} -> [{value, weight} | pair_acc]
            :error -> pair_acc
          end
        end)

      case pairs do
        [] ->
          acc

        _ ->
          {values, weights} =
            pairs
            |> Enum.reverse()
            |> Enum.unzip()

          reducer_key = metric_suffix(key)
          reduced = apply_reduction(key, reducer_key, values, weights)
          Map.merge(acc, reduced)
      end
    end)
  end

  defp metric_suffix(key) when is_binary(key) do
    key
    |> String.split(":")
    |> List.last()
  end

  defp apply_reduction(key, "unique", values, _weights) do
    [first | rest] = values

    Enum.with_index(rest, 2)
    |> Enum.reduce(%{key => first}, fn {value, idx}, acc ->
      Map.put(acc, "#{key}_#{idx}", value)
    end)
  end

  defp apply_reduction(key, suffix, values, weights) do
    reducer = Map.get(@reducers, suffix, :mean)
    reduced_value = execute_reducer(reducer, values, weights)
    %{key => reduced_value}
  end

  defp execute_reducer(:sum, values, _weights), do: Enum.sum(values)
  defp execute_reducer(:min, values, _weights), do: Enum.min(values)
  defp execute_reducer(:max, values, _weights), do: Enum.max(values)

  defp execute_reducer(:mean, values, weights) do
    total_weight = Enum.sum(weights)

    weighted_sum =
      Enum.zip(values, weights)
      |> Enum.reduce(0.0, fn {value, weight}, acc -> acc + value * weight end)

    if total_weight > 0 do
      weighted_sum / total_weight
    else
      0.0
    end
  end

  defp execute_reducer(:slack, values, weights) do
    total_weight = Enum.sum(weights)

    if total_weight > 0 do
      Enum.max(values) - execute_reducer(:mean, values, weights)
    else
      0.0
    end
  end

  defp execute_reducer(:unique, _values, _weights),
    do: raise("unique reducer should be handled separately")
end
