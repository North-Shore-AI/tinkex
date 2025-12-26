defmodule Tinkex.MetricsTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    telemetry_isolation: true

  alias Supertester.TelemetryHelpers

  @http_stop_event [:tinkex, :http, :request, :stop]

  setup do
    test_id = TelemetryHelpers.get_test_id!()
    handler_id = "tinkex-metrics-test-#{test_id}"

    _ = :telemetry.detach("tinkex-metrics")

    :ok =
      :telemetry.attach(
        handler_id,
        @http_stop_event,
        fn event, measurements, metadata, _config ->
          if metadata[:supertester_test_id] == test_id do
            Tinkex.Metrics.handle_event(event, measurements, metadata, nil)
          end
        end,
        nil
      )

    assert :ok = Tinkex.Metrics.reset()

    on_exit(fn ->
      :telemetry.detach(handler_id)

      case :telemetry.attach_many(
             "tinkex-metrics",
             [@http_stop_event],
             &Tinkex.Metrics.handle_event/4,
             nil
           ) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end

      Tinkex.Metrics.reset()
    end)

    :ok
  end

  test "aggregates HTTP telemetry into counters and latency percentiles" do
    emit_http_stop(10, :ok)
    emit_http_stop(20, :ok)
    emit_http_stop(40, :error)

    assert :ok = Tinkex.Metrics.flush()

    snapshot = Tinkex.Metrics.snapshot()

    assert snapshot.counters[:tinkex_requests_total] == 3
    assert snapshot.counters[:tinkex_requests_success] == 2
    assert snapshot.counters[:tinkex_requests_failure] == 1

    latency = snapshot.histograms[:tinkex_request_duration_ms]
    assert latency.count == 3
    assert_in_delta latency.mean, 23.3, 0.5
    assert_in_delta latency.p50, 20.0, 0.1
    assert_in_delta latency.p95, 40.0, 0.1
    assert_in_delta latency.p99, 40.0, 0.1
  end

  test "supports manual counters, gauges, and histograms" do
    assert :ok = Tinkex.Metrics.increment(:custom_counter)
    assert :ok = Tinkex.Metrics.increment(:custom_counter, 2)
    assert :ok = Tinkex.Metrics.set_gauge(:inflight, 5)
    assert :ok = Tinkex.Metrics.record_histogram(:latency_ms, 5.0)
    assert :ok = Tinkex.Metrics.record_histogram(:latency_ms, 15.0)

    assert :ok = Tinkex.Metrics.flush()

    snapshot = Tinkex.Metrics.snapshot()

    assert snapshot.counters[:custom_counter] == 3
    assert snapshot.gauges[:inflight] == 5

    histogram = snapshot.histograms[:latency_ms]
    assert histogram.count == 2
    assert_in_delta histogram.mean, 10.0, 0.1
    assert_in_delta histogram.p50, 10.0, 0.1
    assert_in_delta histogram.p95, 15.0, 0.1
  end

  test "reset clears state" do
    emit_http_stop(5, :ok)
    assert :ok = Tinkex.Metrics.flush()
    assert %{counters: counters} = Tinkex.Metrics.snapshot()
    assert counters[:tinkex_requests_total] == 1

    assert :ok = Tinkex.Metrics.reset()
    assert :ok = Tinkex.Metrics.flush()

    snapshot = Tinkex.Metrics.snapshot()
    assert snapshot.counters == %{}
    assert snapshot.histograms == %{}
    assert snapshot.gauges == %{}
  end

  defp emit_http_stop(duration_ms, result) do
    native =
      duration_ms
      |> Kernel.*(1_000)
      |> System.convert_time_unit(:microsecond, :native)

    metadata = TelemetryHelpers.current_test_metadata(%{result: result})
    :telemetry.execute(@http_stop_event, %{duration: native}, metadata)
  end
end
