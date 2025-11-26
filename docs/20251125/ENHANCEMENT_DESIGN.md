# Tinkex Enhancement Design Document

**Date:** 2025-11-25
**Version:** 0.1.6
**Status:** Implementation Ready

---

## Executive Summary

This document outlines three major enhancements to the Tinkex SDK that improve production resilience, performance, and observability. These enhancements build upon the existing architecture without introducing breaking changes.

### Enhancements Overview

1. **Circuit Breaker Pattern** - Prevent cascading failures and improve API resilience
2. **Request Batching** - Optimize throughput for bulk training operations
3. **Metrics Aggregation** - Enhanced observability with statistical aggregations

---

## 1. Circuit Breaker Pattern

### Motivation

Currently, Tinkex uses a `RateLimiter` to handle 429 responses with backoff. However, when the Tinker API experiences transient failures (5xx errors, network issues), clients continue making requests that are likely to fail. This can:

- Waste client resources on doomed requests
- Exacerbate server load during incidents
- Provide poor user experience with repeated failures

A **Circuit Breaker** complements rate limiting by:
- Detecting failure patterns (not just rate limits)
- Opening the circuit after a threshold of failures
- Allowing periodic probe requests during "half-open" state
- Automatically recovering when service health improves

### Design

#### Circuit Breaker States

```
CLOSED (normal operation)
   │
   │ failure_threshold exceeded
   ↓
OPEN (failing fast)
   │
   │ timeout_ms elapsed
   ↓
HALF_OPEN (testing recovery)
   │
   ├─ success → CLOSED
   └─ failure → OPEN
```

#### State Transitions

- **CLOSED**: Normal operation. Track failure rate.
- **OPEN**: Fast-fail all requests without hitting the API. Return circuit breaker error immediately.
- **HALF_OPEN**: Allow one probe request through. Success → CLOSED, Failure → OPEN.

#### Configuration

```elixir
config :tinkex, :circuit_breaker,
  failure_threshold: 5,      # Open after 5 consecutive failures
  timeout_ms: 30_000,        # Stay open for 30 seconds
  half_open_max_calls: 1     # Allow 1 probe request in half-open
```

#### Implementation Plan

**Module:** `lib/tinkex/circuit_breaker.ex`

```elixir
defmodule Tinkex.CircuitBreaker do
  @moduledoc """
  Circuit breaker for API resilience.

  Tracks failure patterns and opens circuit to prevent cascading failures.
  Complements RateLimiter by handling service degradation beyond rate limits.
  """

  use GenServer

  @type state :: :closed | :open | :half_open
  @type key :: {String.t(), String.t()}  # {base_url, api_key}

  @spec for_key(key()) :: pid()
  @spec check_and_call(pid(), fun()) :: {:ok, term()} | {:error, :circuit_open}
  @spec record_success(pid()) :: :ok
  @spec record_failure(pid()) :: :ok
  @spec get_state(pid()) :: state()
end
```

**Key Functions:**

1. `check_and_call/2` - Check circuit state before making request
2. `record_success/1` - Record successful request, potentially close circuit
3. `record_failure/1` - Record failure, potentially open circuit
4. `get_state/1` - Query current state (for telemetry)

**State Structure:**

```elixir
%{
  state: :closed,                # :closed | :open | :half_open
  failure_count: 0,              # Consecutive failures
  last_failure_time: nil,        # Monotonic time
  config: %{
    failure_threshold: 5,
    timeout_ms: 30_000,
    half_open_max_calls: 1
  }
}
```

#### Integration Points

**HTTP Client** - Wrap requests in circuit breaker:

```elixir
# lib/tinkex/http_client.ex
defp execute_with_resilience(request, config) do
  breaker = CircuitBreaker.for_key({config.base_url, config.api_key})
  limiter = RateLimiter.for_key({config.base_url, config.api_key})

  case CircuitBreaker.check_and_call(breaker, fn ->
    RateLimiter.wait_for_backoff(limiter)
    do_http_request(request, config)
  end) do
    {:ok, {:ok, _} = success} ->
      CircuitBreaker.record_success(breaker)
      RateLimiter.clear_backoff(limiter)
      success

    {:ok, {:error, %Error{status: 429} = error}} ->
      RateLimiter.set_backoff(limiter, error.retry_after_ms || 1000)
      {:error, error}

    {:ok, {:error, %Error{status: status}}} when status >= 500 ->
      CircuitBreaker.record_failure(breaker)
      {:error, error}

    {:error, :circuit_open} ->
      {:error, Error.new(:circuit_open, "Circuit breaker is open")}
  end
end
```

