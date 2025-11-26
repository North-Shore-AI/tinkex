# Tinkex v0.1.6 Enhancement Quick Start

**For the Development Team**

This is a quick reference for implementing the v0.1.6 enhancements. For full details, see `ENHANCEMENT_DESIGN.md` and `IMPLEMENTATION_STATUS.md`.

---

## Prerequisites

### Install Elixir in WSL

The Elixir runtime is currently missing from the `ubuntu-dev` WSL distribution. Install it first:

```bash
# Open WSL terminal
wsl -d ubuntu-dev

# Install Erlang and Elixir
sudo apt update
sudo apt install -y erlang elixir

# Verify installation
elixir --version
# Should show: Elixir 1.14+ (Erlang/OTP 25+)

# Navigate to project
cd /home/home/p/g/North-Shore-AI/tinkex

# Install dependencies
mix deps.get

# Run tests to verify setup
mix test
```

---

## What We're Building

Three major enhancements for v0.1.6:

### 1. Circuit Breaker Pattern

**File:** `lib/tinkex/circuit_breaker.ex`

Prevents cascading failures by detecting error patterns and "opening the circuit" to fail fast.

**Key API:**
```elixir
CircuitBreaker.for_key({base_url, api_key})
CircuitBreaker.check_and_call(breaker, fn -> ... end)
CircuitBreaker.record_success(breaker)
CircuitBreaker.record_failure(breaker)
```

**States:** closed → open → half_open → closed

### 2. Request Batching

**Files:**
- Extend `lib/tinkex/training_client.ex`
- Extend `lib/tinkex/api/training.ex`

Reduces round trips by batching multiple requests into one HTTP call.

**Key API:**
```elixir
TrainingClient.forward_backward_batch(client, [
  {data1, :cross_entropy, []},
  {data2, :cross_entropy, []}
])
```

**Performance:** 40-70% reduction in training time for bulk operations

### 3. Metrics Aggregation

**File:** `lib/tinkex/metrics.ex`

Collects and aggregates telemetry into useful statistics (P50, P95, P99, etc.)

**Key API:**
```elixir
Metrics.increment(:tinkex_requests_total, 1)
Metrics.record_histogram(:tinkex_request_duration_ms, 45)
Metrics.get_all_metrics()  # For dashboards
```

---

## Implementation Order

Follow this sequence (dependencies matter):

### Week 1: Circuit Breaker

**Priority:** HIGH (most important)

**Steps:**
1. Create `lib/tinkex/circuit_breaker.ex` with GenServer
2. Add ETS registry (`:tinkex_circuit_breakers`)
3. Integrate into `lib/tinkex/http_client.ex`
4. Add telemetry events
5. Write tests (`test/tinkex/circuit_breaker_test.exs`)
6. Update docs

**Test Command:**
```bash
mix test test/tinkex/circuit_breaker_test.exs
```

### Week 2: Request Batching

**Priority:** MEDIUM

**Steps:**
1. Add `forward_backward_batch/3` to TrainingClient
2. Add `optim_step_batch/2` to TrainingClient
3. Extend Training API with batch endpoints
4. Write tests (`test/tinkex/training_client_batch_test.exs`)
5. Add example (`examples/batch_training.exs`)

**Test Command:**
```bash
mix test test/tinkex/training_client_batch_test.exs
mix test test/integration/batch_training_workflow_test.exs
```

### Week 3: Metrics Aggregation

**Priority:** MEDIUM

**Steps:**
1. Create `lib/tinkex/metrics.ex` with GenServer
2. Add ETS table (`:tinkex_metrics`)
3. Implement counter/gauge/histogram/summary
4. Attach telemetry handlers in Application
5. Write tests (`test/tinkex/metrics_test.exs`)
6. Add monitoring guide

**Test Command:**
```bash
mix test test/tinkex/metrics_test.exs
```

---

## Code Templates

### Circuit Breaker Skeleton

```elixir
defmodule Tinkex.CircuitBreaker do
  use GenServer

  # State: :closed | :open | :half_open

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def for_key(key) do
    # Get or create breaker for key
  end

  def check_and_call(breaker, fun) do
    case get_state(breaker) do
      :closed -> execute_and_track(breaker, fun)
      :open -> {:error, :circuit_open}
      :half_open -> execute_probe(breaker, fun)
    end
  end

  def record_success(breaker) do
    GenServer.cast(breaker, :success)
  end

  def record_failure(breaker) do
    GenServer.cast(breaker, :failure)
  end

  # GenServer callbacks
  @impl true
  def init(opts) do
    state = %{
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      config: parse_config(opts)
    }
    {:ok, state}
  end

  @impl true
  def handle_cast(:success, state) do
    # Transition to closed, reset failure count
    {:noreply, %{state | state: :closed, failure_count: 0}}
  end

  @impl true
  def handle_cast(:failure, state) do
    new_count = state.failure_count + 1

    if new_count >= state.config.failure_threshold do
      # Open the circuit
      :telemetry.execute([:tinkex, :circuit_breaker, :open], %{}, %{})
      {:noreply, %{state | state: :open, last_failure_time: now()}}
    else
      {:noreply, %{state | failure_count: new_count}}
    end
  end

  # Implement remaining callbacks...
end
```

### Batch API Template

