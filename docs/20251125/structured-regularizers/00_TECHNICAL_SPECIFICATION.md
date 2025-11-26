# Structured Regularizer Composition for Tinkex

## Technical Specification Document

**Version:** 1.0
**Date:** November 25, 2025
**Status:** Draft
**Author:** Claude Code

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Background and Motivation](#2-background-and-motivation)
3. [Requirements Analysis](#3-requirements-analysis)
4. [Architectural Overview](#4-architectural-overview)
5. [Type System Design](#5-type-system-design)
6. [API Surface](#6-api-surface)
7. [Concurrency Model](#7-concurrency-model)
8. [Telemetry and Metrics](#8-telemetry-and-metrics)
9. [Gradient Computation in Elixir](#9-gradient-computation-in-elixir)
10. [Implementation Strategy](#10-implementation-strategy)
11. [Migration Path](#11-migration-path)
12. [Testing Strategy](#12-testing-strategy)
13. [Performance Considerations](#13-performance-considerations)
14. [Security Considerations](#14-security-considerations)
15. [Open Questions](#15-open-questions)

---

## 1. Executive Summary

This specification defines the design and implementation of structured regularizer composition for the Tinkex Elixir SDK. The feature enables researchers to define multiple named regularization terms with independent weights, compute per-regularizer gradient magnitudes, and leverage Elixir's concurrency model for CPU-intensive computations.

### Key Capabilities

1. **Structured Regularizer Composition**: Define multiple named regularizers with independent weights
2. **Gradient Magnitude Tracking**: Compute per-regularizer gradient L2 norms using Nx
3. **Process-Based Execution**: Leverage Elixir processes and Task for CPU-bound regularizers
4. **Async Regularizer Support**: Native support for regularizers requiring I/O operations
5. **Structured Telemetry**: Per-regularizer metrics with Erlang telemetry integration

### Relationship to Python Implementation

This specification ports the Python SDK's structured regularizer feature (commit `22e6fc9b`) to Elixir, adapting the design to leverage:
- OTP concurrency primitives (GenServer, Task, Supervisor)
- Nx/EXLA for GPU-accelerated tensor operations
- Elixir's functional programming model
- Erlang's telemetry library for observability

---

## 2. Background and Motivation

### 2.1 Current State

Tinkex provides training capabilities through `TrainingClient`, a GenServer that coordinates:
- Forward/backward passes via `forward_backward/4`
- Forward-only inference via `forward/4`
- Optimizer steps via `optim_step/3`

The current custom loss mechanism allows researchers to:
1. Call `forward/4` to obtain logprobs as raw JSON data
2. Convert logprobs to Nx tensors via `TensorData.to_nx/1`
3. Compute custom losses using Nx operations
4. Pass gradients back via subsequent training operations

**Limitations of current approach:**

1. **Manual Composition**: Researchers must manually compose and weight multiple regularization terms within a single custom loss function
2. **No Structured Telemetry**: Individual regularizer contributions are not tracked separately
3. **Gradient Tracking Absent**: No built-in mechanism to compute per-regularizer gradient magnitudes
4. **Synchronous Execution**: No framework support for parallel regularizer execution

### 2.2 Research Workflows Requiring This Feature

Research projects increasingly require multiple regularization terms with different conceptual purposes:

| Regularizer Type | Purpose | Typical Computation |
|-----------------|---------|---------------------|
| **Sparsity** (L1/L2) | Encourage peaked predictions | Simple tensor operations |
| **Entropy** | Promote diversity | Probability computations |
| **Topological Consistency** | Structural constraints | Persistent homology (CPU-intensive) |
| **External Validation** | Knowledge base consistency | HTTP/database queries (I/O-bound) |
| **Fairness** | Demographic parity | Statistical tests |
| **Logical Consistency** | Formal verification | SMT solver calls (CPU-intensive) |

Each requires:
- Separate hyperparameter tuning
- Independent ablation studies
- Gradient contribution analysis
- Different execution characteristics (CPU-bound vs I/O-bound)

### 2.3 Design Goals

1. **First-Class Research Extensibility**: Promote custom loss from implementation detail to documented feature
2. **Clean Composition Model**: Express multiple regularizers declaratively
3. **OTP-Native Concurrency**: Leverage Elixir's process model for parallel execution
4. **Full Observability**: Per-regularizer telemetry with gradient tracking
5. **Backward Compatibility**: Existing code continues to work unchanged
6. **Type Safety**: Leverage Elixir's type specs and dialyzer for compile-time checking

---

## 3. Requirements Analysis

### 3.1 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Base loss function required for all custom loss operations | P0 |
| FR-2 | Optional list of named regularizers with independent weights | P0 |
| FR-3 | Regularizers compose additively: `total = base + Σ(weight_i × reg_i)` | P0 |
| FR-4 | Per-regularizer metrics collection including custom metrics | P0 |
| FR-5 | Gradient norm tracking per regularizer via Nx.Defn | P1 |
| FR-6 | Process-based execution for CPU-bound regularizers | P1 |
| FR-7 | Async/await support for I/O-bound regularizers | P1 |
| FR-8 | Structured telemetry events for monitoring | P1 |
| FR-9 | Type specs for all public functions | P0 |
| FR-10 | Backward compatibility with existing forward/4 API | P0 |

### 3.2 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Single regularizer overhead | < 5% latency increase |
| NFR-2 | Parallel regularizer execution | Linear speedup up to CPU cores |
| NFR-3 | Memory overhead per regularizer | < 10MB |
| NFR-4 | Telemetry event latency | < 1ms |
| NFR-5 | API documentation coverage | 100% public functions |

### 3.3 Constraints

1. **Nx Compatibility**: Regularizers must work with Nx tensors (EXLA backend)
2. **GenServer Integration**: Must integrate with existing TrainingClient GenServer
3. **Telemetry Compatibility**: Events must follow existing Tinkex telemetry patterns
4. **OTP Principles**: Supervision trees, let-it-crash, no global state

---

## 4. Architectural Overview

### 4.1 Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           TrainingClient                                 │
│                         (GenServer - existing)                          │
│                                                                         │
│  ┌──────────────────────┐    ┌────────────────────────────────────┐   │
│  │    forward/4          │    │    forward_backward_custom/4       │   │
│  │    (existing)         │    │    (NEW)                           │   │
│  └──────────────────────┘    └────────────────────────────────────┘   │
│                                         │                              │
└─────────────────────────────────────────┼──────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     RegularizerPipeline (NEW)                           │
│                                                                         │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                  │
│  │  Base Loss  │   │ Regularizer │   │ Regularizer │   ...            │
│  │  Function   │   │     #1      │   │     #2      │                  │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘                  │
│         │                 │                 │                          │
│         └────────────────┬┴─────────────────┘                          │
│                          ▼                                              │
│              ┌─────────────────────┐                                   │
│              │  Loss Composition   │                                   │
│              │  & Gradient Norms   │                                   │
│              └─────────────────────┘                                   │
│                          │                                              │
└──────────────────────────┼──────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Telemetry Integration                               │
│                                                                         │
│  [:tinkex, :regularizer, :compute, :start]                             │
│  [:tinkex, :regularizer, :compute, :stop]                              │
│  [:tinkex, :regularizer, :compose, :complete]                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Module Structure

```
lib/tinkex/
├── training_client.ex          # Modified: add forward_backward_custom/4
├── regularizer/                 # NEW directory
│   ├── regularizer.ex          # Behaviour definition
│   ├── pipeline.ex             # Composition orchestration
│   ├── executor.ex             # Process-based execution
│   ├── gradient_tracker.ex     # Nx-based gradient norms
│   └── telemetry.ex            # Regularizer-specific events
├── types/
│   ├── regularizer_spec.ex     # NEW: Regularizer specification type
│   ├── regularizer_output.ex   # NEW: Per-regularizer output
│   └── custom_loss_output.ex   # NEW: Structured metrics output
```

### 4.3 Data Flow

```
forward/4 response (logprobs)
         │
         ▼
┌─────────────────────────────────────┐
│     TensorData.to_nx/1              │
│     (JSON → Nx.Tensor)              │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│     RegularizerPipeline.compute/3   │
│                                     │
│  1. Execute base_loss_fn            │
│  2. Execute regularizers (parallel) │
│  3. Compose total loss              │
│  4. Compute gradient norms          │
│  5. Build structured metrics        │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│     CustomLossOutput                │
│                                     │
│  - loss_total: float                │
│  - base_loss: %{...}                │
│  - regularizers: %{name => %{...}}  │
│  - regularizer_total: float         │
│  - total_grad_norm: float (opt)     │
└─────────────────────────────────────┘
```

---

## 5. Type System Design

### 5.1 Core Types

#### RegularizerSpec

```elixir
defmodule Tinkex.Types.RegularizerSpec do
  @moduledoc """
  Specification for a single regularizer.

  The function must accept (data, logprobs_tensor) and return
  {loss_tensor, metrics_map}.
  """

  @type regularizer_fn ::
    (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
      {Nx.Tensor.t(), %{String.t() => number()}})

  @type async_regularizer_fn ::
    (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
      Task.t({Nx.Tensor.t(), %{String.t() => number()}}))

  @enforce_keys [:fn, :weight, :name]
  defstruct [:fn, :weight, :name, async: false]

  @type t :: %__MODULE__{
    fn: regularizer_fn() | async_regularizer_fn(),
    weight: float(),
    name: String.t(),
    async: boolean()
  }
end
```

#### RegularizerOutput

```elixir
defmodule Tinkex.Types.RegularizerOutput do
  @moduledoc """
  Output metrics from a single regularizer computation.
  """

  @enforce_keys [:name, :value, :weight, :contribution]
  defstruct [:name, :value, :weight, :contribution, :grad_norm,
             :grad_norm_weighted, custom: %{}]

  @type t :: %__MODULE__{
    name: String.t(),
    value: float(),
    weight: float(),
    contribution: float(),
    grad_norm: float() | nil,
    grad_norm_weighted: float() | nil,
    custom: %{String.t() => number()}
  }
end
```

#### CustomLossOutput

```elixir
defmodule Tinkex.Types.CustomLossOutput do
  @moduledoc """
  Structured output from custom loss computation with regularizers.

  This type mirrors the Python SDK's metrics schema for compatibility.
  """

  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizers,
    :regularizer_total,
    :total_grad_norm
  ]

  @type base_loss_metrics :: %{
    value: float(),
    grad_norm: float() | nil,
    custom: %{String.t() => number()}
  }

  @type t :: %__MODULE__{
    loss_total: float(),
    base_loss: base_loss_metrics() | nil,
    regularizers: %{String.t() => RegularizerOutput.t()},
    regularizer_total: float(),
    total_grad_norm: float() | nil
  }
end
```

### 5.2 Behaviour Definition

```elixir
defmodule Tinkex.Regularizer do
  @moduledoc """
  Behaviour for implementing regularizers.

  Regularizers can be implemented as:
  1. Anonymous functions matching the spec
  2. Modules implementing this behaviour
  3. Async tasks for I/O-bound operations
  """

  @doc """
  Compute the regularizer loss and metrics.

  ## Parameters
  - data: List of training data (Datum structs)
  - logprobs: Nx tensor of log probabilities
  - opts: Optional configuration

  ## Returns
  - {loss_tensor, metrics_map} where:
    - loss_tensor: Scalar Nx tensor with requires_grad semantics
    - metrics_map: Custom metrics to track
  """
  @callback compute(
    data :: list(Tinkex.Types.Datum.t()),
    logprobs :: Nx.Tensor.t(),
    opts :: keyword()
  ) :: {Nx.Tensor.t(), %{String.t() => number()}}

  @doc """
  Optional: Return regularizer name for telemetry.
  """
  @callback name() :: String.t()

  @optional_callbacks [name: 0]
end
```

---

## 6. API Surface

### 6.1 TrainingClient Extensions

#### forward_backward_custom/4

```elixir
@doc """
Compute forward/backward pass with custom loss function and optional regularizers.

The base loss function is required and computes the primary training objective.
Optional regularizers add weighted loss terms. Total loss is computed as:

    loss_total = base_loss + Σ(weight_i × regularizer_i_loss)

## Parameters
- client: TrainingClient pid
- data: List of training data (Datum structs)
- loss_fn: Base loss function (required)
- opts: Options including:
  - :regularizers - List of RegularizerSpec (optional)
  - :track_grad_norms - Compute per-regularizer gradient L2 norms (default: false)
  - :parallel_execution - Run regularizers in parallel Tasks (default: true)
  - :timeout - Timeout for regularizer execution (default: 30_000ms)

## Returns
{:ok, Task.t()} that yields {:ok, CustomLossOutput.t()} or {:error, Error.t()}

## Examples

    # Base loss only
    {:ok, task} = TrainingClient.forward_backward_custom(
      client, data, &my_loss_fn/2
    )
    {:ok, output} = Task.await(task)

    # With regularizers
    regularizers = [
      %RegularizerSpec{fn: &sparsity/2, weight: 0.01, name: "sparsity"},
      %RegularizerSpec{fn: &entropy/2, weight: 0.001, name: "entropy"}
    ]

    {:ok, task} = TrainingClient.forward_backward_custom(
      client, data, &base_loss/2,
      regularizers: regularizers,
      track_grad_norms: true
    )

## Telemetry Events

- [:tinkex, :custom_loss, :start] - Emitted when computation begins
- [:tinkex, :regularizer, :compute, :start] - Emitted per regularizer
- [:tinkex, :regularizer, :compute, :stop] - Emitted per regularizer with duration
- [:tinkex, :custom_loss, :stop] - Emitted when computation completes
"""
@spec forward_backward_custom(
  t(),
  list(Tinkex.Types.Datum.t()),
  loss_fn :: (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
    {Nx.Tensor.t(), map()}),
  keyword()
) :: {:ok, Task.t()} | {:error, Tinkex.Error.t()}
```

### 6.2 RegularizerPipeline Module

```elixir
defmodule Tinkex.Regularizer.Pipeline do
  @moduledoc """
  Orchestrates regularizer composition and gradient tracking.
  """

  @doc """
  Compute composed loss from base loss and regularizers.

  ## Parameters
  - data: Training data
  - logprobs: Nx tensor of log probabilities
  - base_loss_fn: Required base loss function
  - opts: Configuration including:
    - :regularizers - List of RegularizerSpec
    - :track_grad_norms - Enable gradient norm computation
    - :parallel_execution - Run regularizers in parallel

  ## Returns
  CustomLossOutput with structured metrics
  """
  @spec compute(
    list(Tinkex.Types.Datum.t()),
    Nx.Tensor.t(),
    loss_fn :: function(),
    keyword()
  ) :: {:ok, Tinkex.Types.CustomLossOutput.t()} | {:error, term()}
end
```

### 6.3 Executor Module

```elixir
defmodule Tinkex.Regularizer.Executor do
  @moduledoc """
  Manages regularizer execution with process-based parallelism.
  """

  @doc """
  Execute multiple regularizers, optionally in parallel.

  When parallel_execution is true (default), spawns Task processes
  for each regularizer and awaits results concurrently.

  CPU-bound regularizers benefit from parallel execution across
  multiple scheduler threads. I/O-bound async regularizers can
  overlap with other computations.
  """
  @spec execute_all(
    list(Tinkex.Types.RegularizerSpec.t()),
    list(Tinkex.Types.Datum.t()),
    Nx.Tensor.t(),
    keyword()
  ) :: {:ok, list(Tinkex.Types.RegularizerOutput.t())} | {:error, term()}

  @doc """
  Execute a single regularizer in a supervised Task.
  """
  @spec execute_one(
    Tinkex.Types.RegularizerSpec.t(),
    list(Tinkex.Types.Datum.t()),
    Nx.Tensor.t(),
    keyword()
  ) :: {:ok, Tinkex.Types.RegularizerOutput.t()} | {:error, term()}
end
```

---

## 7. Concurrency Model

### 7.1 Elixir vs Python Concurrency Comparison

| Aspect | Python (threading) | Elixir (processes) |
|--------|-------------------|-------------------|
| **Parallelism** | GIL limits true parallelism | True parallel execution |
| **Isolation** | Shared memory, locks needed | Process isolation, no locks |
| **Failure handling** | Try/except, manual cleanup | Let-it-crash, supervisors |
| **I/O multiplexing** | asyncio event loop | BEAM scheduler |
| **CPU-bound work** | ThreadPoolExecutor | Task.async_stream |
| **Memory model** | Shared mutable state | Message passing, immutable |

### 7.2 Execution Strategies

#### Strategy 1: Sequential Execution (baseline)

```elixir
def execute_sequential(regularizers, data, logprobs, opts) do
  Enum.map(regularizers, fn spec ->
    execute_one(spec, data, logprobs, opts)
  end)
end
```

**Use case**: Debugging, deterministic ordering, low regularizer count

#### Strategy 2: Parallel Task Execution (default)

```elixir
def execute_parallel(regularizers, data, logprobs, opts) do
  timeout = Keyword.get(opts, :timeout, 30_000)

  regularizers
  |> Task.async_stream(
    fn spec -> execute_one(spec, data, logprobs, opts) end,
    timeout: timeout,
    max_concurrency: System.schedulers_online(),
    on_timeout: :kill_task
  )
  |> Enum.map(fn
    {:ok, result} -> result
    {:exit, reason} -> {:error, {:regularizer_failed, reason}}
  end)
end
```

**Use case**: Multiple CPU-bound regularizers, production workloads

#### Strategy 3: Supervised Execution (fault-tolerant)

```elixir
def execute_supervised(regularizers, data, logprobs, opts) do
  # Start temporary supervisor for this batch
  {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

  try do
    tasks = Enum.map(regularizers, fn spec ->
      {:ok, pid} = DynamicSupervisor.start_child(sup, {
        Task,
        fn -> execute_one(spec, data, logprobs, opts) end
      })
      Task.Supervisor.async_nolink(pid, fn -> :ok end)
    end)

    Task.await_many(tasks, timeout)
  after
    DynamicSupervisor.stop(sup)
  end
end
```

**Use case**: Long-running regularizers, external service dependencies

### 7.3 Async Regularizer Pattern

For I/O-bound regularizers (external APIs, databases):

```elixir
# Define an async regularizer
def external_validation_async(data, logprobs) do
  Task.async(fn ->
    # Non-blocking HTTP call
    {:ok, response} = HTTPClient.get("/validate", query: build_query(data))
    penalty = compute_penalty(response)
    {Nx.tensor(penalty), %{"validated" => true}}
  end)
end

# Use with async: true flag
regularizers = [
  %RegularizerSpec{
    fn: &external_validation_async/2,
    weight: 0.1,
    name: "kb_validation",
    async: true  # Signals that fn returns Task.t()
  }
]
```

### 7.4 GenServer Integration

The TrainingClient GenServer handles the orchestration:

```elixir
def handle_call({:forward_backward_custom, data, loss_fn, opts}, from, state) do
  # Spawn background task for the custom loss computation
  Task.start(fn ->
    reply = try do
      # 1. Get forward pass (logprobs)
      case do_forward(data, state) do
        {:ok, forward_output} ->
          logprobs = extract_logprobs(forward_output)

          # 2. Run regularizer pipeline
          case Pipeline.compute(data, logprobs, loss_fn, opts) do
            {:ok, custom_output} ->
              # 3. Send gradients back via linearization
              do_backward(custom_output, state)
              {:ok, custom_output}

            {:error, _} = error -> error
          end

        {:error, _} = error -> error
      end
    rescue
      e -> {:error, Error.from_exception(e)}
    end

    GenServer.reply(from, reply)
  end)

  {:noreply, state}
end
```

---

## 8. Telemetry and Metrics

### 8.1 Event Schema

#### Custom Loss Events

```elixir
# Emitted when custom loss computation starts
:telemetry.execute(
  [:tinkex, :custom_loss, :start],
  %{system_time: System.system_time()},
  %{
    model_id: model_id,
    data_count: length(data),
    regularizer_count: length(regularizers),
    track_grad_norms: track_grad_norms
  }
)

# Emitted when custom loss computation completes
:telemetry.execute(
  [:tinkex, :custom_loss, :stop],
  %{
    duration: duration_native,
    loss_total: output.loss_total,
    regularizer_total: output.regularizer_total
  },
  %{
    model_id: model_id,
    regularizer_count: length(regularizers),
    track_grad_norms: track_grad_norms
  }
)
```

#### Per-Regularizer Events

```elixir
# Emitted when individual regularizer starts
:telemetry.execute(
  [:tinkex, :regularizer, :compute, :start],
  %{system_time: System.system_time()},
  %{
    regularizer_name: spec.name,
    weight: spec.weight,
    async: spec.async
  }
)

# Emitted when individual regularizer completes
:telemetry.execute(
  [:tinkex, :regularizer, :compute, :stop],
  %{
    duration: duration_native,
    value: output.value,
    contribution: output.contribution,
    grad_norm: output.grad_norm
  },
  %{
    regularizer_name: spec.name,
    weight: spec.weight,
    async: spec.async
  }
)
```

### 8.2 Metrics Output Schema

The `CustomLossOutput` structure provides comprehensive metrics:

```elixir
%CustomLossOutput{
  # Total composed loss (base + weighted regularizers)
  loss_total: 2.847,

  # Base loss metrics
  base_loss: %{
    value: 2.5,
    grad_norm: 3.14,  # Only if track_grad_norms: true
    custom: %{"perplexity" => 12.18, "mean_nll" => 2.5}
  },

  # Per-regularizer metrics
  regularizers: %{
    "sparsity" => %RegularizerOutput{
      name: "sparsity",
      value: 22.4,
      weight: 0.01,
      contribution: 0.224,
      grad_norm: 7.48,
      grad_norm_weighted: 0.0748,
      custom: %{"l1_total" => 44.8, "l1_mean" => 22.4}
    },
    "entropy" => %RegularizerOutput{
      name: "entropy",
      value: 1.5,
      weight: 0.001,
      contribution: 0.0015,
      grad_norm: 2.12,
      grad_norm_weighted: 0.00212,
      custom: %{"entropy_mean" => 1.5}
    }
  },

  # Sum of all regularizer contributions
  regularizer_total: 0.2255,

  # Total gradient norm (only if track_grad_norms: true)
  total_grad_norm: 5.67
}
```

### 8.3 Integration with Existing Telemetry

```elixir
defmodule Tinkex.Regularizer.Telemetry do
  @moduledoc """
  Telemetry helpers for regularizer events.
  """

  @events [
    [:tinkex, :custom_loss, :start],
    [:tinkex, :custom_loss, :stop],
    [:tinkex, :custom_loss, :exception],
    [:tinkex, :regularizer, :compute, :start],
    [:tinkex, :regularizer, :compute, :stop],
    [:tinkex, :regularizer, :compute, :exception]
  ]

  def attach_logger(opts \\ []) do
    handler_id = opts[:handler_id] ||
      "tinkex-regularizer-#{:erlang.unique_integer([:positive])}"
    level = opts[:level] || :info

    :telemetry.attach_many(
      handler_id,
      @events,
      &handle_event/4,
      %{level: level}
    )

    handler_id
  end

  def handle_event([:tinkex, :custom_loss, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(
      measurements.duration, :native, :millisecond
    )

    Logger.log(config.level, fn ->
      "Custom loss computed in #{duration_ms}ms " <>
      "total=#{measurements.loss_total} " <>
      "regularizers=#{metadata.regularizer_count}"
    end)
  end

  def handle_event([:tinkex, :regularizer, :compute, :stop], measurements, metadata, config) do
    duration_ms = System.convert_time_unit(
      measurements.duration, :native, :millisecond
    )

    Logger.log(config.level, fn ->
      "Regularizer #{metadata.regularizer_name} " <>
      "value=#{measurements.value} " <>
      "contribution=#{measurements.contribution} " <>
      "in #{duration_ms}ms"
    end)
  end

  # ... other handlers
end
```

---

## 9. Gradient Computation in Elixir

### 9.1 Nx and Automatic Differentiation

Nx provides `Nx.Defn` for automatic differentiation:

```elixir
defmodule Tinkex.Regularizer.GradientTracker do
  import Nx.Defn

  @doc """
  Compute L2 norm of gradients from loss with respect to inputs.
  """
  defn compute_grad_norm(loss_fn, inputs) do
    # Get gradients via automatic differentiation
    {_loss, grads} = value_and_grad(loss_fn, inputs)

    # Compute L2 norm: sqrt(sum(grad^2))
    grads
    |> Nx.flatten()
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
  end

  @doc """
  Compute gradient norm for a regularizer.
  """
  def gradient_norm_for_regularizer(spec, data, logprobs) do
    # Wrap regularizer in a differentiable function
    loss_fn = fn input ->
      {loss, _metrics} = spec.fn.(data, input)
      loss
    end

    # Compute gradient norm
    compute_grad_norm(loss_fn, logprobs)
    |> Nx.to_number()
  end
end
```

### 9.2 Gradient Tracking Implementation

```elixir
defmodule Tinkex.Regularizer.Pipeline do
  alias Tinkex.Regularizer.GradientTracker

  defp compute_with_gradients(spec, data, logprobs, track_grad_norms) do
    # Execute regularizer
    start_time = System.monotonic_time()
    {loss_tensor, custom_metrics} = spec.fn.(data, logprobs)
    duration = System.monotonic_time() - start_time

    # Compute gradient norm if requested
    grad_norm = if track_grad_norms do
      GradientTracker.gradient_norm_for_regularizer(spec, data, logprobs)
    else
      nil
    end

    loss_value = Nx.to_number(loss_tensor)
    contribution = spec.weight * loss_value

    output = %RegularizerOutput{
      name: spec.name,
      value: loss_value,
      weight: spec.weight,
      contribution: contribution,
      grad_norm: grad_norm,
      grad_norm_weighted: if(grad_norm, do: spec.weight * grad_norm),
      custom: custom_metrics
    }

    # Emit telemetry
    emit_regularizer_stop(spec, output, duration)

    {:ok, output, loss_tensor}
  end
end
```

### 9.3 EXLA Backend Considerations

```elixir
# Configure EXLA for GPU acceleration
config :nx, :default_backend, EXLA.Backend

# For CPU-only systems
config :nx, :default_backend, Nx.BinaryBackend
```

**Key considerations:**

1. **JIT Compilation**: `Nx.Defn` functions are JIT-compiled by EXLA
2. **Device Placement**: Tensors must be on the same device for operations
3. **Memory Management**: Large tensors should be explicitly deallocated
4. **Batch Operations**: Prefer batched operations over loops

---

## 10. Implementation Strategy

### 10.1 Phase 1: Core Types and Pipeline (Week 1)

**Deliverables:**
- `RegularizerSpec` type definition
- `RegularizerOutput` type definition
- `CustomLossOutput` type definition
- `Tinkex.Regularizer` behaviour
- Basic `Pipeline.compute/4` (sequential execution)

**Tests:**
- Type construction and validation
- Sequential regularizer composition
- Basic metrics output

### 10.2 Phase 2: Parallel Execution (Week 2)

**Deliverables:**
- `Executor.execute_parallel/4` with Task.async_stream
- Async regularizer support
- Timeout and error handling
- Integration with TrainingClient GenServer

**Tests:**
- Parallel execution correctness
- Timeout handling
- Error propagation
- Async regularizer awaiting

### 10.3 Phase 3: Gradient Tracking (Week 3)

**Deliverables:**
- `GradientTracker` module with Nx.Defn
- Per-regularizer gradient norm computation
- Total gradient norm calculation
- EXLA backend integration

**Tests:**
- Gradient norm accuracy (mathematical correctness)
- EXLA vs BinaryBackend consistency
- Memory usage under load

### 10.4 Phase 4: Telemetry and Documentation (Week 4)

**Deliverables:**
- Telemetry event emission
- Event handlers for logging
- API documentation (ExDoc)
- Example code and guides

**Tests:**
- Telemetry event correctness
- Documentation accuracy
- Example code execution

---

## 11. Migration Path

### 11.1 Backward Compatibility

Existing code using `forward/4` continues to work:

```elixir
# Existing code (unchanged)
{:ok, task} = TrainingClient.forward(client, data, :cross_entropy)
{:ok, output} = Task.await(task)
```

### 11.2 Migration Examples

**From manual composition:**

```elixir
# Before: Manual composition in custom loss
def custom_loss(data, logprobs) do
  base = compute_cross_entropy(logprobs)
  sparsity = 0.01 * Nx.sum(Nx.abs(logprobs))
  entropy = 0.001 * compute_entropy(logprobs)
  total = base + sparsity + entropy

  {total, %{
    "base" => Nx.to_number(base),
    "sparsity" => Nx.to_number(sparsity),
    "entropy" => Nx.to_number(entropy)
  }}
end

# After: Structured composition
base_loss_fn = &compute_cross_entropy/2

regularizers = [
  %RegularizerSpec{fn: &sparsity_penalty/2, weight: 0.01, name: "sparsity"},
  %RegularizerSpec{fn: &entropy_regularizer/2, weight: 0.001, name: "entropy"}
]

{:ok, task} = TrainingClient.forward_backward_custom(
  client, data, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)
```

---

## 12. Testing Strategy

### 12.1 Unit Tests

```elixir
defmodule Tinkex.Regularizer.PipelineTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{RegularizerSpec, CustomLossOutput}
  alias Tinkex.Regularizer.Pipeline

  describe "compute/4" do
    test "computes base loss only when no regularizers" do
      data = [build_datum()]
      logprobs = Nx.tensor([-1.0, -2.0, -3.0])

      base_loss_fn = fn _data, lp ->
        {Nx.mean(lp), %{"test" => 1.0}}
      end

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn, [])

      assert output.loss_total == Nx.to_number(Nx.mean(logprobs))
      assert output.regularizer_total == 0.0
      assert output.regularizers == %{}
    end

    test "composes multiple regularizers with weights" do
      data = [build_datum()]
      logprobs = Nx.tensor([-1.0, -2.0, -3.0])

      base_loss_fn = fn _data, _lp -> {Nx.tensor(1.0), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(10.0), %{}} end,
          weight: 0.1,
          name: "reg_a"
        },
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(20.0), %{}} end,
          weight: 0.5,
          name: "reg_b"
        }
      ]

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
        regularizers: regularizers
      )

      # base: 1.0, reg_a: 0.1*10=1.0, reg_b: 0.5*20=10.0
      # total: 1.0 + 1.0 + 10.0 = 12.0
      assert_in_delta output.loss_total, 12.0, 0.001
      assert_in_delta output.regularizer_total, 11.0, 0.001

      assert output.regularizers["reg_a"].contribution == 1.0
      assert output.regularizers["reg_b"].contribution == 10.0
    end
  end
end
```

### 12.2 Property-Based Tests

```elixir
defmodule Tinkex.Regularizer.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "regularizer contributions sum to regularizer_total" do
    check all weights <- list_of(float(min: 0.0, max: 1.0), min_length: 1, max_length: 5),
              values <- list_of(float(min: 0.0, max: 100.0), length: length(weights)) do

      regularizers = Enum.zip(weights, values)
      |> Enum.with_index()
      |> Enum.map(fn {{w, _v}, i} ->
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(Enum.at(values, i)), %{}} end,
          weight: w,
          name: "reg_#{i}"
        }
      end)

      {:ok, output} = Pipeline.compute([], Nx.tensor([1.0]), &base_loss/2,
        regularizers: regularizers
      )

      expected_total = Enum.zip(weights, values)
      |> Enum.map(fn {w, v} -> w * v end)
      |> Enum.sum()

      contributions_sum = output.regularizers
      |> Map.values()
      |> Enum.map(& &1.contribution)
      |> Enum.sum()

      assert_in_delta output.regularizer_total, expected_total, 0.001
      assert_in_delta contributions_sum, expected_total, 0.001
    end
  end
end
```

### 12.3 Integration Tests

```elixir
defmodule Tinkex.Regularizer.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))
    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service,
      base_model: "meta-llama/Llama-3.1-8B"
    )

    %{training: training}
  end

  test "full custom loss workflow with regularizers", %{training: training} do
    data = [build_training_datum(training)]

    base_loss_fn = fn _data, logprobs ->
      loss = Nx.negate(Nx.mean(logprobs))
      {loss, %{"mean_nll" => Nx.to_number(loss)}}
    end

    regularizers = [
      %RegularizerSpec{
        fn: fn _d, lp -> {Nx.sum(Nx.abs(lp)), %{}} end,
        weight: 0.01,
        name: "l1"
      }
    ]

    {:ok, task} = TrainingClient.forward_backward_custom(
      training, data, base_loss_fn,
      regularizers: regularizers,
      track_grad_norms: true
    )

    assert {:ok, output} = Task.await(task, 60_000)
    assert is_float(output.loss_total)
    assert is_float(output.regularizer_total)
    assert is_float(output.total_grad_norm)
    assert Map.has_key?(output.regularizers, "l1")
  end
end
```

---

## 13. Performance Considerations

### 13.1 Benchmarks

Target performance characteristics:

| Scenario | Metric | Target |
|----------|--------|--------|
| Single sync regularizer | Overhead | < 5ms |
| 5 parallel regularizers | Speedup | > 3x vs sequential |
| Gradient norm computation | Per-tensor | < 10ms |
| Telemetry emission | Per-event | < 1ms |

### 13.2 Optimization Strategies

1. **Tensor Reuse**: Avoid creating intermediate tensors where possible
2. **Batch Operations**: Combine multiple regularizer computations when possible
3. **EXLA JIT**: Ensure defn functions are JIT-compiled
4. **Task Pooling**: Reuse Task workers across batches
5. **Selective Gradient Tracking**: Only compute when explicitly requested

### 13.3 Memory Management

```elixir
# Explicit cleanup for large tensors
defp cleanup_tensors(tensors) when is_list(tensors) do
  Enum.each(tensors, fn
    %Nx.Tensor{} = t -> Nx.backend_deallocate(t)
    _ -> :ok
  end)
end
```

---

## 14. Security Considerations

### 14.1 Input Validation

```elixir
defp validate_regularizer_spec!(%RegularizerSpec{} = spec) do
  unless is_function(spec.fn, 2) or is_function(spec.fn, 3) do
    raise ArgumentError, "Regularizer fn must be arity 2 or 3"
  end

  unless is_float(spec.weight) and spec.weight >= 0.0 do
    raise ArgumentError, "Regularizer weight must be non-negative float"
  end

  unless is_binary(spec.name) and byte_size(spec.name) > 0 do
    raise ArgumentError, "Regularizer name must be non-empty string"
  end

  :ok
end
```

### 14.2 Resource Limits

```elixir
@max_regularizers 100
@max_execution_timeout 300_000  # 5 minutes

defp validate_options!(opts) do
  regularizers = Keyword.get(opts, :regularizers, [])

  if length(regularizers) > @max_regularizers do
    raise ArgumentError, "Maximum #{@max_regularizers} regularizers allowed"
  end

  timeout = Keyword.get(opts, :timeout, 30_000)

  if timeout > @max_execution_timeout do
    raise ArgumentError, "Maximum timeout is #{@max_execution_timeout}ms"
  end

  :ok
end
```

---

## 15. Open Questions

### 15.1 Design Questions

1. **Gradient Accumulation**: Should we support gradient accumulation across multiple forward_backward_custom calls?

2. **Regularizer State**: Should regularizers be allowed to maintain state across batches (e.g., for EMA tracking)?

3. **Distributed Execution**: How should regularizers behave in a distributed Elixir cluster?

4. **Dynamic Regularizers**: Should we support adding/removing regularizers during training?

### 15.2 Implementation Questions

1. **Nx.Defn Limitations**: Some operations may not be differentiable - how to handle?

2. **Error Recovery**: If one regularizer fails, should others continue?

3. **Memory Pressure**: How to handle large tensors in long training runs?

4. **Backend Compatibility**: Ensure compatibility across EXLA, Torchx, and BinaryBackend?

### 15.3 API Questions

1. **Regularizer Factories**: Should we provide built-in regularizers (L1, L2, entropy)?

2. **Configuration DSL**: Should there be a higher-level configuration format?

3. **Visualization**: Should we provide tools for visualizing regularizer dynamics?

---

## Appendix A: Python API Comparison

| Python API | Elixir API | Notes |
|------------|------------|-------|
| `forward_backward_custom(data, loss_fn, regularizers=...)` | `forward_backward_custom(client, data, loss_fn, regularizers: ...)` | Elixir uses keyword opts |
| `track_grad_norms=True` | `track_grad_norms: true` | Same semantics |
| `run_sync_in_executor=True` | `parallel_execution: true` | Elixir uses processes not thread pool |
| `async def regularizer(...)` | `%RegularizerSpec{async: true, ...}` | Explicit flag in Elixir |
| `torch.autograd.grad(...)` | `Nx.Defn.grad(...)` | Different autodiff systems |

---

## Appendix B: Example Regularizers

### L1 Sparsity

```elixir
defmodule MyRegularizers.L1Sparsity do
  @behaviour Tinkex.Regularizer

  @impl true
  def compute(_data, logprobs, _opts) do
    l1_norm = logprobs
    |> Nx.abs()
    |> Nx.sum()

    metrics = %{
      "l1_total" => Nx.to_number(l1_norm),
      "l1_mean" => Nx.to_number(Nx.mean(Nx.abs(logprobs)))
    }

    {l1_norm, metrics}
  end

  @impl true
  def name, do: "l1_sparsity"
end
```

### Entropy

```elixir
defmodule MyRegularizers.Entropy do
  @behaviour Tinkex.Regularizer
  import Nx.Defn

  @impl true
  def compute(_data, logprobs, _opts) do
    entropy = compute_entropy(logprobs)

    {Nx.negate(entropy), %{
      "entropy" => Nx.to_number(entropy)
    }}
  end

  defnp compute_entropy(logprobs) do
    probs = Nx.exp(logprobs)
    Nx.negate(Nx.sum(probs * logprobs))
  end

  @impl true
  def name, do: "entropy"
end
```

### External Validation (Async)

```elixir
defmodule MyRegularizers.ExternalValidation do
  @behaviour Tinkex.Regularizer

  @impl true
  def compute(data, _logprobs, opts) do
    # Returns a Task for async execution
    Task.async(fn ->
      endpoint = Keyword.get(opts, :endpoint, "http://localhost:8000/validate")

      {:ok, response} = HTTPoison.post(endpoint,
        Jason.encode!(%{data: serialize_data(data)}),
        [{"Content-Type", "application/json"}]
      )

      %{"penalty" => penalty} = Jason.decode!(response.body)

      {Nx.tensor(penalty), %{
        "validated" => true,
        "latency_ms" => response.latency_ms
      }}
    end)
  end

  @impl true
  def name, do: "external_validation"

  defp serialize_data(data), do: # ...
end
```

---

*End of Technical Specification Document*
