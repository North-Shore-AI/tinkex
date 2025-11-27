# Metrics

Tinkex includes a lightweight metrics system for tracking request performance, custom counters, gauges, and histograms. The `Tinkex.Metrics` server automatically collects HTTP request telemetry and provides helpers for recording custom metrics in experiments and benchmarks.

## Overview

The Metrics system is built on GenServer and Telemetry, providing:

- **Automatic HTTP request tracking**: counters for success/failure and latency histograms
- **Custom counters**: increment-based metrics for tracking events
- **Gauges**: point-in-time measurements that can be set directly
- **Histograms**: distribution tracking with percentile calculations (p50, p95, p99)
- **Zero-overhead when disabled**: metrics can be toggled off via configuration
- **Thread-safe**: all updates via GenServer casts/calls

The server starts automatically with the Tinkex application and subscribes to `[:tinkex, :http, :request, :stop]` telemetry events.

## Built-in HTTP metrics

When enabled, Tinkex automatically tracks:

### Request counters

- `:tinkex_requests_total` — total number of HTTP requests
- `:tinkex_requests_success` — requests that returned `:ok`
- `:tinkex_requests_failure` — requests that returned an error

### Request latency histogram

- `:tinkex_request_duration_ms` — end-to-end request duration in milliseconds

This histogram includes:
- **Count**: total number of requests
- **Mean**: average latency
- **Min/Max**: fastest and slowest requests
- **Percentiles**: p50 (median), p95, p99

## Custom counters

Use `Metrics.increment/2` to count events in your application:

```elixir
# Increment by 1 (default)
Tinkex.Metrics.increment(:my_custom_counter)

# Increment by a specific amount
Tinkex.Metrics.increment(:tokens_generated, 150)
Tinkex.Metrics.increment(:cache_hits, 1)
Tinkex.Metrics.increment(:errors, 1)
```

**Common use cases:**
- Track cache hits/misses
- Count successful vs failed generations
- Track tokens consumed across multiple requests
- Count specific error types

## Gauges

Gauges represent instantaneous values that can go up or down. Use `Metrics.set_gauge/2` to record the current state:

```elixir
# Track queue depth
Tinkex.Metrics.set_gauge(:queue_depth, 42)

# Track active connections
Tinkex.Metrics.set_gauge(:active_connections, 8)

# Track memory usage
{:ok, memory} = :erlang.memory(:total)
Tinkex.Metrics.set_gauge(:memory_bytes, memory)

# Track temperature parameter
Tinkex.Metrics.set_gauge(:current_temperature, 0.7)
```

**Common use cases:**
- Monitor queue depths or buffer sizes
- Track active connections or worker pools
- Record configuration values during experiments
- Monitor resource usage (memory, CPU)

Unlike counters, gauges are always set to a specific value rather than incremented.

## Histograms

Histograms track distributions of values over time. Use `Metrics.record_histogram/2` to record samples (values should be in milliseconds):

```elixir
# Record a custom latency measurement
start = System.monotonic_time(:millisecond)
result = do_some_work()
duration_ms = System.monotonic_time(:millisecond) - start
Tinkex.Metrics.record_histogram(:custom_operation_duration, duration_ms)

# Track token generation time
Tinkex.Metrics.record_histogram(:token_generation_ms, 125.5)

# Track decode latency
Tinkex.Metrics.record_histogram(:decode_latency_ms, 3.2)
```

**Histogram features:**
- Automatic bucket assignment based on configured latency buckets
- Stores up to `max_samples` individual values for percentile calculation
- Computes min, max, mean, p50, p95, p99
- Memory-bounded (older samples dropped when limit reached)

**Common use cases:**
- Track end-to-end operation latencies
- Measure token generation speed
- Monitor decode/encode times
- Track database query performance

## Getting snapshots

Call `Metrics.snapshot/0` to retrieve current metrics state:

```elixir
snapshot = Tinkex.Metrics.snapshot()

# Snapshot structure:
%{
  counters: %{
    tinkex_requests_total: 150,
    tinkex_requests_success: 145,
    tinkex_requests_failure: 5,
    my_custom_counter: 42
  },
  gauges: %{
    queue_depth: 8,
    active_connections: 4
  },
  histograms: %{
    tinkex_request_duration_ms: %{
      count: 150,
      mean: 245.3,
      min: 89.2,
      max: 1205.7,
      p50: 220.1,
      p95: 458.2,
      p99: 892.5
    }
  }
}
```

