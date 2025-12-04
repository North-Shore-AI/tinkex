# Data Handling Gaps

## Overview

Data handling achieves ~95% parity. Core types (TensorData, ModelInput, Datum) are implemented with full builder support. Remaining differences are limited to tensor conversion backends (Nx vs NumPy/PyTorch) and key-based dtype inference.

## Type Parity Matrix

| Type | Python | Elixir | Status |
|------|--------|--------|--------|
| `TensorData` | NumPy/PyTorch + list conversions | Nx + `tolist/1` | Different (backend-specific) |
| `ModelInput` | Builders + converters | `empty/0`, `append/2`, `append_int/2`, `from_ints`, `from_text` | ✅ Parity |
| `Datum` | Key-based dtype inference | List/Nx inference only | Different |
| `EncodedTextChunk` | Full | Full | Parity |
| `ImageChunk` | Full | Full | Parity |
| `ImageAssetPointerChunk` | Full | Full | Parity |
| `ForwardBackwardInput` | Full | Full | Parity |
| `ForwardBackwardOutput` | Full | Full | Parity |
| `SamplingParams` | Full | Full | Parity |

**Note:** Chunked forward/backward combiner exists in both SDKs (`chunked_fwdbwd_helpers.combine_fwd_bwd_output_results` vs `Tinkex.Future.Combiner`). Metric reducers now have full parity including `hash_unordered`.

## Gaps

### 1. ~~Metric reducer coverage~~ (RESOLVED)
- **Python:** `combine_fwd_bwd_output_results` supports `hash_unordered` and other reducers.
- **Elixir:** ✅ `MetricsReduction` now includes `hash_unordered` reducer. Uses `Enum.sort/1` + `:erlang.phash2/1` for order-insensitive hashing.
- **Note:** `hash_unordered` returns an **integer** (unlike other reducers which return floats). This is intentional for identity/fingerprinting use cases where the hash is used for equality checks, not arithmetic.

### 2. ~~ModelInput Builder Methods~~ (RESOLVED)

**Python Implementation:**
```python
# model_input.py
class ModelInput:
    @staticmethod
    def empty() -> "ModelInput":
        return ModelInput(chunks=[])

    def append(self, chunk: ModelInputChunk) -> "ModelInput":
        return ModelInput(chunks=self.chunks + [chunk])

    def append_int(self, token: int) -> "ModelInput":
        # Appends to last EncodedTextChunk or creates new one
```

**Elixir Status:** ✅ Implemented in `lib/tinkex/types/model_input.ex`:
- `empty/0` - Creates empty ModelInput
- `append/2` - Appends any chunk type
- `append_int/2` - Token-aware append (extends last EncodedTextChunk or creates new one)

### 3. Key-Based Dtype Inference (Low Priority)

**Python Implementation:**
```python
# datum.py
_key_to_type = {
    "target_tokens": "int64",
    "weights": "float32",
    "advantages": "float32",
    "logprobs": "float32",
    "clip_low_threshold": "float32",
    "clip_high_threshold": "float32",
}
```

**Elixir Status:** Infers from first element type only (integer→int64, float→float32)

**Note:** Current approach works for most cases. Key-based inference would be an optimization.

### 4. Tensor conversion backends (Low Priority)
- **Python:** NumPy and PyTorch helpers (`from_numpy`, `from_torch`, `to_numpy`, `to_torch`).
- **Elixir:** Nx-only (`from_nx`, `to_nx`); list access via `tolist/1` (added for parity) or `data` field.

## Elixir-Only Features

| Feature | Description |
|---------|-------------|
| `ModelInput.from_text/2` | Direct text→tokens via Tokenizer |
| `ModelInput.from_text!/2` | Raising variant |
| `ModelInput.empty/0` | Create empty ModelInput |
| `ModelInput.append/2` | Append any chunk type |
| `ModelInput.append_int/2` | Token-aware append (extends last text chunk or creates new) |
| `TensorData.tolist/1` | Return flat data list (Python parity) |
| Nx casting | `TensorData.from_nx/1` aggressively casts to Python-compatible dtypes |

## Files Reference

- Python: `tinker/types/tensor_data.py`, `tinker/types/model_input.py`, `tinker/types/datum.py`
- Python: `tinker/lib/chunked_fwdbwd_helpers.py`
- Elixir: `lib/tinkex/types/tensor_data.ex`, `lib/tinkex/types/model_input.ex`, `lib/tinkex/types/datum.ex`
- Elixir: `lib/tinkex/metrics_reduction.ex`
