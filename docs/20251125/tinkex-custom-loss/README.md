# Tinkex Custom Loss with Nx/EXLA

**Deep Technical Analysis for Elixir Implementation**

**Status:** Research / Pre-Implementation
**Related:** `../tinker/structured-regularizers/` (Python design)
**Date:** 2025-11-25

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Tinkex State](#current-tinkex-state)
3. [The Linearization Architecture](#the-linearization-architecture)
4. [Nx/EXLA Requirements](#nxexla-requirements)
5. [Implementation Architecture](#implementation-architecture)
6. [API Design](#api-design)
7. [Implementation Details](#implementation-details)
8. [Nx.Defn Gradient Computation](#nxdefn-gradient-computation)
9. [Type System Integration](#type-system-integration)
10. [Telemetry Integration](#telemetry-integration)
11. [Testing Strategy](#testing-strategy)
12. [Migration Path](#migration-path)
13. [Risk Analysis](#risk-analysis)
14. [Appendix: Code Examples](#appendix-code-examples)

---

## Executive Summary

Implementing custom loss in Tinkex requires:

1. **Adding EXLA dependency** (~100MB+ but necessary for autodiff)
2. **Exposing forward-only API** in TrainingClient
3. **Implementing Nx.Defn-based gradient computation**
4. **Supporting regularizer composition** with async execution
5. **Structured telemetry** for per-regularizer metrics

This is a **v2.0 feature** per original porting strategy. The complexity is significant but tractable.

---

## Current Tinkex State

### What Exists

**Dependencies** (`mix.exs:39-65`):
```elixir
{:nx, "~> 0.7"},        # Tensor operations - PRESENT
# {:exla, ...}          # NOT present - removed for "lean" v1
```

**Training Client** (`lib/tinkex/training_client.ex`):
- `forward_backward/4` - full forward+backward, returns `ForwardBackwardOutput`
- No `forward/4` exposed (though API endpoint exists)
- No custom loss callback mechanism

**Training API** (`lib/tinkex/api/training.ex:73-81`):
```elixir
@spec forward(map(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
def forward(request, opts) do
  Tinkex.API.post("/api/v1/forward", request, Keyword.put(opts, :pool_type, :training))
end
```
The forward endpoint EXISTS but is not exposed through TrainingClient.

**Nx Integration** (`lib/tinkex/types/tensor_data.ex`):
```elixir
@spec from_nx(Nx.Tensor.t()) :: t()
def from_nx(%Nx.Tensor{} = tensor) do
  # Converts Nx tensor to wire format with dtype normalization
end

@spec to_nx(t()) :: Nx.Tensor.t()
def to_nx(%__MODULE__{...}) do
  # Converts wire format back to Nx tensor
end
```

**Loss Function Types** (`lib/tinkex/types/loss_fn_type.ex:28`):
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro
```
No `:custom` variant.

### What's Missing

| Component | Status | Required For Custom Loss |
|-----------|--------|-------------------------|
| EXLA dependency | Removed | Autodiff via `Nx.Defn.grad` |
| `forward/4` in TrainingClient | Not exposed | Get logprobs without backward |
| Custom loss callback type | Doesn't exist | User-defined loss functions |
| Regularizer composition | Doesn't exist | Multiple named loss terms |
| Per-regularizer telemetry | Doesn't exist | Structured metrics |

### Why EXLA Was Removed

From `docs/20251119/port_research/07_porting_strategy.md:11`:

> **Dependencies**: Removed Bumblebee and EXLA (bloat) - using tokenizers-only for lean integration

From line 17:

> **Custom loss deferred**: Explicitly moved custom loss functions to v2.0 (requires EXLA, out of v1 scope)

The decision was deliberate: v1.0 focused on core training loop parity without the ~100MB+ EXLA dependency.

---

## The Linearization Architecture

### How Python Does It

The Python SDK's custom loss uses a **linearization trick** that separates client-side computation from server-side gradient flow:

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT SIDE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Call forward() → get logprobs from server                   │
│                                                                  │
│  2. Convert logprobs to PyTorch tensors with requires_grad=True │
│                                                                  │
│  3. User callback: loss = f(data, logprobs)                     │
│     - Can use ANY library (GUDHI, Z3, external APIs)            │
│     - Arbitrary computation allowed                              │
│                                                                  │
│  4. loss.backward() → compute ∂loss/∂logprobs via autograd     │
│                                                                  │
│  5. Package gradients as "weights" for linearized loss          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP: forward_backward(data, weights)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        SERVER SIDE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  6. Receive linearized weights                                   │
│                                                                  │
│  7. Compute: weighted_loss = Σ weights[i] * logprobs[i]         │
│                                                                  │
│  8. weighted_loss.backward() → compute ∂loss/∂params            │
│                                                                  │
│  9. Accumulate gradients for optim_step                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Mathematical Foundation

Given:
- `logprobs`: server-computed log-probabilities (vector)
- `loss = f(logprobs)`: user's custom loss function
- Goal: compute `∂loss/∂params` for model parameters

**The Chain Rule**:
```
∂loss/∂params = (∂loss/∂logprobs) · (∂logprobs/∂params)
                 ↑                    ↑
                 Client computes      Server computes
                 (via autograd)       (via forward_backward)
```

**The Trick**:
- Client computes `g = ∂loss/∂logprobs` using local autograd
- Server treats `weighted_loss = Σ g[i] * logprobs[i]` as if it were the original loss
- `∂weighted_loss/∂params = Σ g[i] * (∂logprobs[i]/∂params)` = the chain rule result

This works because the gradient is a **linear operator**.

### Why This Architecture

1. **Library Flexibility**: Client can use any library (GUDHI, Z3, etc.) - not available on server
2. **No Server Changes**: Server just sees a weighted cross-entropy-like loss
3. **Compute Separation**: Expensive domain computations run client-side
4. **Security**: User code never runs on Tinker infrastructure

---

## Nx/EXLA Requirements

### Why EXLA is Required

**Nx alone cannot compute gradients**. Nx is a tensor library, not an autodiff system.

Gradient computation requires `Nx.Defn.grad/2`, which needs a **compiler backend**:

```elixir
# This requires EXLA or Torchx backend
defn loss_grad(logprobs, custom_fn) do
  grad(logprobs, fn lp -> custom_fn.(lp) end)
end
```

Without EXLA:
```elixir
iex> Nx.Defn.grad(fn x -> Nx.sum(x) end).(Nx.tensor([1,2,3]))
** (RuntimeError) cannot call grad/1 with the default defn compiler...
```

### EXLA Dependency Addition

Update `mix.exs`:
```elixir
defp deps do
  [
    # Existing
    {:nx, "~> 0.7"},

    # NEW: Required for autodiff
    {:exla, "~> 0.7"},

    # ... rest unchanged
  ]
end
```

**Size Impact**: EXLA adds ~100-150MB due to XLA/LLVM compiler.

### EXLA Configuration

Add to `config/config.exs`:
```elixir
# Set EXLA as default Nx backend for autodiff
config :nx, :default_backend, EXLA.Backend

# Optional: configure JIT compilation
config :exla,
  clients: [
    host: [platform: :host]
  ],
  default_client: :host
```

For CPU-only (no GPU):
```elixir
config :exla, :default_client, :host
```

---

## Implementation Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Tinkex.CustomLoss                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │  RegularizerSpec │  │ RegularizerRunner │  │ GradComputer  │  │
│  │  (type/struct)   │  │ (async executor)  │  │ (Nx.Defn)     │  │
│  └────────┬─────────┘  └────────┬──────────┘  └───────┬───────┘  │
│           │                     │                      │          │
│           └─────────────────────┼──────────────────────┘          │
│                                 │                                 │
│                                 ▼                                 │
│                    ┌────────────────────────┐                     │
│                    │  Tinkex.TrainingClient │                     │
│                    │  forward_backward_     │                     │
│                    │  custom/4              │                     │
│                    └────────────┬───────────┘                     │
│                                 │                                 │
└─────────────────────────────────┼─────────────────────────────────┘
                                  │
                                  ▼
                    ┌────────────────────────┐
                    │  Tinkex.API.Training   │
                    │  forward/2             │
                    │  forward_backward/2    │
                    └────────────────────────┘
```

### New Modules

| Module | Purpose |
|--------|---------|
| `Tinkex.CustomLoss.RegularizerSpec` | Type definition for regularizer config |
| `Tinkex.CustomLoss.GradComputer` | Nx.Defn-based gradient computation |
| `Tinkex.CustomLoss.Runner` | Async regularizer execution |
| `Tinkex.CustomLoss.Telemetry` | Per-regularizer metrics |

---

## API Design

### RegularizerSpec Type

```elixir
defmodule Tinkex.CustomLoss.RegularizerSpec do
  @moduledoc """
  Specification for a custom regularizer.
  """

  @type loss_fn :: (list(Nx.Tensor.t()), list(map()) -> {Nx.Tensor.t(), map()})
  @type async_loss_fn :: (list(Nx.Tensor.t()), list(map()) -> Task.t())

  @type t :: %__MODULE__{
    name: String.t(),
    weight: float(),
    fn: loss_fn() | async_loss_fn(),
    async: boolean()
  }

  @enforce_keys [:name, :weight, :fn]
  defstruct [:name, :weight, :fn, async: false]

  @doc """
  Create a synchronous regularizer.
  """
  def sync(name, weight, fun) when is_function(fun, 2) do
    %__MODULE__{name: name, weight: weight, fn: fun, async: false}
  end

  @doc """
  Create an async regularizer (for expensive computations).
  """
  def async(name, weight, fun) when is_function(fun, 2) do
    %__MODULE__{name: name, weight: weight, fn: fun, async: true}
  end
end
```

### Extended TrainingClient API

```elixir
defmodule Tinkex.TrainingClient do
  # ... existing code ...

  @doc """
  Forward pass only (for custom loss computation).

  Returns logprobs that can be used for gradient computation.
  """
  @spec forward(t(), [map()], atom() | String.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward(client, data, loss_fn, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward, data, loss_fn, opts}, :infinity)
     end)}
  end

  @doc """
  Forward-backward with custom loss function(s).

  ## Options

  - `:regularizers` - List of `RegularizerSpec` structs
  - `:base_loss_fn` - Optional base loss callback (legacy support)

  ## Examples

      regularizers = [
        RegularizerSpec.sync("sparsity", 0.01, &sparsity_penalty/2),
        RegularizerSpec.async("topology", 0.1, &compute_topology/2)
      ]

      {:ok, task} = TrainingClient.forward_backward_custom(
        client, data, regularizers: regularizers
      )
  """
  @spec forward_backward_custom(t(), [map()], keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward_backward_custom(client, data, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward_backward_custom, data, opts}, :infinity)
     end)}
  end
end
```

---

## Implementation Details

### TrainingClient GenServer Handlers

Add to `lib/tinkex/training_client.ex`:

```elixir
@impl true
def handle_call({:forward, data, loss_fn, opts}, from, state) do
  chunks = chunk_data(data)
  {seq_ids, new_counter} = allocate_request_ids(length(chunks), state.request_id_counter)

  send_result =
    Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
      case send_forward_request(chunk, loss_fn, seq_id, opts, state) do
        {:ok, future} -> {:cont, {:ok, [future | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)

  case send_result do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, futures_rev} ->
      futures = Enum.reverse(futures_rev)

      Task.start(fn ->
        reply =
          try do
            polling_tasks =
              Enum.map(futures, fn future ->
                task = state.future_module.poll(future, poll_opts_with_type(state, opts, "Forward"))
                unlink_task(task)
                task
              end)

            case await_forward_results(polling_tasks, state.future_module) do
              {:ok, outputs} ->
                {:ok, combine_forward_results(outputs)}

              {:error, %Error{} = error} ->
                {:error, error}
            end
          rescue
            e ->
              {:error, %Error{message: "Polling failed: #{Exception.message(e)}", type: :request_failed}}
          end

        try do
          GenServer.reply(from, reply)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:noreply, %{state | request_id_counter: new_counter}}
  end
end

@impl true
def handle_call({:forward_backward_custom, data, opts}, from, state) do
  alias Tinkex.CustomLoss.{GradComputer, Runner}

  regularizers = Keyword.get(opts, :regularizers, [])
  base_loss_fn = Keyword.get(opts, :base_loss_fn)

  if regularizers == [] and base_loss_fn == nil do
    {:reply, {:error, Error.new(:validation, "Must provide regularizers or base_loss_fn")}, state}
  else
    Task.start(fn ->
      reply =
        try do
          # 1. Forward pass to get logprobs
          {:ok, forward_task} = forward(self(), data, :cross_entropy, opts)
          {:ok, forward_result} = Task.await(forward_task, :infinity)

          # 2. Convert logprobs to Nx tensors
          logprobs_list = extract_logprobs_as_nx(forward_result)

          # 3. Run regularizers (handles sync/async)
          {:ok, reg_results} = Runner.run_regularizers(regularizers, logprobs_list, data)

          # 4. Also run base_loss_fn if provided
          base_result =
            if base_loss_fn do
              {loss, metrics} = base_loss_fn.(logprobs_list, data)
              %{loss: loss, metrics: metrics, name: "base"}
            else
              nil
            end

          # 5. Compute total loss and gradients via Nx.Defn
          {total_loss, grads, telemetry} =
            GradComputer.compute_gradients(logprobs_list, reg_results, base_result)

          # 6. Linearize gradients as weights
          linear_data = linearize_gradients(data, grads)

          # 7. Call standard forward_backward with linearized weights
          {:ok, fwdbwd_task} = forward_backward(self(), linear_data, :cross_entropy, opts)
          {:ok, fwdbwd_result} = Task.await(fwdbwd_task, :infinity)

          # 8. Merge custom telemetry into result
          merged_metrics = Map.merge(fwdbwd_result.metrics, telemetry)
          {:ok, %{fwdbwd_result | metrics: merged_metrics}}

        rescue
          e ->
            {:error, %Error{message: "Custom loss failed: #{Exception.message(e)}", type: :request_failed}}
        end

      try do
        GenServer.reply(from, reply)
      rescue
        ArgumentError -> :ok
      end
    end)

    {:noreply, state}
  end
end

defp extract_logprobs_as_nx(%ForwardBackwardOutput{loss_fn_outputs: outputs}) do
  Enum.map(outputs, fn output ->
    output["logprobs"]
    |> Tinkex.Types.TensorData.to_nx()
  end)
end

defp linearize_gradients(data, grads) do
  Enum.zip(data, grads)
  |> Enum.map(fn {datum, grad} ->
    # Negate gradient (as in Python: weights = -grad)
    neg_grad = Nx.negate(grad)
    weight_tensor = Tinkex.Types.TensorData.from_nx(neg_grad)

    %{datum |
      loss_fn_inputs: Map.put(datum.loss_fn_inputs, "weights", weight_tensor)
    }
  end)
end
```

---

## Nx.Defn Gradient Computation

### GradComputer Module

```elixir
defmodule Tinkex.CustomLoss.GradComputer do
  @moduledoc """
  Gradient computation using Nx.Defn autodiff.

  Requires EXLA backend for `Nx.Defn.grad/2` to work.
  """

  import Nx.Defn

  @doc """
  Compute gradients for all regularizers.

  Returns {total_loss, gradients, telemetry}.
  """
  @spec compute_gradients(
    list(Nx.Tensor.t()),
    list(map()),
    map() | nil
  ) :: {Nx.Tensor.t(), list(Nx.Tensor.t()), map()}
  def compute_gradients(logprobs_list, reg_results, base_result) do
    # Combine logprobs into single tensor for gradient computation
    # This is tricky because we need gradients w.r.t. each logprob tensor

    # Compute total loss
    {total_loss, telemetry} = compute_total_loss(reg_results, base_result)

    # Compute gradients using Nx.Defn.grad
    # We need to trace through the loss computation
    grads = compute_grads_per_logprob(logprobs_list, reg_results, base_result)

    {total_loss, grads, telemetry}
  end

  defp compute_total_loss(reg_results, base_result) do
    # Sum weighted regularizer losses
    reg_total =
      Enum.reduce(reg_results, Nx.tensor(0.0), fn result, acc ->
        weighted = Nx.multiply(result.loss, result.weight)
        Nx.add(acc, weighted)
      end)

    # Add base loss if present
    total =
      if base_result do
        Nx.add(reg_total, base_result.loss)
      else
        reg_total
      end

    # Build telemetry
    telemetry = build_telemetry(reg_results, base_result, total)

    {total, telemetry}
  end

  @doc """
  Compute gradient of total loss w.r.t. each logprob tensor.

  This is the core autodiff operation requiring EXLA.
  """
  def compute_grads_per_logprob(logprobs_list, reg_results, base_result) do
    # For each logprob tensor, compute ∂total_loss/∂logprob
    Enum.with_index(logprobs_list)
    |> Enum.map(fn {logprob, idx} ->
      # Create a function that computes total loss from this logprob
      loss_fn = fn lp ->
        # Re-run regularizers with this specific logprob
        compute_loss_for_logprob(lp, idx, reg_results, base_result)
      end

      # Compute gradient using Nx.Defn.grad
      grad_fn = Nx.Defn.grad(loss_fn)
      grad_fn.(logprob)
    end)
  end

  # This needs to be a defn to participate in autodiff
  defn compute_loss_for_logprob(logprob, idx, reg_results, base_result) do
    # Note: This is simplified. Real implementation needs to handle
    # the fact that regularizer fns may not be defn-compatible.
    # See "Limitations" section below.
    Nx.sum(logprob)  # Placeholder
  end

  defp build_telemetry(reg_results, base_result, total_loss) do
    reg_telemetry =
      Map.new(reg_results, fn result ->
        {result.name, %{
          "value" => Nx.to_number(result.loss),
          "weight" => result.weight,
          "contribution" => Nx.to_number(Nx.multiply(result.loss, result.weight)),
          "custom" => result.metrics
        }}
      end)

    base_telemetry =
      if base_result do
        %{"base_loss" => %{
          "value" => Nx.to_number(base_result.loss),
          "custom" => base_result.metrics
        }}
      else
        %{}
      end

    %{
      "loss_total" => Nx.to_number(total_loss),
      "regularizers" => reg_telemetry,
      "regularizer_total" => compute_reg_total(reg_results)
    }
    |> Map.merge(base_telemetry)
  end

  defp compute_reg_total(reg_results) do
    Enum.reduce(reg_results, 0.0, fn result, acc ->
      acc + Nx.to_number(Nx.multiply(result.loss, result.weight))
    end)
  end
end
```

### Critical Limitation: Defn Compatibility

**Problem**: User-defined regularizer functions likely use arbitrary Elixir code that is NOT `defn`-compatible.

`Nx.Defn.grad/2` only works on `defn` functions that use Nx operations. If the user's regularizer does:
```elixir
def my_regularizer(logprobs, data) do
  # This calls external library - NOT defn-compatible
  topology = GUDHI.compute_persistence(data)
  loss = process_topology(topology, logprobs)
  {loss, %{}}
end
```

This **cannot** be traced by Nx autodiff.

### Solution: Two-Phase Gradient Computation

```elixir
defmodule Tinkex.CustomLoss.GradComputer do
  @moduledoc """
  Two-phase gradient computation for arbitrary regularizers.

  Phase 1: User computes loss (any Elixir code allowed)
  Phase 2: We compute ∂loss/∂logprobs numerically or via chain rule
  """

  @doc """
  Compute gradients for user-defined loss.

  If the loss is a simple function of logprobs (sum, mean, etc.),
  we can use symbolic differentiation.

  For complex losses, we use numerical differentiation.
  """
  def compute_gradients_flexible(logprobs_list, reg_results, base_result, opts \\ []) do
    method = Keyword.get(opts, :grad_method, :numerical)

    grads =
      case method do
        :numerical ->
          compute_numerical_gradients(logprobs_list, reg_results, base_result)

        :symbolic ->
          # Only works if regularizers return defn-compatible loss
          compute_symbolic_gradients(logprobs_list, reg_results, base_result)

        :hybrid ->
          # User provides gradient function alongside loss
          compute_hybrid_gradients(logprobs_list, reg_results, base_result)
      end

    {compute_total_loss(reg_results, base_result), grads, build_telemetry(reg_results, base_result)}
  end

  @doc """
  Numerical gradient via finite differences.

  ∂f/∂x ≈ (f(x + ε) - f(x - ε)) / (2ε)

  Slow but works for ANY function.
  """
  def compute_numerical_gradients(logprobs_list, reg_results, base_result) do
    epsilon = 1.0e-5

    Enum.map(logprobs_list, fn logprob ->
      shape = Nx.shape(logprob)
      flat_size = Tuple.product(shape)

      # For each element, compute partial derivative
      grads =
        for i <- 0..(flat_size - 1) do
          # f(x + ε)
          plus = perturb_at(logprob, i, epsilon)
          loss_plus = recompute_total_loss(plus, reg_results, base_result)

          # f(x - ε)
          minus = perturb_at(logprob, i, -epsilon)
          loss_minus = recompute_total_loss(minus, reg_results, base_result)

          # Central difference
          (Nx.to_number(loss_plus) - Nx.to_number(loss_minus)) / (2 * epsilon)
        end

      grads
      |> Nx.tensor()
      |> Nx.reshape(shape)
    end)
  end

  defp perturb_at(tensor, index, delta) do
    flat = Nx.flatten(tensor)
    current = Nx.to_number(Nx.slice(flat, [index], [1]))
    updated = Nx.indexed_put(flat, Nx.tensor([[index]]), Nx.tensor([current + delta]))
    Nx.reshape(updated, Nx.shape(tensor))
  end
end
```

### Performance Implications

| Method | Accuracy | Speed | Defn Required |
|--------|----------|-------|---------------|
| Symbolic (Nx.Defn.grad) | Exact | Fast | Yes |
| Numerical (finite diff) | ~1e-5 error | O(n) slower | No |
| Hybrid (user provides) | User-controlled | Fast | Partial |

**Recommendation**: Support all three methods. Default to numerical for flexibility, allow symbolic for performance-critical defn-compatible regularizers.

---

## Type System Integration

### New Types

Create `lib/tinkex/types/custom_loss_types.ex`:

```elixir
defmodule Tinkex.Types.CustomLossTypes do
  @moduledoc """
  Types for custom loss functionality.
  """

  alias Tinkex.CustomLoss.RegularizerSpec

  @type regularizer_result :: %{
    name: String.t(),
    loss: Nx.Tensor.t(),
    weight: float(),
    metrics: map()
  }

  @type custom_loss_telemetry :: %{
    String.t() => %{
      String.t() => float() | map()
    }
  }

  @type gradient_method :: :numerical | :symbolic | :hybrid
end
```

### Extend ForwardBackwardOutput

The existing `ForwardBackwardOutput` already has `metrics: %{String.t() => float()}`.

For custom loss, we need nested metrics. Options:

1. **Keep flat, namespace keys**: `"regularizers.topology.value"`
2. **Change type to allow nesting**: `metrics: %{String.t() => term()}`
3. **Add separate field**: `custom_loss_telemetry: map()`

**Recommendation**: Option 2 (allow nesting) matches Python behavior.

---

## Telemetry Integration

### Telemetry Events

Add to `lib/tinkex/telemetry.ex`:

```elixir
defmodule Tinkex.Telemetry do
  # ... existing code ...

  @doc """
  Emit custom loss regularizer metrics.
  """
  def emit_regularizer_metrics(regularizer_name, metrics, metadata \\ %{}) do
    :telemetry.execute(
      [:tinkex, :training, :custom_loss, :regularizer],
      metrics,
      Map.merge(metadata, %{regularizer: regularizer_name})
    )
  end

  @doc """
  Emit custom loss gradient computation timing.
  """
  def emit_gradient_computation(duration_ms, method, metadata \\ %{}) do
    :telemetry.execute(
      [:tinkex, :training, :custom_loss, :gradient],
      %{duration_ms: duration_ms},
      Map.merge(metadata, %{method: method})
    )
  end
end
```

### Telemetry Output Schema

```elixir
%{
  "loss_total" => 2.847,
  "base_loss" => %{
    "value" => 2.5,
    "custom" => %{"perplexity" => 12.18}
  },
  "regularizers" => %{
    "topology" => %{
      "value" => 1.23,
      "weight" => 0.1,
      "contribution" => 0.123,
      "custom" => %{"beta_1_mean" => 3.2}
    },
    "sparsity" => %{
      "value" => 22.4,
      "weight" => 0.01,
      "contribution" => 0.224,
      "custom" => %{"l1_norm" => 22.4}
    }
  },
  "regularizer_total" => 0.347,
  "gradient_method" => "numerical",
  "gradient_duration_ms" => 45.2
}
```

---

## Testing Strategy

### Unit Tests

```elixir
defmodule Tinkex.CustomLoss.GradComputerTest do
  use ExUnit.Case

  alias Tinkex.CustomLoss.{GradComputer, RegularizerSpec}

  describe "compute_numerical_gradients/3" do
    test "computes correct gradients for sum loss" do
      logprobs = [Nx.tensor([1.0, 2.0, 3.0])]

      reg = RegularizerSpec.sync("sum", 1.0, fn [lp], _data ->
        {Nx.sum(lp), %{}}
      end)

      reg_results = [%{name: "sum", loss: Nx.tensor(6.0), weight: 1.0, metrics: %{}}]

      grads = GradComputer.compute_numerical_gradients(logprobs, reg_results, nil)

      # ∂sum/∂x = [1, 1, 1]
      assert_all_close(hd(grads), Nx.tensor([1.0, 1.0, 1.0]), atol: 1.0e-4)
    end

    test "computes correct gradients for weighted mean" do
      logprobs = [Nx.tensor([2.0, 4.0])]

      reg_results = [%{name: "mean", loss: Nx.tensor(3.0), weight: 0.5, metrics: %{}}]

      grads = GradComputer.compute_numerical_gradients(logprobs, reg_results, nil)

      # ∂(0.5 * mean)/∂x = [0.25, 0.25]
      assert_all_close(hd(grads), Nx.tensor([0.25, 0.25]), atol: 1.0e-4)
    end
  end

  describe "compute_symbolic_gradients/3" do
    test "uses Nx.Defn.grad for defn-compatible losses" do
      # Only test if EXLA is available
      if Code.ensure_loaded?(EXLA) do
        logprobs = [Nx.tensor([1.0, 2.0, 3.0])]

        # defn-compatible regularizer
        defmodule TestReg do
          import Nx.Defn

          defn sum_loss(logprobs) do
            Nx.sum(hd(logprobs))
          end
        end

        grads = GradComputer.compute_symbolic_gradients(logprobs, [...], nil)

        assert_all_close(hd(grads), Nx.tensor([1.0, 1.0, 1.0]))
      end
    end
  end
end
```

### Integration Tests

```elixir
defmodule Tinkex.TrainingClientCustomLossTest do
  use ExUnit.Case

  alias Tinkex.{TrainingClient, CustomLoss.RegularizerSpec}

  @tag :integration
  test "forward_backward_custom with single regularizer" do
    {:ok, client} = start_training_client()

    regularizers = [
      RegularizerSpec.sync("l1", 0.01, fn logprobs, _data ->
        loss = logprobs |> Enum.map(&Nx.sum(Nx.abs(&1))) |> Enum.reduce(&Nx.add/2)
        {loss, %{"l1_total" => Nx.to_number(loss)}}
      end)
    ]

    {:ok, task} = TrainingClient.forward_backward_custom(client, data, regularizers: regularizers)
    {:ok, result} = Task.await(task)

    assert Map.has_key?(result.metrics, "regularizers")
    assert Map.has_key?(result.metrics["regularizers"], "l1")
  end
end
```

---

## Migration Path

### Phase 1: Add EXLA (v2.0-alpha)

1. Add `{:exla, "~> 0.7"}` to `mix.exs`
2. Configure EXLA backend
3. Run existing tests to ensure no regressions

### Phase 2: Expose Forward (v2.0-beta)

1. Add `forward/4` to TrainingClient
2. Add handler in GenServer
3. Add tests for forward-only path

### Phase 3: Core Custom Loss (v2.0-rc)

1. Add `GradComputer` module with numerical gradients
2. Add `RegularizerSpec` type
3. Add `forward_backward_custom/3` to TrainingClient
4. Add telemetry integration
5. Comprehensive tests

### Phase 4: Structured Regularizers (v2.0)

1. Add `Runner` module for async regularizers
2. Add per-regularizer telemetry
3. Documentation and examples
4. Performance optimization (symbolic gradients for defn fns)

---

## Risk Analysis

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| EXLA adds significant size | Certain | Medium | Document trade-off; optional dep? |
| Numerical gradients too slow | Medium | High | Support symbolic for defn fns |
| User fns break gradient computation | High | Medium | Clear docs; error handling |
| Async regularizers timeout | Medium | Medium | Configurable timeouts; supervision |

### Compatibility Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| EXLA version conflicts | Low | High | Pin compatible versions |
| Nx API changes | Low | Medium | Version constraints |
| ForwardBackwardOutput schema change | Low | Low | Backward-compat nesting |

### Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CPU-only performance issues | Medium | Medium | Document GPU benefits |
| Memory usage with large batches | Medium | Medium | Chunking; streaming |

---

## Appendix: Code Examples

### Example 1: Sparsity Regularizer

```elixir
defmodule MyRegularizers do
  alias Tinkex.CustomLoss.RegularizerSpec

  def sparsity(weight \\ 0.01) do
    RegularizerSpec.sync("sparsity", weight, fn logprobs_list, _data ->
      l1_norms = Enum.map(logprobs_list, fn lp ->
        Nx.sum(Nx.abs(lp))
      end)

      total = Enum.reduce(l1_norms, Nx.tensor(0.0), &Nx.add/2)
      mean = Nx.divide(total, length(logprobs_list))

      metrics = %{
        "l1_total" => Nx.to_number(total),
        "l1_mean" => Nx.to_number(mean)
      }

      {mean, metrics}
    end)
  end
end
```

### Example 2: Async External Service Regularizer

```elixir
defmodule MyRegularizers do
  alias Tinkex.CustomLoss.RegularizerSpec

  def knowledge_consistency(weight \\ 0.05) do
    RegularizerSpec.async("kb", weight, fn logprobs_list, data ->
      # Returns a Task
      Task.async(fn ->
        # Query external knowledge base
        claims = extract_claims(data)

        results =
          claims
          |> Enum.map(&verify_claim_async/1)
          |> Enum.map(&Task.await/1)

        # Compute penalty for unverified claims
        penalties = Enum.map(results, fn
          %{verified: true} -> Nx.tensor(0.0)
          %{verified: false, confidence: c} -> Nx.tensor(c)
        end)

        loss = penalties |> Nx.stack() |> Nx.mean()

        verified_count = Enum.count(results, & &1.verified)

        metrics = %{
          "verified_ratio" => verified_count / length(results),
          "penalty_mean" => Nx.to_number(loss)
        }

        {loss, metrics}
      end)
    end)
  end
end
```

### Example 3: Full Training Loop

```elixir
defmodule MyTraining do
  alias Tinkex.{ServiceClient, TrainingClient, CustomLoss.RegularizerSpec}

  def train(data_batches, opts \\ []) do
    {:ok, service} = ServiceClient.start_link(opts)
    {:ok, training} = ServiceClient.create_lora_training_client(service,
      base_model: "Qwen/Qwen2.5-7B"
    )

    regularizers = [
      MyRegularizers.sparsity(0.01),
      MyRegularizers.knowledge_consistency(0.05)
    ]

    for {batch, epoch} <- Enum.with_index(data_batches) do
      # Forward-backward with custom loss
      {:ok, fwdbwd_task} = TrainingClient.forward_backward_custom(
        training,
        batch,
        regularizers: regularizers,
        grad_method: :numerical
      )

      # Optimizer step
      {:ok, optim_task} = TrainingClient.optim_step(training, %{
        learning_rate: 1.0e-4,
        weight_decay: 0.01
      })

      # Await results
      {:ok, fwdbwd_result} = Task.await(fwdbwd_task)
      {:ok, _optim_result} = Task.await(optim_task)

      # Log structured metrics
      IO.puts("Epoch #{epoch}: loss=#{fwdbwd_result.metrics["loss_total"]}")

      for {name, reg_metrics} <- fwdbwd_result.metrics["regularizers"] do
        IO.puts("  #{name}: value=#{reg_metrics["value"]}, contribution=#{reg_metrics["contribution"]}")
      end
    end
  end
end
```

---

## References

- Python design: `../tinker/structured-regularizers/README.md`
- Tinkex TrainingClient: `lib/tinkex/training_client.ex`
- Tinkex Training API: `lib/tinkex/api/training.ex`
- Nx documentation: https://hexdocs.pm/nx
- EXLA documentation: https://hexdocs.pm/exla
- Original porting strategy: `docs/20251119/port_research/07_porting_strategy.md`
