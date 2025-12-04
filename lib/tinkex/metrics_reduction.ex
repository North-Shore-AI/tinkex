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
    "unique" => :unique,
    "hash_unordered" => :hash_unordered
  }

  @doc """
  Reduce metrics from chunked forward/backward results.

  * Weights use the number of `loss_fn_outputs` for each chunk.
  * Unknown suffixes fall back to the weighted mean reducer.
  * `:unique` metrics retain every value by emitting suffixed keys (`key_2`, `key_3`, ...).
  * Weighted reducers return `0.0` when the total weight is `0`.
  * `:hash_unordered` returns an **integer** hash (not a float) for order-insensitive
    identity checks. Suitable for verifying batch composition across distributed chunks.
  """
  @spec reduce([ForwardBackwardOutput.t()]) :: metrics()
  def reduce([]), do: %{}

  def reduce([first | _] = results) do
    metrics_with_weights = build_metrics_with_weights(results)
    first_metrics = first.metrics || %{}

    first_metrics
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc -> reduce_key(key, metrics_with_weights, acc) end)
  end

  defp build_metrics_with_weights(results) do
    Enum.map(results, fn %ForwardBackwardOutput{} = result ->
      metrics = result.metrics || %{}
      outputs = result.loss_fn_outputs || []
      weight = length(outputs)
      {metrics, weight}
    end)
  end

  defp reduce_key(key, metrics_with_weights, acc) do
    metrics_with_weights
    |> collect_pairs(key)
    |> merge_reduction(key, acc)
  end

  defp collect_pairs(metrics_with_weights, key) do
    Enum.reduce(metrics_with_weights, [], fn {metrics, weight}, pair_acc ->
      case Map.fetch(metrics, key) do
        {:ok, value} -> [{value, weight} | pair_acc]
        :error -> pair_acc
      end
    end)
  end

  defp merge_reduction([], _key, acc), do: acc

  defp merge_reduction(pairs, key, acc) do
    {values, weights} =
      pairs
      |> Enum.reverse()
      |> Enum.unzip()

    reducer_key = metric_suffix(key)
    reduced = apply_reduction(key, reducer_key, values, weights)
    Map.merge(acc, reduced)
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

  defp apply_reduction(key, "hash_unordered", values, _weights) do
    %{key => execute_reducer(:hash_unordered, values, [])}
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

  defp execute_reducer(:hash_unordered, values, _weights) do
    # Order-insensitive hash: sort values numerically, then hash.
    # Python uses: hash(tuple(sorted(values))) - we use :erlang.phash2 for consistency.
    #
    # NOTE: Returns an integer hash (not a float like other reducers). This is
    # intentional for identity/fingerprinting use cases. Consumers should be
    # aware that :hash_unordered metrics are integers used for equality checks,
    # not for arithmetic aggregation.
    values
    |> Enum.sort()
    |> :erlang.phash2()
  end
end
