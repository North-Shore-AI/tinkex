# API Function Gap Analysis

**Date**: December 4, 2025

---

## Summary

| Category | Python Functions | Elixir Functions | Gap |
|----------|-----------------|------------------|-----|
| Training Operations | 8 | 12 | +4 (enhanced) |
| Weight Operations | 6 | 12 | +6 (enhanced) |
| Sampling Operations | 4 | 4 | Parity |
| REST Operations | 28 | 28 | 0 |
| Service Operations | 4 | 4 | 0 |
| Client Creation | 8 | 8 | Parity |
| **Total** | 58 | 68 | +10 (typed/sync helpers) |

---

## Missing Functions

None. Previously flagged gaps are implemented:
- `compute_logprobs/2` exists in `Tinkex.SamplingClient` (wraps `sample/4` with `prompt_logprobs`)
- `load_state_with_optimizer/3` exists in `Tinkex.TrainingClient` (sets `optimizer: true`)
- `create_training_client_from_state_with_optimizer/3` exists in `Tinkex.ServiceClient` (optionally async)
- `forward_backward_custom/3` exists in `Tinkex.TrainingClient` (Nx gradients + linearized loss)

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
| `create_training_client_from_state_with_optimizer()` | `Tinkex.Client.create_training_client_from_state_with_optimizer()` | ✅ Parity |
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
| `forward_backward_custom()` | `Tinkex.TrainingClient.forward_backward_custom()` | ✅ Parity |
| `optim_step()` | `Tinkex.TrainingClient.optim_step()` | ✅ Parity |
| `save_state()` | `Tinkex.TrainingClient.save_weights()` | ✅ Parity |
| `load_state()` | `Tinkex.TrainingClient.load_weights()` | ✅ Parity |
| `load_state_with_optimizer()` | `Tinkex.TrainingClient.load_state_with_optimizer()` | ✅ Parity |
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
| `compute_logprobs()` | `Tinkex.SamplingClient.compute_logprobs()` | ✅ Parity |
| `compute_logprobs_async()` | Task-returning variant | ✅ Parity |

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

### P0 (Critical for Recovery UX)

1. **Recovery automation** – add monitor/executor that polls `TrainingRun.corrupted` and restarts via `create_training_client_from_state_with_optimizer/3`.

### P1 (High Priority)

2. **Hardening tests** – integration coverage for optimizer-state load, corrupted-run parsing, and `compute_logprobs/2`.

### P2 (Medium Priority)

3. **Docs/telemetry clarity** – document `get_telemetry/1` pattern and backpressure semantics for sampling/logprob helpers.

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
