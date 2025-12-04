# Data Handling Gaps

## Overview

Data handling achieves ~80% parity. Core types (TensorData, ModelInput, Datum) are fully implemented. Gaps exist in chunking utilities and convenience methods.

## Type Parity Matrix

| Type | Python | Elixir | Status |
|------|--------|--------|--------|
| `TensorData` | Full | Full | Parity |
| `ModelInput` | Full | Partial | Missing builders |
| `Datum` | Full | Full | Parity |
| `EncodedTextChunk` | Full | Full | Parity |
| `ImageChunk` | Full | Full | Parity |
| `ImageAssetPointerChunk` | Full | Full | Parity |
| `ForwardBackwardInput` | Full | Full | Parity |
| `ForwardBackwardOutput` | Full | Full | Parity |
| `SamplingParams` | Full | Full | Parity |

## Missing Features

### 1. Chunked Output Combiner (High Priority)

**Python Implementation:**
```python
# chunked_fwdbwd_helpers.py
def combine_fwd_bwd_output_results(
    results: List[ForwardBackwardOutput]
) -> ForwardBackwardOutput:
    """Combines results from multiple chunks into single output."""
    # Merges metrics with weighted averaging
    # Flattens loss_fn_outputs
    # Handles metric suffixes: :mean, :sum, :min, :max, :slack, :hash_unordered, :unique
```

**Elixir Status:**
- `MetricsReduction.reduce/1` exists for metrics only
- No unified `combine_fwd_bwd_output_results/1` function

**Implementation Recommendation:**
```elixir
# lib/tinkex/chunked_helpers.ex
defmodule Tinkex.ChunkedHelpers do
  def combine_fwd_bwd_outputs(outputs) when is_list(outputs) do
    loss_fn_outputs = Enum.flat_map(outputs, & &1.loss_fn_outputs)
    weights = Enum.map(outputs, &length(&1.loss_fn_outputs))
    metrics = MetricsReduction.reduce_weighted(
      Enum.map(outputs, & &1.metrics),
      weights
    )

    %ForwardBackwardOutput{
      loss_fn_output_type: hd(outputs).loss_fn_output_type,
      loss_fn_outputs: loss_fn_outputs,
      metrics: metrics
    }
  end
end
```

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

### 4. TensorData.tolist/1 (Low Priority)

**Python Implementation:**
```python
def tolist(self) -> List[int] | List[float]:
    return self.data
```

**Elixir Status:** Can use `tensor_data.data` directly

**Recommendation:** Add for API consistency:
```elixir
def tolist(%__MODULE__{data: data}), do: data
```

## Tensor Conversion Comparison

| Conversion | Python | Elixir |
|------------|--------|--------|
| From NumPy | `from_numpy()` | N/A (no NumPy) |
| From PyTorch | `from_torch()` | N/A (no PyTorch) |
| From Nx | N/A | `from_nx()` |
| To NumPy | `to_numpy()` | N/A |
| To PyTorch | `to_torch()` | N/A |
| To Nx | N/A | `to_nx()` |
| To List | `tolist()` | `.data` field |

**Note:** Elixir uses Nx as the tensor library. NumPy/PyTorch conversions are not applicable.

## Elixir-Only Features

| Feature | Description |
|---------|-------------|
| `ModelInput.from_text/2` | Direct text→tokens via Tokenizer |
| `ModelInput.from_text!/2` | Raising variant |
| Nested list support | `TensorData.from_nx/1` handles nested lists |

## Files Reference

- Python: `tinker/types/tensor_data.py`, `tinker/types/model_input.py`, `tinker/types/datum.py`
- Python: `tinker/lib/chunked_fwdbwd_helpers.py`
- Elixir: `lib/tinkex/types/tensor_data.ex`, `lib/tinkex/types/model_input.ex`, `lib/tinkex/types/datum.ex`
- Elixir: `lib/tinkex/metrics_reduction.ex`
