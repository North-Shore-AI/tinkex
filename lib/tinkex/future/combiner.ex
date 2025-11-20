defmodule Tinkex.Future.Combiner do
  @moduledoc """
  Helpers for combining chunked forward/backward results returned by the API.

  Training client callers rely on this module to flatten chunk responses and
  apply metric reduction identical to the Python SDK.
  """

  require Logger

  alias Tinkex.MetricsReduction
  alias Tinkex.Types.ForwardBackwardOutput

  @doc """
  Combine multiple chunked `%ForwardBackwardOutput{}` structs into a single
  struct.

  * `loss_fn_output_type` is taken from the first chunk. When later chunks
    disagree a warning is logged but the first value still wins.
  * `loss_fn_outputs` are flattened in chunk order.
  * `metrics` are merged via `Tinkex.MetricsReduction.reduce/1`.
  """
  @spec combine_forward_backward_results([ForwardBackwardOutput.t()]) ::
          ForwardBackwardOutput.t()
  def combine_forward_backward_results([]) do
    raise ArgumentError, "expected at least one ForwardBackwardOutput to combine"
  end

  def combine_forward_backward_results([first | _] = results) do
    expected_type = first.loss_fn_output_type
    warn_on_mismatched_types(results, expected_type)

    %ForwardBackwardOutput{
      loss_fn_output_type: expected_type,
      loss_fn_outputs: Enum.flat_map(results, &(&1.loss_fn_outputs || [])),
      metrics: MetricsReduction.reduce(results)
    }
  end

  defp warn_on_mismatched_types(results, expected_type) do
    results
    |> Enum.map(& &1.loss_fn_output_type)
    |> Enum.uniq()
    |> case do
      [^expected_type] ->
        :ok

      types ->
        Logger.warning(
          "combine_forward_backward_results received mixed loss_fn_output_type values: #{inspect(types)}; using #{inspect(expected_type)} from first chunk"
        )
    end
  end
end