**Access specific metrics:**

```elixir
snapshot = Tinkex.Metrics.snapshot()

# Check total requests
total = snapshot.counters[:tinkex_requests_total] || 0

# Check success rate
success = snapshot.counters[:tinkex_requests_success] || 0
failure = snapshot.counters[:tinkex_requests_failure] || 0
success_rate = if total > 0, do: success / total * 100, else: 0

# Check p99 latency
latency_hist = snapshot.histograms[:tinkex_request_duration_ms]
p99_latency = latency_hist.p99
```

## Understanding latency percentiles

Percentiles tell you what percentage of requests completed faster than a given threshold:

- **p50 (median)**: 50% of requests were faster than this value
- **p95**: 95% of requests were faster than this value
- **p99**: 99% of requests were faster than this value

**Example interpretation:**

```elixir
%{
  p50: 220.1,   # Half of all requests completed in under 220ms
  p95: 458.2,   # 95% completed in under 458ms
  p99: 892.5    # 99% completed in under 892ms
}
```

High p99 values indicate "tail latency" — a small percentage of requests taking much longer than average. This is critical for understanding worst-case user experience.

## Configuration options

Configure metrics in `config/config.exs`:

```elixir
config :tinkex,
  # Enable or disable metrics collection
  metrics_enabled: true,

  # Histogram bucket boundaries in milliseconds
  # Default: [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]
  metrics_latency_buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000],

  # Maximum individual samples to keep per histogram
  # Default: 1_000
  metrics_histogram_max_samples: 2_000
```

**Configuration guide:**

### Latency buckets

Buckets define histogram boundaries. Choose values appropriate for your workload:

```elixir
# For fast operations (sub-second)
metrics_latency_buckets: [1, 5, 10, 25, 50, 100, 250, 500]

# For slow operations (multi-second)
metrics_latency_buckets: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000]

# For mixed workloads (default)
metrics_latency_buckets: [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]
```

More buckets = finer granularity but more memory usage.

### Max samples

The `max_samples` setting controls how many individual values are stored for percentile calculation:

```elixir
# Lower memory usage, less accurate percentiles
metrics_histogram_max_samples: 500

# Higher accuracy, more memory
metrics_histogram_max_samples: 5_000
```

When the limit is reached, new samples displace older ones. For production workloads with high volume, consider a lower value (500-1000). For detailed analysis, use higher values (5000-10000).

### Disabling metrics

To disable metrics entirely:

```elixir
config :tinkex, metrics_enabled: false
```

Or pass at startup:

```elixir
{:ok, _} = Tinkex.Metrics.start_link(enabled: false)
```

## Integration with experiments

Use metrics to track experiment progress and performance:

```elixir
defmodule MyExperiment do
  def run_benchmark(num_iterations) do
    # Reset metrics at start
    :ok = Tinkex.Metrics.reset()

    # Track experiment configuration
    Tinkex.Metrics.set_gauge(:experiment_iterations, num_iterations)
    Tinkex.Metrics.set_gauge(:experiment_temperature, 0.7)

    Enum.each(1..num_iterations, fn i ->
      start = System.monotonic_time(:millisecond)

      # Your experiment code
      {:ok, result} = run_single_trial(i)

      # Track custom metrics
      Tinkex.Metrics.increment(:trials_completed)
      if result.success?, do: Tinkex.Metrics.increment(:successful_trials)

      # Track trial duration
      duration = System.monotonic_time(:millisecond) - start
      Tinkex.Metrics.record_histogram(:trial_duration_ms, duration)

      # Track tokens generated
      Tinkex.Metrics.increment(:total_tokens, result.num_tokens)
    end)

    # Flush pending updates
    :ok = Tinkex.Metrics.flush()

    # Get final snapshot
    snapshot = Tinkex.Metrics.snapshot()

    # Compute experiment metrics
    total_trials = snapshot.counters[:trials_completed] || 0
    successful = snapshot.counters[:successful_trials] || 0
    success_rate = if total_trials > 0, do: successful / total_trials * 100, else: 0

    trial_stats = snapshot.histograms[:trial_duration_ms]

    IO.puts """
    Experiment complete:
      Trials: #{total_trials}
      Success rate: #{:erlang.float_to_binary(success_rate, decimals: 1)}%
      Trial duration:
        Mean: #{format_ms(trial_stats.mean)}
        p50:  #{format_ms(trial_stats.p50)}
        p95:  #{format_ms(trial_stats.p95)}
        p99:  #{format_ms(trial_stats.p99)}
      HTTP requests:
        Total: #{snapshot.counters[:tinkex_requests_total] || 0}
        Success: #{snapshot.counters[:tinkex_requests_success] || 0}
        Failure: #{snapshot.counters[:tinkex_requests_failure] || 0}
    """
  end

  defp format_ms(nil), do: "n/a"
  defp format_ms(value), do: "#{:erlang.float_to_binary(value, decimals: 2)}ms"
end
```

