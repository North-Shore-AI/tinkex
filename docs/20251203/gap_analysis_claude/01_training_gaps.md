# Training Feature Gaps

## Overview

TrainingClient achieves ~85% parity. Core training loop (forward, backward, optim_step) is fully implemented. Gaps exist in advanced regularizer features.

## Fully Implemented (Parity)

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| `forward/3` | Lines 202-260 | Lines 240-247 | Full |
| `forward_backward/3` | Lines 282-354 | Lines 213-220 | Full |
| `forward_backward_custom/3` | Lines 358-607 | Lines 404-417 + CustomLoss | Full |
| `optim_step/3` | Lines 610-671 | Lines 255-259 | Full |
| `save_state/3` (save_weights) | Lines 674-723 | Lines 325-331 | Full |
| `load_state/3` (load_weights) | Lines 755-777 | Lines 339-345 | Full |
| `load_state_with_optimizer/3` | Lines 780-806 | Lines 353-360 | Full |
| `save_weights_for_sampler/3` | Lines 847-882 | Lines 272-279 | Full |
| `save_weights_and_get_sampling_client/3` | Lines 971-1023 | Lines 287-317 | Full |
| `get_info/1` | Lines 899-918 | Lines 84-92 | Full |
| `get_tokenizer/2` | Lines 922-935 | Lines 116-126 | Full |
| `create_sampling_client/2` | Lines 938-969 | Lines 372-377 | Full |

## Missing Features

### 1. Gradient Norm Tracking (High Priority)

**Python Implementation:**
```python
# training_client.py lines 484-596
def forward_backward_custom(..., track_grad_norms: bool = False):
    if track_grad_norms:
        # Compute L2 norm of gradients per-regularizer
        grad_norm = torch.linalg.vector_norm(gradient).item()
        grad_norm_weighted = grad_norm * weight
```

**Python Output Structure:**
```python
{
    "regularizers": {
        "<name>": {
            "value": float,
            "weight": float,
            "contribution": float,
            "grad_norm": float,           # MISSING
            "grad_norm_weighted": float,  # MISSING
            "custom": dict
        }
    },
    "total_grad_norm": float  # MISSING
}
```

**Elixir Status:** Not implemented

**Implementation Recommendation:**
Add to `Tinkex.CustomLoss`:
```elixir
defp compute_gradient_norms(regularizer_grads, track_norms?) when track_norms? do
  Enum.map(regularizer_grads, fn {name, grad, weight} ->
    norm = Nx.LinAlg.norm(grad) |> Nx.to_number()
    {name, %{grad_norm: norm, grad_norm_weighted: norm * weight}}
  end)
end
```

### 2. Thread Pool Regularizer Execution (Low Priority)

**Python Implementation:**
```python
# training_client.py line 365, 501-507
run_sync_in_executor: bool = False

async def _maybe_run_in_executor(fn, *args):
    if run_sync_in_executor and not inspect.iscoroutinefunction(fn):
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, fn, *args)
```

**Elixir Status:** Not implemented

**Note:** Less critical in Elixir due to BEAM's lightweight process model. Regularizers can be spawned as Tasks for parallelism:
```elixir
regularizers
|> Task.async_stream(&compute_regularizer/1)
|> Enum.to_list()
```

### 3. Automatic Async Detection (Low Priority)

**Python:** Uses `inspect.iscoroutinefunction()` to auto-detect async regularizers

**Elixir:** Uses explicit `async: boolean` flag in `RegularizerSpec`

**Recommendation:** Keep explicit flag - more idiomatic in Elixir

## Elixir-Only Features (Improvements)

| Feature | Description |
|---------|-------------|
| `encode/3`, `decode/3` | Integrated tokenizer helpers on TrainingClient |
| `unload_model/2` | Explicit model unloading (not exposed in Python TrainingClient) |

## Files Reference

- Python: `tinker/lib/public_interfaces/training_client.py`
- Elixir: `lib/tinkex/training_client.ex`, `lib/tinkex/custom_loss.ex`
