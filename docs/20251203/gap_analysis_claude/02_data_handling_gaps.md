# Data Handling Gaps

## Overview

Data handling achieves ~90% parity. Core types (TensorData, ModelInput, Datum) are implemented; differences are limited to tensor conversion backends, a missing metric reducer, and a few convenience builders.

## Type Parity Matrix

| Type | Python | Elixir | Status |
|------|--------|--------|--------|
| `TensorData` | NumPy/PyTorch + list conversions | Nx + list conversions | Different (backend-specific) |
| `ModelInput` | Builders + converters | from_ints/from_text only | Missing builders |
| `Datum` | Key-based dtype inference | List/Nx inference only | Different |
| `EncodedTextChunk` | Full | Full | Parity |
| `ImageChunk` | Full | Full | Parity |
| `ImageAssetPointerChunk` | Full | Full | Parity |
| `ForwardBackwardInput` | Full | Full | Parity |
| `ForwardBackwardOutput` | Full | Full | Parity |
| `SamplingParams` | Full | Full | Parity |

**Note:** Chunked forward/backward combiner exists in both SDKs (`chunked_fwdbwd_helpers.combine_fwd_bwd_output_results` vs `Tinkex.Future.Combiner`). Metric reducer coverage differs (see Gaps).

## Gaps

### 1. Metric reducer coverage (Medium)
- **Python:** `combine_fwd_bwd_output_results` supports `hash_unordered` and other reducers.
- **Elixir:** Combiner exists (`Tinkex.Future.Combiner`) but `MetricsReduction` lacks `hash_unordered`, so order-insensitive metrics will differ.

### 2. ModelInput Builder Methods (Medium Priority)

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

**Elixir Status:** Not implemented

**Implementation Recommendation:**
```elixir
# lib/tinkex/types/model_input.ex
def empty, do: %__MODULE__{chunks: []}

def append(%__MODULE__{chunks: chunks}, chunk) do
  %__MODULE__{chunks: chunks ++ [chunk]}
end

def append_int(%__MODULE__{chunks: chunks}, token) when is_integer(token) do
  case List.last(chunks) do
    %EncodedTextChunk{tokens: tokens} = last ->
      updated = %{last | tokens: tokens ++ [token]}
      %__MODULE__{chunks: List.replace_at(chunks, -1, updated)}
    _ ->
      append(%__MODULE__{chunks: chunks}, %EncodedTextChunk{tokens: [token]})
  end
end
```

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
- **Elixir:** Nx-only (`from_nx`, `to_nx`); list access via `data` field.

## Elixir-Only Features

| Feature | Description |
|---------|-------------|
| `ModelInput.from_text/2` | Direct text→tokens via Tokenizer |
| `ModelInput.from_text!/2` | Raising variant |
| Nx casting | `TensorData.from_nx/1` aggressively casts to Python-compatible dtypes |

## Files Reference

- Python: `tinker/types/tensor_data.py`, `tinker/types/model_input.py`, `tinker/types/datum.py`
- Python: `tinker/lib/chunked_fwdbwd_helpers.py`
- Elixir: `lib/tinkex/types/tensor_data.ex`, `lib/tinkex/types/model_input.ex`, `lib/tinkex/types/datum.ex`
- Elixir: `lib/tinkex/metrics_reduction.ex`