#### Telemetry Events

```elixir
[:tinkex, :circuit_breaker, :state_change]  # State transitions
[:tinkex, :circuit_breaker, :open]          # Circuit opened
[:tinkex, :circuit_breaker, :half_open]     # Circuit half-opened
[:tinkex, :circuit_breaker, :closed]        # Circuit closed
[:tinkex, :circuit_breaker, :rejected]      # Request rejected (circuit open)
```

#### Testing Strategy

1. **Unit Tests** (`test/tinkex/circuit_breaker_test.exs`):
   - State transitions (closed → open → half_open → closed)
   - Failure threshold enforcement
   - Timeout behavior
   - Probe request handling

2. **Integration Tests**:
   - Simulate API failures with Bypass
   - Verify fast-fail behavior during outages
   - Test recovery after service restoration

---

## 2. Request Batching Optimization

### Motivation

Training workflows often process multiple independent data chunks sequentially. Current implementation:

```elixir
# Sequential processing - 3 round trips
forward_backward(client, chunk1)  # 100ms
forward_backward(client, chunk2)  # 100ms
forward_backward(client, chunk3)  # 100ms
# Total: 300ms
```

With batching:

```elixir
# Single batched request - 1 round trip
forward_backward_batch(client, [chunk1, chunk2, chunk3])  # 110ms
# Total: 110ms (63% reduction)
```

Benefits:
- Reduced network round trips
- Lower HTTP overhead
- Improved training throughput
- Better GPU utilization on server side

### Design

#### Batch Request API

**Public API:**

```elixir
# Batch forward-backward
{:ok, task} = TrainingClient.forward_backward_batch(client, [
  {data1, :cross_entropy, opts1},
  {data2, :cross_entropy, opts2}
])
{:ok, [result1, result2]} = Task.await(task)

# Batch optimizer steps
{:ok, task} = TrainingClient.optim_step_batch(client, [
  %AdamParams{learning_rate: 1.0e-4},
  %AdamParams{learning_rate: 1.0e-4}
])
{:ok, [resp1, resp2]} = Task.await(task)
```

#### Implementation Plan

**Module:** `lib/tinkex/api/training.ex` (extend existing)

Add batch endpoints:

```elixir
@spec forward_backward_batch([{data, loss_fn, opts}], keyword()) ::
  {:ok, [future()]} | {:error, Error.t()}

@spec optim_step_batch([OptimStepRequest.t()], keyword()) ::
  {:ok, [future()]} | {:error, Error.t()}
```

**Module:** `lib/tinkex/training_client.ex` (extend existing)

Add public batch APIs:

```elixir
@spec forward_backward_batch(t(), [{data, loss_fn, opts}], keyword()) ::
  {:ok, Task.t()} | {:error, Error.t()}

@spec optim_step_batch(t(), [AdamParams.t()], keyword()) ::
  {:ok, Task.t()} | {:error, Error.t()}
```

#### Configuration

```elixir
config :tinkex, :batching,
  enabled: true,
  max_batch_size: 10,        # Max requests per batch
  max_wait_ms: 100           # Max wait to accumulate batch
```

#### Automatic Batching (Future Enhancement)

For power users, implement automatic batching collector:

```elixir
# Transparent batching - requests within 100ms window get batched
forward_backward(client, data1)  # Queued
forward_backward(client, data2)  # Queued, batched with data1
forward_backward(client, data3)  # Queued, batched with data1+data2
# Server receives 1 batched request
```

**Not implemented in 0.1.6** - Requires careful coordination and may complicate semantics.

#### Telemetry Events

```elixir
[:tinkex, :batch, :forward_backward, :start]
[:tinkex, :batch, :forward_backward, :stop]    # Includes batch_size
[:tinkex, :batch, :optim_step, :start]
[:tinkex, :batch, :optim_step, :stop]
```