```elixir
# In lib/tinkex/training_client.ex

@doc """
Batch multiple forward-backward requests.

## Examples

    batched = [
      {data1, :cross_entropy, []},
      {data2, :cross_entropy, []}
    ]

    {:ok, task} = TrainingClient.forward_backward_batch(client, batched)
    {:ok, [result1, result2]} = Task.await(task)
"""
@spec forward_backward_batch(t(), [{data, loss_fn, opts}], keyword()) ::
  {:ok, Task.t()} | {:error, Error.t()}
def forward_backward_batch(client, requests, opts \\ []) do
  {:ok, Task.async(fn ->
    GenServer.call(client, {:forward_backward_batch, requests, opts}, :infinity)
  end)}
end

# Add handle_call clause
@impl true
def handle_call({:forward_backward_batch, requests, opts}, from, state) do
  # Assemble batch request
  # Send to API
  # Distribute responses
  # Return results
end
```

### Metrics Template

```elixir
defmodule Tinkex.Metrics do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def increment(metric_name, value \\ 1) do
    :ets.update_counter(:tinkex_metrics, {:counter, metric_name}, value, {nil, 0})
    :ok
  end

  def set_gauge(metric_name, value) do
    :ets.insert(:tinkex_metrics, {{:gauge, metric_name}, value})
    :ok
  end

  def record_histogram(metric_name, value) do
    GenServer.cast(__MODULE__, {:histogram, metric_name, value})
  end

  def get_all_metrics do
    # Collect from ETS
    # Compute percentiles
    # Return structured map
  end

  # GenServer callbacks
  @impl true
  def init(_opts) do
    :ets.new(:tinkex_metrics, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:histogram, metric_name, value}, state) do
    # Update histogram buckets
    # Increment count, update sum
    {:noreply, state}
  end
end
```

---

## Testing Checklist

### Circuit Breaker Tests

- [ ] Closed → Open transition (after threshold failures)
- [ ] Open → Half-Open transition (after timeout)
- [ ] Half-Open → Closed transition (on success)
- [ ] Half-Open → Open transition (on failure)
- [ ] Fast-fail during Open state (<1ms)
- [ ] Telemetry events emitted
- [ ] Per-tenant isolation

### Batch Tests

- [ ] Batch request assembly
- [ ] Response distribution to callers
- [ ] Empty batch handling
- [ ] Oversized batch rejection
- [ ] Partial failure handling
- [ ] Telemetry events emitted

### Metrics Tests

- [ ] Counter increments
- [ ] Gauge updates
- [ ] Histogram percentile accuracy (P50, P95, P99)
- [ ] Summary statistics (mean, stddev)
- [ ] Reset functionality
- [ ] Concurrent access
- [ ] Telemetry integration

---

## Running All Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific module
mix test test/tinkex/circuit_breaker_test.exs

# Run integration tests only
mix test test/integration/

# Check for warnings
mix compile --warnings-as-errors

# Run static analysis
mix credo
mix dialyzer
```

---

## Version Update Checklist

Before releasing v0.1.6:

- [ ] Update `mix.exs` - Line 4: `@version "0.1.6"`
- [ ] Update `README.md` - Line 16: Version highlights
- [ ] Update `README.md` - Line 50: Installation version
- [ ] Update `CHANGELOG.md` - Add v0.1.6 section at top
- [ ] Run `mix docs` - Regenerate documentation
- [ ] Run `mix test` - All tests pass
- [ ] Run `mix compile --warnings-as-errors` - Zero warnings
- [ ] Run `MIX_ENV=prod mix escript.build` - CLI builds
- [ ] Git commit with message: "Release v0.1.6"
- [ ] Git tag: `git tag v0.1.6`

---

## Configuration Example

Add to `config/config.exs`:

```elixir
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod",

  # NEW: Circuit breaker
  circuit_breaker: [
    enabled: true,
    failure_threshold: 5,
    timeout_ms: 30_000,
    half_open_max_calls: 1
  ],

  # NEW: Metrics
  metrics: [
    enabled: true,
    snapshot_interval_ms: 60_000,
    histogram_max_size: 1000
  ]
```

---

## Troubleshooting

### "mix: command not found"

**Solution:** Install Elixir (see Prerequisites above)

### Tests fail with "module not found"

**Solution:** Run `mix deps.get` to install dependencies

### Compilation warnings

**Solution:** Fix all warnings - project targets zero warnings

### ETS table already exists error

**Solution:** Tables may persist between test runs. Use unique names or cleanup in test setup.

---

## Resources

### Full Documentation

- `ENHANCEMENT_DESIGN.md` - Complete architectural design (25 pages)
- `IMPLEMENTATION_STATUS.md` - Status and roadmap (30 pages)
- Existing guides in `docs/guides/`

### External References

- [Circuit Breaker Pattern](https://martinfowler.com/bliki/CircuitBreaker.html)
- [The Tail at Scale](https://research.google/pubs/pub40801/) - Google paper on latency
- [Elixir GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)
- [Telemetry Documentation](https://hexdocs.pm/telemetry)

---

## Questions?

Refer to the full design documents in `docs/20251125/`:

1. `ENHANCEMENT_DESIGN.md` - Architecture and rationale
2. `IMPLEMENTATION_STATUS.md` - Status and blockers
3. `QUICKSTART.md` - This document

---

**Good luck with the implementation!**

The design is solid, the tests are planned, and the roadmap is clear. Just need Elixir installed to proceed.
