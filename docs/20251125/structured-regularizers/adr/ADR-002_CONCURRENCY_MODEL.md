# ADR-002: Concurrency Model for Regularizer Execution

## Status

**Proposed** - November 25, 2025

## Context

Regularizer computation can be CPU-intensive (topological analysis, SMT solving) or I/O-bound (external API calls, database queries). The Tinkex SDK must efficiently execute multiple regularizers without blocking the training loop.

### Python SDK Approach

The Python implementation uses:
- `asyncio` for async regularizers
- `ThreadPoolExecutor` for CPU-bound sync callbacks (via `run_sync_in_executor`)
- Sequential execution within the event loop by default

### Elixir Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| Parallelism | GIL limits true parallelism | True parallel via BEAM schedulers |
| Async model | asyncio cooperative scheduling | Preemptive process scheduling |
| Thread pools | Explicit ThreadPoolExecutor | Implicit scheduler pools |
| Process model | Single-threaded + threads | Lightweight processes |

## Decision

We will use **Elixir's native Task-based parallelism** for regularizer execution, with the following model:

### 1. Parallel Execution by Default

Regularizers execute in parallel using `Task.async_stream/3`:

```elixir
regularizers
|> Task.async_stream(
  fn spec -> execute_one(spec, data, logprobs, opts) end,
  max_concurrency: System.schedulers_online(),
  timeout: timeout,
  on_timeout: :kill_task
)
```

**Rationale:**
- BEAM schedulers distribute work across CPU cores
- No GIL limitation - true parallelism
- Built-in timeout and error handling
- Simpler than explicit thread pool management

### 2. Sequential Execution Option

A `:parallel` option allows disabling parallelism:

```elixir
Pipeline.compute(data, logprobs, loss_fn,
  regularizers: regularizers,
  parallel: false  # Sequential execution
)
```

**Use cases:**
- Debugging regularizer interactions
- Deterministic execution order
- Resource-constrained environments

### 3. Async Regularizers via Task Return

Regularizers can return `Task.t()` for I/O-bound operations:

```elixir
%RegularizerSpec{
  fn: fn data, _logprobs ->
    Task.async(fn ->
      {:ok, resp} = HTTPoison.get(url)
      {compute_penalty(resp), %{}}
    end)
  end,
  async: true,  # Signals Task return type
  ...
}
```

**Rationale:**
- Native Elixir pattern for async work
- Executor automatically awaits when `async: true`
- Composable with other Task operations

### 4. GenServer Non-Blocking Pattern

The TrainingClient GenServer spawns a background Task for custom loss computation:

```elixir
def handle_call({:forward_backward_custom, ...}, from, state) do
  Task.start(fn ->
    result = do_computation(...)
    GenServer.reply(from, result)
  end)
  {:noreply, state}
end
```

**Rationale:**
- GenServer remains responsive to other calls
- Long-running computations don't block
- Matches existing TrainingClient pattern

### 5. No Explicit Thread Pool

Unlike Python's `run_sync_in_executor`, we do NOT create an explicit thread pool.

**Rationale:**
- BEAM's dirty schedulers handle CPU-bound work
- Elixir processes are cheaper than OS threads
- Task.async_stream provides sufficient parallelism
- Simpler mental model

## Alternatives Considered

### Alternative A: :poolboy Worker Pool

```elixir
# Rejected
:poolboy.transaction(:regularizer_pool, fn worker ->
  GenServer.call(worker, {:compute, spec, data, logprobs})
end)
```

**Why rejected:**
- Unnecessary complexity for stateless regularizers
- Task.async_stream achieves same result
- Extra dependency and configuration

### Alternative B: Broadway Pipeline

```elixir
# Rejected
Broadway.start_link(RegularizerBroadway,
  producer: [module: {RegularizerProducer, specs}],
  processors: [default: [concurrency: 10]]
)
```

**Why rejected:**
- Overkill for single-batch regularizer execution
- Designed for continuous stream processing
- Harder to await synchronous results

### Alternative C: Flow for Data Parallelism

```elixir
# Rejected
regularizers
|> Flow.from_enumerable()
|> Flow.map(&execute_one/1)
|> Enum.to_list()
```

**Why rejected:**
- Overhead for small regularizer lists (< 10 items)
- Designed for large data volumes
- Task.async_stream is simpler and sufficient

### Alternative D: GenStage Producer-Consumer

```elixir
# Rejected
{:producer, specs} -> {:consumer, results}
```

**Why rejected:**
- Over-engineered for batch computation
- Backpressure not needed (finite regularizer list)
- Synchronous result aggregation harder

## Consequences

### Positive

1. **True Parallelism**: Full use of multi-core CPUs
2. **Simplicity**: No thread pool configuration needed
3. **Fault Isolation**: Process crashes don't affect others
4. **Native Patterns**: Familiar to Elixir developers

### Negative

1. **Memory Overhead**: Each Task is a process (~2KB minimum)
   - Acceptable for typical regularizer counts (< 100)

2. **Scheduling Overhead**: Process spawn/teardown cost
   - Negligible compared to regularizer computation time

3. **No Shared State**: Can't share large data across regularizers
   - Use ETS or process dictionary if needed

### Risks

1. **Task Timeout Race**: Timeout may not clean up Nx tensors
   - Mitigation: BEAM's GC handles orphaned tensors

2. **Scheduler Saturation**: Too many concurrent Tasks
   - Mitigation: `max_concurrency` limits

3. **EXLA Device Contention**: Parallel GPU operations
   - Mitigation: Nx handles device placement

## Performance Expectations

| Scenario | Expected Behavior |
|----------|-------------------|
| 1 regularizer, sync | Equivalent to sequential |
| 5 regularizers, parallel, CPU | ~5x speedup (linear) |
| 5 regularizers, parallel, GPU | Depends on Nx batching |
| 1 async regularizer (100ms I/O) | Non-blocking wait |
| 10 regularizers, 30s timeout | All killed at timeout |

## Related Decisions

- ADR-001: Regularizer Architecture
- ADR-003: Telemetry Schema

## References

- Elixir Task documentation: https://hexdocs.pm/elixir/Task.html
- BEAM schedulers: https://www.erlang.org/doc/man/erl.html#+S
- Task.async_stream: https://hexdocs.pm/elixir/Task.html#async_stream/3