#### Testing Strategy

1. **Unit Tests** (`test/tinkex/training_client_batch_test.exs`):
   - Batch request construction
   - Response distribution
   - Error handling (partial failures)

2. **Integration Tests**:
   - End-to-end batch training workflow
   - Performance comparison (batch vs sequential)

---

## 3. Metrics Aggregation System

### Motivation

Current telemetry emits raw events but lacks aggregation. Users must manually compute:
- Request latency percentiles (P50, P95, P99)
- Success/failure rates
- Throughput metrics
- Circuit breaker state durations

An **aggregation layer** provides:
- Pre-computed statistics for dashboards
- Historical trend analysis
- Anomaly detection foundations
- Production monitoring insights

### Design

#### Metrics Types

**Counter** - Monotonically increasing values:
- `tinkex.requests.total`
- `tinkex.requests.success`
- `tinkex.requests.failure`
- `tinkex.circuit_breaker.opens`

**Gauge** - Point-in-time values:
- `tinkex.circuit_breaker.state` (0=closed, 1=open, 2=half_open)
- `tinkex.rate_limiter.backoff_ms`
- `tinkex.active_sessions`

**Histogram** - Distribution metrics:
- `tinkex.request.duration_ms` (P50, P95, P99)
- `tinkex.batch.size`
- `tinkex.future.poll_iterations`

**Summary** - Time-windowed statistics:
- `tinkex.regularizer.loss` (mean, stddev)
- `tinkex.training.loss_total`

#### Implementation Plan

**Module:** `lib/tinkex/metrics.ex`

```elixir
defmodule Tinkex.Metrics do
  @moduledoc """
  Metrics aggregation and reporting.

  Collects telemetry events and provides statistical aggregations.
  Stores metrics in ETS for lock-free reads.
  """

  use GenServer

  @type metric_name :: atom()
  @type metric_type :: :counter | :gauge | :histogram | :summary

  @spec start_link(keyword()) :: GenServer.on_start()
  @spec increment(metric_name(), number()) :: :ok
  @spec set_gauge(metric_name(), number()) :: :ok
  @spec record_histogram(metric_name(), number()) :: :ok
  @spec get_snapshot(metric_name()) :: {:ok, map()} | {:error, :not_found}
  @spec get_all_metrics() :: map()
end
```

**Histogram Implementation** - Use HdrHistogram-inspired bucketing:

```elixir
# Latency buckets (ms): 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000+
buckets = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
```

Compute percentiles via linear interpolation.

**Storage** - ETS table `:tinkex_metrics`:

```elixir
# Counter
{:counter, :tinkex_requests_total, value}

# Gauge
{:gauge, :tinkex_circuit_breaker_state, value}

# Histogram
{:histogram, :tinkex_request_duration_ms, %{
  buckets: [0, 5, 10, 50],
  counts: [100, 80, 20, 5],
  sum: 2500,
  count: 205
}}
```

#### Telemetry Attachment

Attach handlers during `Tinkex.Application.start/2`:

```elixir
:telemetry.attach_many(
  "tinkex-metrics",
  [
    [:tinkex, :http, :request, :stop],
    [:tinkex, :circuit_breaker, :state_change],
    [:tinkex, :custom_loss, :stop],
    [:tinkex, :batch, :forward_backward, :stop]
  ],
  &Tinkex.Metrics.handle_event/4,
  nil
)
```

#### Export API

```elixir
# Get snapshot for monitoring systems
metrics = Tinkex.Metrics.get_all_metrics()

%{
  counters: %{
    "tinkex.requests.total" => 1250,
    "tinkex.requests.success" => 1200,
    "tinkex.requests.failure" => 50
  },
  gauges: %{
    "tinkex.circuit_breaker.state" => 0,
    "tinkex.active_sessions" => 3
  },
  histograms: %{
    "tinkex.request.duration_ms" => %{
      p50: 45,
      p95: 120,
      p99: 250,
      mean: 58,
      count: 1250
    }
  }
}
```

#### Reset API

For testing and resets:

