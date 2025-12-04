# API Function Gap Analysis

**Date**: December 4, 2025

---

## Summary

| Category | Python Functions | Elixir Functions | Gap |
|----------|-----------------|------------------|-----|
| Training Operations | 8 | 12 | +4 (enhanced) |
| Weight Operations | 6 | 12 | +6 (enhanced) |
| Sampling Operations | 4 | 2 | -2 (missing) |
| REST Operations | 28 | 28 | 0 |
| Service Operations | 4 | 4 | 0 |
| Client Creation | 8 | 6 | -2 (missing) |
| **Total** | 58 | 64 | +6 overall |

---

## Missing Functions (Critical Gaps)

### 1. `compute_logprobs()` - MISSING

**Python:**
```python
# sampling_client.py:258-296
def compute_logprobs(self, prompt: types.ModelInput) -> ConcurrentFuture[list[float | None]]:
    """Computes log probabilities for prompt tokens."""
```

**Elixir Status**: NOT IMPLEMENTED

**Impact**: Cannot compute perplexity, cannot evaluate model confidence on prompts

**Implementation Notes**:
- Internally calls `sample()` with `max_tokens=1, prompt_logprobs=True`
- Simple wrapper function

**Suggested Elixir Implementation**:
```elixir
def compute_logprobs(client, prompt) do
  request = %SampleRequest{
    prompt: prompt,
    num_samples: 1,
    sampling_params: %SamplingParams{max_tokens: 1},
    prompt_logprobs: true
  }

  case sample(client, request) do
    {:ok, %{prompt_logprobs: logprobs}} -> {:ok, logprobs}
    error -> error
  end
end
```

---

### 2. `load_state_with_optimizer()` - MISSING

**Python:**
```python
# training_client.py:594-615
def load_state_with_optimizer(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights AND optimizer state from a checkpoint."""
```

**Elixir Status**: NOT IMPLEMENTED

**Impact**: Cannot fully resume training with optimizer momentum preserved

**Implementation Notes**:
- Same as `load_state()` but with `optimizer: true` parameter
- Critical for exact training resumption

**Suggested Elixir Implementation**:
```elixir
# In Tinkex.TrainingClient
def load_state_with_optimizer(client, path) do
  request = %LoadWeightsRequest{
    model_id: client.model_id,
    path: path,
    optimizer: true,  # ← Key difference
    seq_id: next_seq_id(client)
  }

  API.Weights.load_weights(request, client.config)
end
```

---

### 3. `create_training_client_from_state_with_optimizer()` - MISSING

**Python:**
```python
# service_client.py:280-320
def create_training_client_from_state_with_optimizer(
    self, path: str, user_metadata: dict[str, str] | None = None
) -> TrainingClient:
```

**Elixir Status**: NOT IMPLEMENTED

**Impact**: Cannot create new training client with full state restoration

**Implementation Notes**:
- Combines `create_lora_training_client()` + `load_state_with_optimizer()`
- Queries checkpoint metadata first to get model config

---

### 4. `forward_backward_custom()` - PARTIAL

**Python:**
```python
# training_client.py:335-419
def forward_backward_custom(
    self, data: List[types.Datum], loss_fn: CustomLossFnV1
) -> APIFuture[ForwardBackwardOutput]:
    """Compute forward/backward with a custom loss function."""
```

**Elixir Status**: May exist via regularizers, needs verification

**Impact**: Cannot use custom PyTorch-based loss functions

---

## Enhanced Functions (Elixir Exceeds Python)

### Training Operations

| Elixir Function | Python Equivalent | Enhancement |
|-----------------|-------------------|-------------|
| `forward_future/2` | N/A | Returns future ID for manual polling |
| `forward_backward_future/2` | N/A | Returns future ID for manual polling |
| `optim_step_future/2` | N/A | Returns future ID for manual polling |

### Weight Operations

| Elixir Function | Python Equivalent | Enhancement |
|-----------------|-------------------|-------------|
| `save_weights_typed/2` | N/A | Returns parsed struct |
| `load_weights_typed/2` | N/A | Returns parsed struct |
| `save_weights_for_sampler_typed/2` | N/A | Returns parsed struct |

### Telemetry Operations

| Elixir Function | Python Equivalent | Enhancement |
|-----------------|-------------------|-------------|
| `send_sync/2` | N/A | Synchronous telemetry send |

---

## Function-by-Function Comparison

### ServiceClient / Tinkex.Client

| Python | Elixir | Status |
|--------|--------|--------|
| `ServiceClient()` | `Tinkex.Client.new()` | ✅ Parity |
| `create_lora_training_client()` | `Tinkex.Client.create_training_client()` | ✅ Parity |
| `create_training_client_from_state()` | `Tinkex.Client.create_training_client_from_state()` | ✅ Parity |
| `create_training_client_from_state_with_optimizer()` | N/A | ❌ **MISSING** |
| `create_sampling_client()` | `Tinkex.Client.create_sampling_client()` | ✅ Parity |
| `create_rest_client()` | `Tinkex.RestClient.new()` | ✅ Parity |
| `get_server_capabilities()` | `Tinkex.API.Service.get_server_capabilities()` | ✅ Parity |
| `get_telemetry()` | N/A (different pattern) | ⚠️ Different |

