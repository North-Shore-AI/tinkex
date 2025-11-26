# Structured Regularizers for Tinker Custom Loss

**Design Document for Python SDK Enhancement**

**Status:** Proposed
**Issue Reference:** thinking-machines-lab/tinker-feedback#27
**Related Python Source:** `src/tinker/lib/public_interfaces/training_client.py:328-413`
**Author:** nshkrdotcom
**Date:** 2025-11-25

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Problem Statement](#problem-statement)
4. [Proposed Solution](#proposed-solution)
5. [API Design](#api-design)
6. [Implementation Details](#implementation-details)
7. [Telemetry Schema](#telemetry-schema)
8. [Examples](#examples)
9. [Migration Path](#migration-path)
10. [Tinkex Implications](#tinkex-implications)
11. [Open Questions](#open-questions)

---

## Executive Summary

This document specifies enhancements to Tinker's Python SDK to promote custom loss functionality from an internal mechanism to a first-class, documented research extensibility feature. The primary additions are:

1. **Structured regularizer composition** - multiple named regularizers with independent weights
2. **Async-capable callbacks** - support for async regularizer functions
3. **Enhanced telemetry** - per-regularizer metrics with namespaced keys
4. **Backward compatibility** - existing `CustomLossFnV1` API continues to work

---

## Current State Analysis

### Existing Implementation

The Python SDK currently provides custom loss capability through two methods in `TrainingClient`:

**File:** `src/tinker/lib/public_interfaces/training_client.py`

```python
# Line 47: Type definition
CustomLossFnV1 = Callable[[List[types.Datum], List[Any]], Tuple[Any, Dict[str, float]]]

# Lines 328-361: Sync wrapper
@sync_only
@capture_exceptions(fatal=True)
def forward_backward_custom(
    self, data: List[types.Datum], loss_fn: CustomLossFnV1
) -> APIFuture[types.ForwardBackwardOutput]:
    """Compute forward/backward with a custom loss function."""
    return self.holder.run_coroutine_threadsafe(
        self.forward_backward_custom_async(data, loss_fn)
    ).result()

# Lines 363-412: Async implementation
@capture_exceptions(fatal=True)
async def forward_backward_custom_async(
    self, data: List[types.Datum], loss_fn: CustomLossFnV1
) -> APIFuture[types.ForwardBackwardOutput]:
    """Async version of forward_backward_custom."""
    import torch

    # 1. Forward pass to get logprobs
    forward_future = await self.forward_async(data, "cross_entropy")
    forward_result = await forward_future.result_async()

    # 2. Convert logprobs to tensors with gradients
    logprobs_list: List[torch.Tensor] = []
    for out in forward_result.loss_fn_outputs:
        logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)
        logprobs_list.append(logprob)

    # 3. Apply user-provided loss function
    loss, metrics = loss_fn(data, logprobs_list)

    # 4. Compute gradients via PyTorch autograd
    loss.backward()
    grads = []
    for logprob in logprobs_list:
        if logprob.grad is None:
            raise ValueError("No gradient computed for logprob tensor")
        grads.append(logprob.grad)

    # 5. Linearize: convert grads to weights for standard forward_backward
    linear_loss_data = []
    for datum, grad in zip(data, grads):
        loss_fn_inputs: Any = {
            "target_tokens": datum.loss_fn_inputs["target_tokens"],
            "weights": -grad,  # Pass gradients as weights
        }
        linear_loss_data.append(
            types.Datum(
                model_input=datum.model_input,
                loss_fn_inputs=loss_fn_inputs,
            )
        )

    # 6. Server-side backward pass with linearized gradients
    backward_future = await self.forward_backward_async(linear_loss_data, "cross_entropy")

    # 7. Merge custom metrics into result
    def add_custom_metrics(results: List[types.ForwardBackwardOutput]) -> types.ForwardBackwardOutput:
        result = results[0]
        result.metrics.update(metrics)
        return result

    return _CombinedAPIFuture([backward_future], add_custom_metrics, self.holder)
```

### Key Architectural Insight: The Linearization Trick

The custom loss mechanism uses a clever linearization approach:

1. **Forward pass** returns log-probabilities for each token
2. **User callback** computes arbitrary loss function on logprobs using PyTorch
3. **Autograd** computes ∂loss/∂logprobs locally (client-side)
4. **Linearization**: Gradients are passed as "weights" to a standard forward_backward call
5. **Server** performs backward pass using these weights, computing ∂loss/∂params

This separation means:
- **Expensive domain-specific computation** (topology, logic checking, KB queries) runs client-side where specialized libraries are available
- **Gradient computation through the model** runs on Tinker infrastructure
- **No modification to the server-side training API** is required

### Current Types

**`ForwardBackwardOutput`** (`src/tinker/types/forward_backward_output.py`):
```python
class ForwardBackwardOutput(BaseModel):
    loss_fn_output_type: str
    loss_fn_outputs: List[LossFnOutput]
    metrics: Dict[str, float]  # <-- custom metrics merged here
```

**`LossFnType`** (`src/tinker/types/loss_fn_type.py`):
```python
LossFnType: TypeAlias = Literal["cross_entropy", "importance_sampling", "ppo", "cispo", "dro"]
```

### Current Documentation

**File:** `docs/api/trainingclient.md:126-168`

The existing docs show only the simple single-callback interface:
```python
def custom_loss(data, logprobs_list):
    loss = torch.mean(torch.stack([torch.mean(lp) for lp in logprobs_list]))
    metrics = {"custom_metric": loss.item()}
    return loss, metrics

future = training_client.forward_backward_custom(data, custom_loss)
```

---

## Problem Statement

The current implementation has several limitations identified in the original issue:

### 1. Discoverability

> "Researchers exploring Tinker's capabilities for projects requiring structured regularization have no clear path to this functionality without reading TrainingClient internals. The custom loss mechanism is not positioned in documentation as a core research extensibility point."

The capability exists but is under-documented and positioned as an advanced internal feature rather than a first-class research tool.

### 2. Monolithic Callbacks

> "The callback signature handles all custom loss computation as a single monolithic function. For research projects requiring multiple regularization terms with different conceptual purposes, this forces researchers to manually compose and weight components within their callback, then manually decompose metrics for logging."

Example research scenario requiring multiple regularizers:
- **Topological consistency** - Betti numbers via persistent homology
- **Sparsity constraints** - L1 penalties on activations
- **Fairness regularizers** - Demographic parity constraints
- Each needs independent hyperparameter tuning and ablation

### 3. Synchronous Execution Bottleneck

> "Computing Betti numbers via persistent homology, running SMT solvers for logical consistency checks, or querying external knowledge bases can take seconds per batch. When these computations execute synchronously within the event loop, they block all other training operations."

The current callback is sync-only (note `@sync_only` decorator on `forward_backward_custom`). Even `forward_backward_custom_async` executes the user callback synchronously.

### 4. Unstructured Telemetry

> "Metrics returned from callbacks appear in logs, but the system provides no standardized way to track individual regularizer contributions, compare their relative magnitudes, or analyze how their weights affect training dynamics."

Currently metrics are just `Dict[str, float]` merged flat - no structure for per-regularizer tracking.

---

## Proposed Solution

### Design Goals

1. **Structured regularizer composition**: Accept a list of named regularizers with independent weights
2. **Async-capable callbacks**: Support `async` regularizer functions natively
3. **Enhanced telemetry**: Return per-regularizer metrics with namespaced keys plus totals
4. **Backward compatibility**: Keep existing `CustomLossFnV1` and `forward_backward_custom` working unchanged
5. **Minimal transport changes**: Reuse the existing linearization mechanism

### Non-Goals (This Pass)

- **Thread/process pool offload**: Optional enhancement, can defer
- **Automatic ablation tooling**: Users toggle regularizers via config; no built-in runner
- **New transport protocol**: Reuse "client computes grads, server consumes weights" pattern
- **Gradient norm telemetry**: Nice-to-have, can add later

---

## API Design

### New Type Definitions

Add to `src/tinker/lib/public_interfaces/training_client.py`:

```python
from typing import Union, Awaitable

# Single regularizer spec
RegularizerSpec = TypedDict("RegularizerSpec", {
    "fn": Callable[[List[types.Datum], List[torch.Tensor]], Union[
        Tuple[torch.Tensor, Dict[str, float]],
        Awaitable[Tuple[torch.Tensor, Dict[str, float]]]
    ]],
    "weight": float,
    "name": str,
})

# Type for regularizer list
RegularizerList = List[RegularizerSpec]
```

### Extended Method Signature

```python
@capture_exceptions(fatal=True)
async def forward_backward_custom_async(
    self,
    data: List[types.Datum],
    loss_fn: CustomLossFnV1 | None = None,           # Legacy single callback (optional)
    regularizers: RegularizerList | None = None,     # NEW: structured regularizers
) -> APIFuture[types.ForwardBackwardOutput]:
    """
    Compute forward/backward with custom loss function(s).

    Supports two modes:
    1. Legacy: Single `loss_fn` callback (backward compatible)
    2. Structured: List of named `regularizers` with independent weights

    When using structured regularizers, the total loss is computed as:
        loss_total = base_loss + Σ (weight_i * regularizer_i_loss)

    Each regularizer function receives (data, logprobs_list) and returns
    (loss_tensor, metrics_dict). Regularizers may be async functions.

    Args:
        data: List of training data samples
        loss_fn: Legacy single loss function (optional, for backward compat)
        regularizers: List of regularizer specs with fn, weight, name

    Returns:
        APIFuture containing ForwardBackwardOutput with structured metrics

    Example (structured regularizers):
        regularizers = [
            {
                "fn": topological_consistency,
                "weight": 0.1,
                "name": "topology"
            },
            {
                "fn": sparsity_penalty,
                "weight": 0.01,
                "name": "sparsity"
            }
        ]
        future = await client.forward_backward_custom_async(
            data, regularizers=regularizers
        )
    """
```

### Backward Compatibility

The sync wrapper maintains compatibility:

```python
@sync_only
@capture_exceptions(fatal=True)
def forward_backward_custom(
    self,
    data: List[types.Datum],
    loss_fn: CustomLossFnV1 | None = None,
    regularizers: RegularizerList | None = None,
) -> APIFuture[types.ForwardBackwardOutput]:
    """Sync version of forward_backward_custom_async."""
    return self.holder.run_coroutine_threadsafe(
        self.forward_backward_custom_async(data, loss_fn, regularizers)
    ).result()
```

When called with only `loss_fn` (no `regularizers`), behavior is identical to current.

---

## Implementation Details

### Updated Async Implementation

```python
@capture_exceptions(fatal=True)
async def forward_backward_custom_async(
    self,
    data: List[types.Datum],
    loss_fn: CustomLossFnV1 | None = None,
    regularizers: RegularizerList | None = None,
) -> APIFuture[types.ForwardBackwardOutput]:
    import torch
    import asyncio
    import inspect

    # Validate: at least one of loss_fn or regularizers must be provided
    if loss_fn is None and (regularizers is None or len(regularizers) == 0):
        raise ValueError("Must provide either loss_fn or regularizers")

    # 1. Forward pass to get logprobs
    forward_future = await self.forward_async(data, "cross_entropy")
    forward_result = await forward_future.result_async()

    logprobs_list: List[torch.Tensor] = []
    for out in forward_result.loss_fn_outputs:
        logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)
        logprobs_list.append(logprob)

    # 2. Compute losses from regularizers and/or legacy loss_fn
    total_loss = torch.tensor(0.0, requires_grad=True)
    all_metrics: Dict[str, Any] = {}
    regularizer_metrics: Dict[str, Dict[str, float]] = {}
    regularizer_total = 0.0

    # 2a. Legacy loss_fn (if provided)
    if loss_fn is not None:
        base_loss, base_metrics = loss_fn(data, logprobs_list)
        total_loss = total_loss + base_loss
        all_metrics["base_loss"] = {
            "value": base_loss.item(),
            "custom": base_metrics,
        }

    # 2b. Structured regularizers (if provided)
    if regularizers:
        for reg_spec in regularizers:
            fn = reg_spec["fn"]
            weight = reg_spec["weight"]
            name = reg_spec["name"]

            # Support async regularizers
            if inspect.iscoroutinefunction(fn):
                reg_loss, reg_metrics = await fn(data, logprobs_list)
            else:
                reg_loss, reg_metrics = fn(data, logprobs_list)

            weighted_loss = weight * reg_loss
            total_loss = total_loss + weighted_loss

            contribution = weighted_loss.item()
            regularizer_total += contribution

            regularizer_metrics[name] = {
                "value": reg_loss.item(),
                "weight": weight,
                "contribution": contribution,
                "custom": reg_metrics,
            }

    all_metrics["regularizers"] = regularizer_metrics
    all_metrics["regularizer_total"] = regularizer_total
    all_metrics["loss_total"] = total_loss.item()

    # 3. Compute gradients via PyTorch autograd
    total_loss.backward()

    grads = []
    for logprob in logprobs_list:
        if logprob.grad is None:
            raise ValueError("No gradient computed for logprob tensor")
        grads.append(logprob.grad)

    # 4. Linearize gradients as weights
    linear_loss_data = []
    for datum, grad in zip(data, grads):
        loss_fn_inputs: Any = {
            "target_tokens": datum.loss_fn_inputs["target_tokens"],
            "weights": -grad,
        }
        linear_loss_data.append(
            types.Datum(
                model_input=datum.model_input,
                loss_fn_inputs=loss_fn_inputs,
            )
        )

    # 5. Server-side backward pass
    backward_future = await self.forward_backward_async(linear_loss_data, "cross_entropy")

    # 6. Merge structured metrics
    def add_custom_metrics(results: List[types.ForwardBackwardOutput]) -> types.ForwardBackwardOutput:
        result = results[0]
        result.metrics.update(all_metrics)
        return result

    return _CombinedAPIFuture([backward_future], add_custom_metrics, self.holder)
```

### Key Implementation Notes

1. **Async detection**: Use `inspect.iscoroutinefunction(fn)` to detect async regularizers
2. **Gradient accumulation**: All losses contribute to `total_loss` before single `.backward()` call
3. **Metric namespacing**: Each regularizer's metrics stored under `regularizers[name]`
4. **Type preservation**: `total_loss` starts as `torch.tensor(0.0, requires_grad=True)` to accumulate

---

## Telemetry Schema

### Output Metrics Structure

```python
{
    # Total loss across all components
    "loss_total": float,

    # Base loss (if legacy loss_fn provided)
    "base_loss": {
        "value": float,
        "custom": Dict[str, float]  # metrics from loss_fn
    },

    # Structured regularizers
    "regularizers": {
        "<name>": {
            "value": float,           # raw loss_i before weighting
            "weight": float,          # weight applied
            "contribution": float,    # weight * value
            "custom": Dict[str, float]  # metrics from regularizer fn
        },
        # ... for each regularizer
    },

    # Sum of all regularizer contributions
    "regularizer_total": float,

    # Any additional metrics from server-side forward_backward
    ...
}
```

### Example Telemetry Output

```json
{
    "loss_total": 2.847,
    "base_loss": {
        "value": 2.5,
        "custom": {"perplexity": 12.18}
    },
    "regularizers": {
        "topology": {
            "value": 1.23,
            "weight": 0.1,
            "contribution": 0.123,
            "custom": {"beta_1_mean": 3.2, "num_components": 5}
        },
        "sparsity": {
            "value": 22.4,
            "weight": 0.01,
            "contribution": 0.224,
            "custom": {"l1_norm": 22.4, "nonzero_frac": 0.73}
        }
    },
    "regularizer_total": 0.347
}
```

---

## Examples

### Example 1: Topological Consistency Regularizer

```python
import torch
from gudhi import RipsComplex  # Topological data analysis

def topological_consistency(data: List[types.Datum], logprobs_list: List[torch.Tensor]):
    """
    Penalize reasoning structures that lack topological coherence.
    Uses persistent homology to measure structural complexity.
    """
    # Extract reasoning graph from outputs (domain-specific)
    graphs = extract_reasoning_graphs(data)

    # Compute Betti numbers via persistent homology
    betti_losses = []
    betti_1_values = []

    for graph in graphs:
        rips = RipsComplex(points=graph.node_embeddings)
        st = rips.create_simplex_tree(max_dimension=2)
        st.compute_persistence()

        # Penalize high Betti-1 (indicates loops/cycles in reasoning)
        betti_1 = len(st.persistence_intervals_in_dimension(1))
        betti_1_values.append(betti_1)
        betti_losses.append(torch.tensor(float(betti_1)))

    loss = torch.mean(torch.stack(betti_losses))
    metrics = {
        "beta_1_mean": sum(betti_1_values) / len(betti_1_values),
        "beta_1_max": max(betti_1_values),
    }

    return loss, metrics
```

### Example 2: Sparsity Penalty

```python
def sparsity_penalty(data: List[types.Datum], logprobs_list: List[torch.Tensor]):
    """
    L1 regularization on log-probability magnitudes.
    Encourages peaked, confident predictions.
    """
    l1_norms = []
    for logprobs in logprobs_list:
        l1_norm = torch.norm(logprobs, p=1)
        l1_norms.append(l1_norm)

    total_l1 = torch.sum(torch.stack(l1_norms))
    mean_l1 = total_l1 / len(logprobs_list)

    metrics = {
        "l1_total": total_l1.item(),
        "l1_mean": mean_l1.item(),
    }

    return mean_l1, metrics
```

### Example 3: Async Knowledge Base Query

```python
import aiohttp

async def knowledge_consistency(data: List[types.Datum], logprobs_list: List[torch.Tensor]):
    """
    Async regularizer that queries an external knowledge base.
    Penalizes outputs inconsistent with verified facts.
    """
    async with aiohttp.ClientSession() as session:
        # Extract claims from model outputs
        claims = extract_claims(data)

        # Query KB asynchronously
        verification_tasks = [
            verify_claim(session, claim) for claim in claims
        ]
        results = await asyncio.gather(*verification_tasks)

    # Penalize unverified claims
    penalties = []
    verified_count = 0
    for result in results:
        if result.verified:
            verified_count += 1
            penalties.append(torch.tensor(0.0))
        else:
            penalties.append(torch.tensor(result.confidence))

    loss = torch.mean(torch.stack(penalties))
    metrics = {
        "verified_ratio": verified_count / len(results),
        "penalty_mean": loss.item(),
    }

    return loss, metrics
```

### Example 4: Full Training Loop with Structured Regularizers

```python
from tinker import ServiceClient, types

# Initialize
service = ServiceClient()
training_client = service.create_lora_training_client(base_model="Qwen/Qwen2.5-7B")
tokenizer = training_client.get_tokenizer()

# Define regularizers
regularizers = [
    {"fn": topological_consistency, "weight": 0.1, "name": "topology"},
    {"fn": sparsity_penalty, "weight": 0.01, "name": "sparsity"},
    {"fn": knowledge_consistency, "weight": 0.05, "name": "kb_consistency"},  # async
]

# Training loop
for epoch in range(num_epochs):
    for batch in dataloader:
        data = prepare_data(batch, tokenizer)

        # Forward/backward with structured regularizers
        fwdbwd_future = await training_client.forward_backward_custom_async(
            data,
            regularizers=regularizers
        )

        # Optimizer step
        optim_future = training_client.optim_step(
            types.AdamParams(learning_rate=1e-4)
        )

        # Get results
        result = await fwdbwd_future
        await optim_future

        # Structured metrics available
        print(f"Total loss: {result.metrics['loss_total']:.4f}")
        print(f"Regularizer breakdown:")
        for name, reg_metrics in result.metrics['regularizers'].items():
            print(f"  {name}: value={reg_metrics['value']:.4f}, "
                  f"contribution={reg_metrics['contribution']:.4f}")
```

---

## Migration Path

### Backward Compatibility Guarantee

Existing code using the current API continues to work unchanged:

```python
# This still works exactly as before
def my_loss(data, logprobs_list):
    loss = compute_my_loss(logprobs_list)
    return loss, {"my_metric": loss.item()}

future = training_client.forward_backward_custom(data, my_loss)
```

### Gradual Adoption

1. **Phase 1**: Add structured regularizers support (this PR)
2. **Phase 2**: Migrate existing monolithic callbacks to structured form
3. **Phase 3**: Add optional async execution enhancements (thread pool)
4. **Phase 4**: Add gradient norm telemetry (nice-to-have)

---

## Tinkex Implications

### Current Tinkex State

Tinkex (Elixir backend) deliberately deferred custom loss support. From `lib/tinkex/types/loss_fn_type.ex`:

```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo
```

There is no custom loss hook, no forward-only path exposed, and no client-side gradient mechanism.

### Future Tinkex Options

Once Python ships structured regularizers, Tinkex has three paths:

1. **Add Nx/EXLA autograd support**
   - Expose forward-only API
   - Accept callbacks that compute on Nx tensors
   - Use Nx.Defn for autodiff
   - Matches Python architecture

2. **Require user-provided gradients**
   - Skip Nx autodiff entirely
   - User provides weights/gradients directly
   - Simpler but less ergonomic

3. **Defer to Python for custom losses**
   - Keep Tinkex for standard loss functions only
   - Researchers use Python SDK for custom loss experiments
   - Least implementation effort

**Recommendation**: Implement option 1 (Nx/EXLA) for parity, but defer until Python implementation is stable.

---

## Open Questions

### Must Answer Before Implementation

1. **Remove `@sync_only` decorator?**
   Currently `forward_backward_custom` is sync-only. Should the enhanced version support true async in the sync wrapper, or keep the restriction?

2. **Error handling for async regularizers?**
   If one async regularizer fails, should we:
   - Fail the entire batch?
   - Skip that regularizer and continue?
   - Return partial metrics with error flag?

3. **Regularizer execution order?**
   Async regularizers could run concurrently. Does order matter for gradient accumulation? (Answer: No, gradient accumulation is commutative)

### Nice-to-Have (Defer)

1. **Gradient norm telemetry**
   Track `grad_norm` per regularizer. Useful but adds complexity.

2. **Run-in-executor flag**
   `{"fn": heavy_sync_fn, "run_in_executor": True}` to offload CPU-bound sync functions.

3. **Config object alternative**
   Instead of function args, accept a `TrainingConfig` dataclass. More discoverable but more breaking.

4. **Regularizer disable flag**
   `{"fn": ..., "enabled": False}` for ablation studies without removing from list.

---

## References

- Original Issue: https://github.com/thinking-machines-lab/tinker-feedback/issues/27
- Python SDK: `src/tinker/lib/public_interfaces/training_client.py`
- API Docs: `docs/api/trainingclient.md`
- Types: `src/tinker/types/forward_backward_output.py`, `loss_fn_type.py`
- Tinkex: `lib/tinkex/types/loss_fn_type.ex`
