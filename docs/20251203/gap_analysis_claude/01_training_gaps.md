# Training Feature Gaps

## Overview

TrainingClient achieves ~95% parity. Core training loop (forward, backward, optim_step, checkpoint save/load, sampler creation) matches Python. Elixir goes beyond Python with a regularizer pipeline and optional gradient-norm reporting; Python lacks this pipeline entirely.

## Fully Implemented (Parity)

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| `forward/3` | training_client.py:181-233 | training_client.ex:240-279 | Parity |
| `forward_backward/3` | training_client.py:261-318 | training_client.ex:213-220 | Parity |
| `forward_backward_custom/3` | training_client.py:337-419 | training_client.ex:404-455 + `Training.CustomLoss` | Different (Elixir richer) |
| `optim_step/3` | training_client.py:422-479 | training_client.ex:255-279 | Parity |
| `save_state/3` (save_weights) | training_client.py:486-533 | training_client.ex:325-332 | Parity |
| `load_state/3` (load_weights) | training_client.py:541-578 | training_client.ex:339-345 | Parity |
| `load_state_with_optimizer/3` | training_client.py:584-619 | training_client.ex:353-360 | Parity |
| `save_weights_for_sampler/3` | training_client.py:642-688 | training_client.ex:272-279 | Parity |
| `save_weights_and_get_sampling_client/3` | training_client.py:723-789 | training_client.ex:287-317 | Parity |
| `get_info/1` | training_client.py:808-840 | training_client.ex:84-92 | Parity |
| `get_tokenizer/1` | training_client.py:843-894 | training_client.ex:116-126 | Parity |
| `create_sampling_client/2` | training_client.py:898-935 | training_client.ex:372-377 | Parity |

## Gaps & Differences

1. **Regularizer pipeline / grad norms**  
   - Python: `forward_backward_custom` only wraps a torch-based custom loss; no regularizer execution or gradient-norm reporting.  
   - Elixir: Full regularizer pipeline with optional gradient norms (`Tinkex.Regularizer.*`, `Training.CustomLoss`). This is an Elixir-only enhancement, not a gap.

2. **Async regularizer handling**  
   - Python: No regularizer async handling.  
   - Elixir: Supports `async: true` specs with `Task.async_stream/3`.

3. **Coverage gap: metric reducer parity**  
   - Training results that depend on `hash_unordered` reducer (Python) will differ; Elixir combiner lacks that reducer (see Data Handling doc).

## Elixir-Only Features (Improvements)

| Feature | Description |
|---------|-------------|
| `encode/3`, `decode/3` | Integrated tokenizer helpers on TrainingClient |
| `unload_model/2` | Explicit model unloading (not exposed in Python TrainingClient) |
| Regularizer pipeline | Composition, optional parallelism, grad norms |

## Files Reference

- Python: `tinker/lib/public_interfaces/training_client.py`
- Elixir: `lib/tinkex/training_client.ex`, `lib/tinkex/custom_loss.ex`