```elixir
Tinkex.Metrics.reset()  # Clear all metrics
Tinkex.Metrics.reset(:tinkex_requests_total)  # Clear specific metric
```

#### Telemetry Events

```elixir
[:tinkex, :metrics, :snapshot]  # Periodic snapshot (every 60s)
```

#### Configuration

```elixir
config :tinkex, :metrics,
  enabled: true,
  snapshot_interval_ms: 60_000,  # Emit snapshots every 60s
  histogram_max_size: 1000       # Max samples per histogram
```

#### Testing Strategy

1. **Unit Tests** (`test/tinkex/metrics_test.exs`):
   - Counter increments
   - Gauge updates
   - Histogram percentile calculations
   - Summary statistics
   - Reset functionality

2. **Integration Tests**:
   - Telemetry event handling
   - Metrics persistence across failures
   - Export format validation

---

## Implementation Plan

### Phase 1: Circuit Breaker (Priority: High)

**Why First?** Highest impact on production resilience. Independent of other enhancements.

**Tasks:**
1. Create `lib/tinkex/circuit_breaker.ex` with GenServer implementation
2. Add ETS table for circuit breaker registry
3. Integrate into `HTTPClient.request/3`
4. Add telemetry events
5. Write unit tests (state machine, thresholds)
6. Write integration tests (simulated outages)
7. Update documentation

**Estimated Complexity:** Medium
**Test Coverage Target:** >95%

### Phase 2: Request Batching (Priority: Medium)

**Why Second?** Performance optimization. Builds on stable base.

**Tasks:**
1. Add `forward_backward_batch/3` to `TrainingClient`
2. Add `optim_step_batch/2` to `TrainingClient`
3. Extend `Training` API module with batch endpoints
4. Add request/response mapping logic
5. Add telemetry events
6. Write unit tests (batch assembly, error handling)
7. Write integration tests (end-to-end batching)
8. Add examples (`examples/batch_training.exs`)

**Estimated Complexity:** Medium
**Test Coverage Target:** >90%

### Phase 3: Metrics Aggregation (Priority: Medium)

**Why Third?** Observability enhancement. Requires circuit breaker metrics to be meaningful.

**Tasks:**
1. Create `lib/tinkex/metrics.ex` with GenServer implementation
2. Add ETS table for metrics storage
3. Implement histogram bucketing and percentile calculations
4. Attach telemetry handlers in Application
5. Add snapshot and export APIs
6. Write unit tests (all metric types, percentiles)
7. Write integration tests (telemetry integration)
8. Update documentation with metrics guide

**Estimated Complexity:** High (percentile math)
**Test Coverage Target:** >90%

---

## Testing Strategy

### Unit Tests

Each module gets comprehensive unit tests:

```
test/tinkex/circuit_breaker_test.exs         # State machine, thresholds
test/tinkex/training_client_batch_test.exs   # Batch assembly, mapping
test/tinkex/metrics_test.exs                 # All metric types, math
```

### Integration Tests

End-to-end workflows:

```
test/integration/circuit_breaker_resilience_test.exs  # Outage simulation
test/integration/batch_training_workflow_test.exs     # Performance comparison
test/integration/metrics_collection_test.exs          # Telemetry flow
```

### Property-Based Tests

Use StreamData for:
- Histogram percentile accuracy (random samples)
- Circuit breaker state transitions (random events)
- Batch size handling (edge cases)

---

## Documentation Updates

### README.md

Add sections:
- **Circuit Breaker** - Configuration and behavior
- **Request Batching** - Performance benefits and API
- **Metrics** - Monitoring and observability

### Guides

New guide: `docs/guides/production_resilience.md`

Topics:
- Circuit breaker patterns
- Retry strategies
- Metrics collection
- Alerting recommendations

---

## Versioning

**Version:** 0.1.5 → 0.1.6

**Semantic Versioning Rationale:**
- **MINOR bump** (not PATCH) because we're adding new public APIs
- **Not MAJOR** because changes are backward-compatible
- Existing code continues to work without modifications

---

## Migration Guide

### For Existing Users

**No breaking changes!** All enhancements are opt-in or automatic:

1. **Circuit Breaker** - Automatic, configurable via config
2. **Request Batching** - New APIs, existing APIs unchanged
3. **Metrics** - Automatic collection, opt-in export