## Integration with benchmarks

Track comparative performance across different configurations:

```elixir
defmodule ModelComparison do
  def compare_models(models, prompt, num_runs) do
    results =
      Enum.map(models, fn model ->
        # Reset for each model
        :ok = Tinkex.Metrics.reset()

        Enum.each(1..num_runs, fn _ ->
          {:ok, _response} = sample_with_model(model, prompt)
        end)

        :ok = Tinkex.Metrics.flush()
        snapshot = Tinkex.Metrics.snapshot()

        latency = snapshot.histograms[:tinkex_request_duration_ms]

        {model, %{
          total_requests: snapshot.counters[:tinkex_requests_total] || 0,
          success_rate: calculate_success_rate(snapshot),
          mean_latency: latency.mean,
          p50_latency: latency.p50,
          p99_latency: latency.p99
        }}
      end)

    # Print comparison table
    print_comparison_table(results)
  end

  defp calculate_success_rate(snapshot) do
    total = snapshot.counters[:tinkex_requests_total] || 0
    success = snapshot.counters[:tinkex_requests_success] || 0
    if total > 0, do: success / total * 100, else: 0
  end
end
```

## Utility functions

### Reset metrics

Clear all counters, gauges, and histograms:

```elixir
:ok = Tinkex.Metrics.reset()
```

Use this between experiments or benchmark runs to start fresh.

### Flush pending updates

Block until all pending metric updates are processed:

```elixir
:ok = Tinkex.Metrics.flush()
```

This ensures all async casts have been handled before reading a snapshot. Useful for deterministic testing and experiment finalization.

## Example: end-to-end workflow

See `examples/metrics_live.exs` for a complete example:

```elixir
# Reset metrics
:ok = Tinkex.Metrics.reset()

# Run some requests (metrics collected automatically)
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: model)
{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 5)
{:ok, _response} = Task.await(task, 30_000)

# Ensure all metrics are recorded
:ok = Tinkex.Metrics.flush()

# Get snapshot
snapshot = Tinkex.Metrics.snapshot()

# Print results
IO.puts "\n=== Metrics Snapshot ==="
IO.puts "Counters:"
Enum.each(snapshot.counters, fn {name, value} ->
  IO.puts "  #{name}: #{value}"
end)

IO.puts "\nLatency (ms):"
latency = snapshot.histograms[:tinkex_request_duration_ms]
IO.puts "  count: #{latency.count}"
IO.puts "  mean:  #{:erlang.float_to_binary(latency.mean, decimals: 2)}"
IO.puts "  p50:   #{:erlang.float_to_binary(latency.p50, decimals: 2)}"
IO.puts "  p95:   #{:erlang.float_to_binary(latency.p95, decimals: 2)}"
IO.puts "  p99:   #{:erlang.float_to_binary(latency.p99, decimals: 2)}"
```

Run the example:

```bash
TINKER_API_KEY=your-key mix run examples/metrics_live.exs
```

## Best practices

1. **Reset between experiments**: Call `Metrics.reset/0` at the start of each independent run
2. **Flush before reading**: Call `Metrics.flush/0` before taking snapshots to ensure all updates are processed
3. **Choose appropriate buckets**: Match latency buckets to your expected request durations
4. **Monitor p99**: Don't just look at averages — p99 reveals tail latency issues
5. **Track custom metrics**: Use counters and histograms to track domain-specific events
6. **Use gauges for configuration**: Record experiment parameters as gauges for reproducibility
7. **Disable in production**: If metrics aren't needed, disable to reduce overhead

## What to read next

- Getting started with Tinkex: `docs/guides/getting_started.md`
- Troubleshooting common issues: `docs/guides/troubleshooting.md`
- Training loop integration: `docs/guides/training_loop.md`
- API reference: `docs/guides/api_reference.md`