### TrainingClient / Tinkex.TrainingClient

| Python | Elixir | Status |
|--------|--------|--------|
| `forward()` | `Tinkex.TrainingClient.forward()` | ✅ Parity |
| `forward_async()` | (implicit) | ✅ Parity |
| `forward_backward()` | `Tinkex.TrainingClient.forward_backward()` | ✅ Parity |
| `forward_backward_async()` | (implicit) | ✅ Parity |
| `forward_backward_custom()` | N/A | ⚠️ Partial |
| `optim_step()` | `Tinkex.TrainingClient.optim_step()` | ✅ Parity |
| `save_state()` | `Tinkex.TrainingClient.save_weights()` | ✅ Parity |
| `load_state()` | `Tinkex.TrainingClient.load_weights()` | ✅ Parity |
| `load_state_with_optimizer()` | N/A | ❌ **MISSING** |
| `save_weights_for_sampler()` | `Tinkex.API.Weights.save_weights_for_sampler()` | ✅ Parity |
| `get_info()` | `Tinkex.API.Models.get_info()` | ✅ Parity |
| `get_tokenizer()` | `Tinkex.TrainingClient.get_tokenizer()` | ✅ Parity |
| `create_sampling_client()` | Available | ✅ Parity |
| `save_weights_and_get_sampling_client()` | Available | ✅ Parity |

### SamplingClient / Tinkex.SamplingClient

| Python | Elixir | Status |
|--------|--------|--------|
| `sample()` | `Tinkex.SamplingClient.sample()` | ✅ Parity |
| `sample_async()` | (implicit) | ✅ Parity |
| `compute_logprobs()` | N/A | ❌ **MISSING** |
| `compute_logprobs_async()` | N/A | ❌ **MISSING** |

### RestClient / Tinkex.RestClient

| Python | Elixir | Status |
|--------|--------|--------|
| `get_training_run()` | `Tinkex.API.Rest.get_training_run()` | ✅ Parity |
| `get_training_run_by_tinker_path()` | `Tinkex.API.Rest.get_training_run_by_tinker_path()` | ✅ Parity |
| `list_training_runs()` | `Tinkex.API.Rest.list_training_runs()` | ✅ Parity |
| `list_checkpoints()` | `Tinkex.API.Rest.list_checkpoints()` | ✅ Parity |
| `list_user_checkpoints()` | `Tinkex.API.Rest.list_user_checkpoints()` | ✅ Parity |
| `get_checkpoint_archive_url()` | `Tinkex.API.Rest.get_checkpoint_archive_url()` | ✅ Parity |
| `delete_checkpoint()` | `Tinkex.API.Rest.delete_checkpoint()` | ✅ Parity |
| `publish_checkpoint_from_tinker_path()` | `Tinkex.API.Rest.publish_checkpoint()` | ✅ Parity |
| `unpublish_checkpoint_from_tinker_path()` | `Tinkex.API.Rest.unpublish_checkpoint()` | ✅ Parity |
| `get_session()` | `Tinkex.API.Rest.get_session()` | ✅ Parity |
| `list_sessions()` | `Tinkex.API.Rest.list_sessions()` | ✅ Parity |
| `get_sampler()` | `Tinkex.API.Rest.get_sampler()` | ✅ Parity |
| `get_weights_info_by_tinker_path()` | `Tinkex.API.Rest.get_weights_info_by_tinker_path()` | ✅ Parity |

---

## Implementation Priority

### P0 (Critical for Recovery)

1. **`load_state_with_optimizer/2`**
   - Required for full training resumption
   - Simple addition: pass `optimizer: true` to existing load

2. **TrainingRun.corrupted parsing**
   - Required to detect poisoned jobs
   - Ensure `from_map/1` parses this field

### P1 (High Priority)

3. **`compute_logprobs/2`**
   - Wrapper around existing `sample/4`
   - Enables model evaluation workflows

4. **`create_training_client_from_state_with_optimizer/3`**
   - Combines existing functions
   - Enables one-step recovery

### P2 (Medium Priority)

5. **`forward_backward_custom/3`**
   - Advanced training feature
   - May require per-datum logprobs support

---

## Architectural Differences

### Async Model

| Aspect | Python | Elixir |
|--------|--------|--------|
| Pattern | async/await + concurrent.futures | GenServer + Task |
| Sync calls | `.result()` on future | Direct call |
| Async calls | `await future` | Task.async |
| Cancellation | Future.cancel() | Task.shutdown() |

### Error Handling

| Aspect | Python | Elixir |
|--------|--------|--------|
| Pattern | Exceptions | Tagged tuples |
| Success | Return value | `{:ok, result}` |
| Failure | Raise exception | `{:error, error}` |
| Retry | Automatic + exceptions | Automatic + tuples |

### Response Typing

| Aspect | Python | Elixir |
|--------|--------|--------|
| Default | Generic dict | Raw map |
| Typed | Pydantic model | Struct via `from_map/1` |
| Variants | Single return | `_typed` suffixed functions |
