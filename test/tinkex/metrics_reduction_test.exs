defmodule Tinkex.MetricsReductionTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureLog

  alias Tinkex.Future.Combiner
  alias Tinkex.MetricsReduction
  alias Tinkex.Types.ForwardBackwardOutput

  describe "reduce/1" do
    test "returns empty map for empty results" do
      assert MetricsReduction.reduce([]) == %{}
    end

    test "weighted mean uses loss_fn_output counts" do
      results = [
        fb_output(%{"loss:mean" => 1.0}, outputs: 1),
        fb_output(%{"loss:mean" => 3.0}, outputs: 3),
        fb_output(%{"loss:mean" => 5.0}, outputs: 2)
      ]

      reduced = MetricsReduction.reduce(results)
      assert_in_delta(reduced["loss:mean"], 20 / 6, 1.0e-6)
    end

    test "supports sum/min/max/slack reducers" do
      results = [
        fb_output(
          %{
            "tokens_processed:sum" => 100,
            "latency:max" => 1.1,
            "temperature:min" => 0.3,
            "drift:slack" => 1.0
          },
          outputs: 2
        ),
        fb_output(
          %{
            "tokens_processed:sum" => 50,
            "latency:max" => 1.5,
            "temperature:min" => 0.1,
            "drift:slack" => 3.0
          },
          outputs: 1
        ),
        fb_output(
          %{
            "tokens_processed:sum" => 75,
            "latency:max" => 1.2,
            "temperature:min" => 0.2,
            "drift:slack" => 5.0
          },
          outputs: 3
        )
      ]

      reduced = MetricsReduction.reduce(results)

      assert reduced["tokens_processed:sum"] == 225
      assert reduced["latency:max"] == 1.5
      assert reduced["temperature:min"] == 0.1
      assert_in_delta(reduced["drift:slack"], 5.0 - 20 / 6, 1.0e-6)
    end

    test "unique metrics keep suffixed copies" do
      results = [
        fb_output(%{"clock_cycle:unique" => 10.0}),
        fb_output(%{"clock_cycle:unique" => 11.0}),
        fb_output(%{"clock_cycle:unique" => 12.0})
      ]

      reduced = MetricsReduction.reduce(results)

      assert reduced["clock_cycle:unique"] == 10.0
      assert reduced["clock_cycle:unique_2"] == 11.0
      assert reduced["clock_cycle:unique_3"] == 12.0
    end

    test "unknown suffix falls back to weighted mean" do
      results = [
        fb_output(%{"efficiency:median" => 1.0}, outputs: 1),
        fb_output(%{"efficiency:median" => 3.0}, outputs: 3)
      ]

      reduced = MetricsReduction.reduce(results)
      assert_in_delta(reduced["efficiency:median"], 2.5, 1.0e-6)
    end

    test "first chunk defines the metric set" do
      results = [
        fb_output(%{"loss:mean" => 1.0}, outputs: 1),
        fb_output(%{"loss:mean" => 3.0, "extra_metric:sum" => 42.0}, outputs: 1)
      ]

      reduced = MetricsReduction.reduce(results)

      assert Map.has_key?(reduced, "loss:mean")
      refute Map.has_key?(reduced, "extra_metric:sum")
    end

    test "missing metrics in later chunks are ignored (not zero-filled)" do
      results = [
        fb_output(%{"accuracy:mean" => 0.8}, outputs: 2),
        fb_output(%{"something_else:sum" => 10}, outputs: 4),
        fb_output(%{"accuracy:mean" => 0.6}, outputs: 1)
      ]

      reduced = MetricsReduction.reduce(results)

      # Only the first and third chunks contribute (2 + 1 weights).
      assert_in_delta(reduced["accuracy:mean"], 2.2 / 3, 1.0e-6)
      refute Map.has_key?(reduced, "something_else:sum")
    end

    test "weighted reducers return 0.0 when total weight is zero" do
      results = [
        fb_output(%{"loss:mean" => 5.0, "drift:slack" => 1.0}, outputs: 0),
        fb_output(%{"loss:mean" => 15.0, "drift:slack" => 2.0}, outputs: 0)
      ]

      reduced = MetricsReduction.reduce(results)

      assert reduced["loss:mean"] == 0.0
      assert reduced["drift:slack"] == 0.0
    end
  end

  describe "combine_forward_backward_results/1" do
    test "flattens outputs and applies metrics reduction" do
      results = [
        fb_output(%{"loss:mean" => 1.0, "tokens:sum" => 10}, outputs: 2),
        fb_output(%{"loss:mean" => 3.0, "tokens:sum" => 5}, outputs: 1)
      ]

      combined = Combiner.combine_forward_backward_results(results)

      assert combined.loss_fn_output_type == "tensor"
      assert combined.loss_fn_outputs == Enum.flat_map(results, & &1.loss_fn_outputs)
      assert combined.metrics == MetricsReduction.reduce(results)
    end

    test "logs warning when loss_fn_output_type differs across chunks" do
      results = [
        fb_output(%{"loss:mean" => 1.0}, outputs: 1, type: "per-example"),
        fb_output(%{"loss:mean" => 3.0}, outputs: 1, type: "per-token")
      ]

      log =
        capture_log(fn ->
          combined = Combiner.combine_forward_backward_results(results)
          assert combined.loss_fn_output_type == "per-example"
        end)

      assert log =~ "mixed loss_fn_output_type"
    end
  end

  defp fb_output(metrics, opts \\ []) do
    count = Keyword.get(opts, :outputs, 1)
    type = Keyword.get(opts, :type, "tensor")

    %ForwardBackwardOutput{
      loss_fn_output_type: type,
      metrics: metrics,
      loss_fn_outputs: build_outputs(count)
    }
  end

  defp build_outputs(count) when is_integer(count) and count > 0 do
    Enum.map(1..count, fn idx -> %{value: idx} end)
  end

  defp build_outputs(_count), do: []
end
