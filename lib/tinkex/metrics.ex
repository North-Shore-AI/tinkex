defmodule Tinkex.Metrics do
  @moduledoc """
  Lightweight metrics aggregation for Tinkex telemetry events.

  The server subscribes to `[:tinkex, :http, :request, :stop]` and keeps
  counters for successes/failures plus latency histograms. Public helpers allow
  recording custom counters, gauges, and histograms for experiment tracking.
  """

  use GenServer

  @http_stop_event [:tinkex, :http, :request, :stop]
  @default_latency_buckets [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]
  @default_histogram_max_samples 1_000

  @type metric_name :: atom()

  @type histogram_snapshot :: %{
          count: non_neg_integer(),
          mean: float() | nil,
          min: float() | nil,
          max: float() | nil,
          p50: float() | nil,
          p95: float() | nil,
          p99: float() | nil
        }

  @type snapshot :: %{
          counters: %{optional(metric_name()) => number()},
          gauges: %{optional(metric_name()) => number()},
          histograms: %{optional(metric_name()) => histogram_snapshot()}
        }

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Start the metrics server.

  Options:
    * `:enabled` - turn metrics on/off (defaults to application env, true)
    * `:latency_buckets` - histogram buckets in milliseconds
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increment a counter metric by the provided delta (default: 1).
  """
  @spec increment(metric_name(), number()) :: :ok
  def increment(name, delta \\ 1) do
    GenServer.cast(__MODULE__, {:counter, name, delta})
    :ok
  end

  @doc """
  Set a gauge to a specific value.
  """
  @spec set_gauge(metric_name(), number()) :: :ok
  def set_gauge(name, value) do
    GenServer.cast(__MODULE__, {:gauge, name, value})
    :ok
  end

  @doc """
  Record a histogram sample (value in milliseconds).
  """
  @spec record_histogram(metric_name(), number()) :: :ok
  def record_histogram(name, value_ms) do
    GenServer.cast(__MODULE__, {:histogram, name, value_ms})
    :ok
  end

  @doc """
  Return a snapshot of counters, gauges, and histograms.
  """
  @spec snapshot() :: snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc """
  Reset all metrics state.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Block until the server has processed all prior casts.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Telemetry handler entrypoint.
  """
  @spec handle_event([atom()], map(), map(), term()) :: :ok
  def handle_event(@http_stop_event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:http_stop, measurements, metadata})
    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @impl true
  def init(opts) do
    enabled? = Keyword.get(opts, :enabled, Application.get_env(:tinkex, :metrics_enabled, true))

    latency_buckets =
      Keyword.get(
        opts,
        :latency_buckets,
        Application.get_env(:tinkex, :metrics_latency_buckets, @default_latency_buckets)
      )

    histogram_max_samples =
      Keyword.get(
        opts,
        :histogram_max_samples,
        Application.get_env(
          :tinkex,
          :metrics_histogram_max_samples,
          @default_histogram_max_samples
        )
      )

    maybe_attach_telemetry(enabled?)

    state = %{
      enabled?: enabled?,
      latency_buckets: latency_buckets,
      histogram_max_samples: histogram_max_samples,
      counters: %{},
      gauges: %{},
      histograms: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:http_stop, _measurements, _metadata}, %{enabled?: false} = state) do
    {:noreply, state}
  end

  def handle_cast({:http_stop, measurements, metadata}, state) do
    duration_native = Map.get(measurements, :duration)
    result = Map.get(metadata, :result, :error)

    state =
      case duration_native do
        nil ->
          state

        duration ->
          duration_ms =
            duration
            |> System.convert_time_unit(:native, :microsecond)
            |> Kernel./(1_000)

          state
          |> increment_counter(:tinkex_requests_total, 1)
          |> increment_counter(counter_for_result(result), 1)
          |> record_histogram_value(:tinkex_request_duration_ms, duration_ms)
      end

    {:noreply, state}
  end

  def handle_cast({:counter, name, delta}, state) do
    {:noreply, increment_counter(state, name, delta)}
  end

  def handle_cast({:gauge, name, value}, state) do
    {:noreply, put_in(state.gauges[name], value)}
  end

  def handle_cast({:histogram, name, value_ms}, state) do
    {:noreply, record_histogram_value(state, name, value_ms)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  def handle_call(:reset, _from, state) do
    empty = %{state | counters: %{}, gauges: %{}, histograms: %{}}
    {:reply, :ok, empty}
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, state}
  end

  defp maybe_attach_telemetry(false), do: :ok

  defp maybe_attach_telemetry(true) do
    handler_id = "tinkex-metrics"

    case :telemetry.attach_many(handler_id, [@http_stop_event], &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp increment_counter(state, name, delta) do
    updated =
      state.counters
      |> Map.get(name, 0)
      |> Kernel.+(delta)

    put_in(state.counters[name], updated)
  end

  defp counter_for_result(:ok), do: :tinkex_requests_success
  defp counter_for_result(_other), do: :tinkex_requests_failure

  defp record_histogram_value(state, name, value_ms) when is_number(value_ms) do
    hist =
      Map.get(state.histograms, name) ||
        new_histogram(state.latency_buckets, state.histogram_max_samples)

    idx = bucket_index(hist.buckets, value_ms)
    counts = List.update_at(hist.counts, idx, &(&1 + 1))

    values =
      [value_ms | hist.values]
      |> Enum.take(hist.max_samples)

    updated =
      hist
      |> Map.put(:counts, counts)
      |> Map.update!(:count, &(&1 + 1))
      |> Map.update!(:sum, &(&1 + value_ms))
      |> Map.put(:values, values)
      |> update_min(value_ms)
      |> update_max(value_ms)

    put_in(state.histograms[name], updated)
  end

  defp record_histogram_value(state, _name, _value_ms), do: state

  defp new_histogram(buckets, max_samples) do
    %{
      buckets: buckets,
      counts: for(_ <- 0..length(buckets), do: 0),
      count: 0,
      sum: 0.0,
      values: [],
      max_samples: max_samples,
      min: nil,
      max: nil
    }
  end

  defp bucket_index(buckets, value_ms) do
    buckets
    |> Enum.find_index(fn upper -> value_ms <= upper end)
    |> case do
      nil -> length(buckets)
      idx -> idx
    end
  end

  defp update_min(hist, value_ms) do
    case hist.min do
      nil -> Map.put(hist, :min, value_ms)
      current when value_ms < current -> Map.put(hist, :min, value_ms)
      _ -> hist
    end
  end

  defp update_max(hist, value_ms) do
    case hist.max do
      nil -> Map.put(hist, :max, value_ms)
      current when value_ms > current -> Map.put(hist, :max, value_ms)
      _ -> hist
    end
  end

  defp build_snapshot(state) do
    histograms =
      Enum.into(state.histograms, %{}, fn {name, hist} ->
        {name, histogram_stats(hist)}
      end)

    %{
      counters: state.counters,
      gauges: state.gauges,
      histograms: histograms
    }
  end

  defp histogram_stats(%{count: 0} = _hist) do
    %{
      count: 0,
      mean: nil,
      min: nil,
      max: nil,
      p50: nil,
      p95: nil,
      p99: nil
    }
  end

  defp histogram_stats(%{count: count, sum: sum, values: values} = hist) do
    mean = sum / count
    sorted = Enum.sort(values)

    %{
      count: count,
      mean: mean,
      min: hist.min,
      max: hist.max,
      p50: percentile_from_values(sorted, 50),
      p95: percentile_from_values(sorted, 95),
      p99: percentile_from_values(sorted, 99)
    }
  end

  defp percentile_from_values([], _pct), do: nil

  defp percentile_from_values(values, 50) do
    count = length(values)

    if rem(count, 2) == 1 do
      Enum.at(values, div(count, 2))
    else
      upper = div(count, 2)
      lower = upper - 1
      (Enum.at(values, lower) + Enum.at(values, upper)) / 2
    end
  end

  defp percentile_from_values(values, pct) do
    count = length(values)

    rank =
      count
      |> Kernel.*(pct)
      |> Kernel./(100)
      |> Float.ceil()
      |> trunc()

    idx = max(rank - 1, 0)
    Enum.at(values, idx)
  end
end