**Configuration (optional):**

```elixir
# config/config.exs
config :tinkex,
  # Circuit breaker (enabled by default)
  circuit_breaker: [
    failure_threshold: 5,
    timeout_ms: 30_000,
    half_open_max_calls: 1
  ],

  # Metrics (enabled by default)
  metrics: [
    enabled: true,
    snapshot_interval_ms: 60_000
  ]
```

---

## Future Enhancements (Out of Scope for 0.1.6)

### Automatic Batching

Transparent request batching with configurable windows. Requires:
- Request queue per client
- Batch collector process
- Careful timeout handling

**Complexity:** High
**Target:** 0.2.0

### Adaptive Circuit Breaker

Circuit breaker with dynamic thresholds based on:
- Request volume
- Error rate trends
- Time-of-day patterns

**Complexity:** Very High
**Target:** 0.3.0

### Distributed Tracing

OpenTelemetry integration for distributed tracing:
- Span creation for all operations
- Context propagation
- Trace export to Jaeger/Zipkin

**Complexity:** Medium
**Target:** 0.2.0

---

## Success Criteria

### Circuit Breaker

- [ ] All state transitions work correctly
- [ ] Fast-fail during outages (< 1ms rejection)
- [ ] Automatic recovery after timeout
- [ ] Telemetry events emitted
- [ ] Zero compilation warnings
- [ ] >95% test coverage

### Request Batching

- [ ] Batch APIs functional
- [ ] Correct response mapping
- [ ] Error handling for partial failures
- [ ] Telemetry events emitted
- [ ] Performance improvement measurable
- [ ] >90% test coverage

### Metrics Aggregation

- [ ] All metric types implemented
- [ ] Percentile calculations accurate
- [ ] Telemetry handlers attached
- [ ] Export API functional
- [ ] Zero compilation warnings
- [ ] >90% test coverage

---

## References

### Circuit Breaker Pattern

- Fowler, M. (2014). "CircuitBreaker" - martinfowler.com
- Nygard, M. (2007). "Release It!" - Pragmatic Programmers
- Netflix Hystrix documentation

### Request Batching

- Dean, J., & Barroso, L. A. (2013). "The Tail at Scale" - ACM Queue
- Google SRE Book - Chapter 21: "Handling Overload"

### Metrics Aggregation

- Prometheus documentation - Metric types
- Dropwizard Metrics library
- HdrHistogram - Gil Tene (Azul Systems)

---

## Appendix: Code Examples

### Circuit Breaker Usage

```elixir
# Automatic - no user code changes
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service)

# Circuit breaker protects all API calls automatically
{:ok, task} = Tinkex.TrainingClient.forward_backward(training, data, :cross_entropy)

case Task.await(task) do
  {:ok, result} ->
    # Success
  {:error, %Error{type: :circuit_open}} ->
    # Circuit breaker tripped - fast fail
  {:error, error} ->
    # Other error
end
```

### Request Batching Usage

```elixir
# Batch multiple forward-backward passes
batched_requests = [
  {data1, :cross_entropy, []},
  {data2, :cross_entropy, []},
  {data3, :cross_entropy, []}
]

{:ok, task} = Tinkex.TrainingClient.forward_backward_batch(
  training_client,
  batched_requests
)

{:ok, [result1, result2, result3]} = Task.await(task)

# 3x reduction in round trips!
```

### Metrics Collection Usage

```elixir
# Metrics collected automatically via telemetry
# Export for monitoring dashboard
metrics = Tinkex.Metrics.get_all_metrics()

IO.inspect(metrics.histograms["tinkex.request.duration_ms"])
# %{p50: 45, p95: 120, p99: 250, mean: 58, count: 1250}

# Track circuit breaker state
IO.inspect(metrics.gauges["tinkex.circuit_breaker.state"])
# 0 (closed), 1 (open), or 2 (half_open)

# Monitor request success rate
total = metrics.counters["tinkex.requests.total"]
success = metrics.counters["tinkex.requests.success"]
success_rate = success / total * 100
IO.puts("Success rate: #{success_rate}%")
```

---

**End of Enhancement Design Document**
