# AdamParams Extension Specification

## Summary

Extend `Tinkex.Types.AdamParams` to include `weight_decay` and `grad_clip_norm` fields to match Python SDK v0.7.0.

## Python SDK Reference

```python
# tinker/src/tinker/types/optim_step_request.py
class AdamParams(StrictBase):
    learning_rate: float = 0.0001
    beta1: float = 0.9
    beta2: float = 0.95
    eps: float = 1e-12
    weight_decay: float = 0.0      # NEW: decoupled weight decay
    grad_clip_norm: float = 0.0    # NEW: gradient clipping (0 = disabled)
```

## Current Elixir Implementation

**File**: `lib/tinkex/types/adam_params.ex`

```elixir
@derive {Jason.Encoder, only: [:learning_rate, :beta1, :beta2, :eps]}
defstruct learning_rate: 0.0001,
          beta1: 0.9,
          beta2: 0.95,
          eps: 1.0e-12

@type t :: %__MODULE__{
        learning_rate: float(),
        beta1: float(),
        beta2: float(),
        eps: float()
      }
```

## Required Changes

### 1. Struct Definition

Add two new fields to the struct:

```elixir
defstruct learning_rate: 0.0001,
          beta1: 0.9,
          beta2: 0.95,
          eps: 1.0e-12,
          weight_decay: 0.0,       # NEW
          grad_clip_norm: 0.0      # NEW
```

### 2. Jason.Encoder Derive

Update to include new fields:

```elixir
@derive {Jason.Encoder, only: [:learning_rate, :beta1, :beta2, :eps, :weight_decay, :grad_clip_norm]}
```

### 3. Type Spec

Extend type definition:

```elixir
@type t :: %__MODULE__{
        learning_rate: float(),
        beta1: float(),
        beta2: float(),
        eps: float(),
        weight_decay: float(),
        grad_clip_norm: float()
      }
```

### 4. Validation in `new/1`

Add validation for the new fields in the `new/1` function:

```elixir
def new(opts \\ []) do
  with {:ok, lr} <- validate_learning_rate(Keyword.get(opts, :learning_rate, 0.0001)),
       {:ok, b1} <- validate_beta(Keyword.get(opts, :beta1, 0.9), "beta1"),
       {:ok, b2} <- validate_beta(Keyword.get(opts, :beta2, 0.95), "beta2"),
       {:ok, eps} <- validate_epsilon(Keyword.get(opts, :eps, 1.0e-12)),
       {:ok, wd} <- validate_non_negative(Keyword.get(opts, :weight_decay, 0.0), "weight_decay"),
       {:ok, gcn} <- validate_non_negative(Keyword.get(opts, :grad_clip_norm, 0.0), "grad_clip_norm") do
    {:ok,
     %__MODULE__{
       learning_rate: lr,
       beta1: b1,
       beta2: b2,
       eps: eps,
       weight_decay: wd,
       grad_clip_norm: gcn
     }}
  end
end

defp validate_non_negative(value, name) when is_number(value) and value >= 0 do
  {:ok, value / 1}
end
defp validate_non_negative(_, name), do: {:error, "#{name} must be non-negative number"}
```

### 5. Documentation Update

Update moduledoc to document new fields:

```elixir
@moduledoc """
Adam optimizer parameters.

Mirrors Python tinker.types.AdamParams.

IMPORTANT: Defaults match Python SDK exactly:
- learning_rate: 0.0001
- beta1: 0.9
- beta2: 0.95 (NOT 0.999!)
- eps: 1.0e-12 (NOT 1e-8!)
- weight_decay: 0.0 (decoupled weight decay)
- grad_clip_norm: 0.0 (0 = no clipping)

## Weight Decay

Uses decoupled weight decay (AdamW-style), applied after the Adam update.

## Gradient Clipping

When `grad_clip_norm > 0`, gradients are clipped to this maximum L2 norm
before the optimizer step. Set to 0.0 to disable clipping.
"""
```

## Test Cases

```elixir
# test/tinkex/types/adam_params_test.exs

describe "new/1" do
  test "default values include weight_decay and grad_clip_norm" do
    {:ok, params} = AdamParams.new()
    assert params.weight_decay == 0.0
    assert params.grad_clip_norm == 0.0
  end

  test "accepts custom weight_decay" do
    {:ok, params} = AdamParams.new(weight_decay: 0.01)
    assert params.weight_decay == 0.01
  end

  test "accepts custom grad_clip_norm" do
    {:ok, params} = AdamParams.new(grad_clip_norm: 1.0)
    assert params.grad_clip_norm == 1.0
  end

  test "rejects negative weight_decay" do
    assert {:error, msg} = AdamParams.new(weight_decay: -0.01)
    assert msg =~ "weight_decay"
  end

  test "rejects negative grad_clip_norm" do
    assert {:error, msg} = AdamParams.new(grad_clip_norm: -1.0)
    assert msg =~ "grad_clip_norm"
  end
end

describe "JSON encoding" do
  test "includes weight_decay and grad_clip_norm in JSON output" do
    {:ok, params} = AdamParams.new(weight_decay: 0.01, grad_clip_norm: 1.0)
    json = Jason.encode!(params)
    decoded = Jason.decode!(json)

    assert decoded["weight_decay"] == 0.01
    assert decoded["grad_clip_norm"] == 1.0
  end
end
```

## Backward Compatibility

- Defaults match previous behavior (0.0 for both)
- Existing code not passing these options continues to work
- JSON encoding automatically includes new fields

## Files Affected

| File | Change |
|------|--------|
| `lib/tinkex/types/adam_params.ex` | Add fields, validation, documentation |
| `test/tinkex/types/adam_params_test.exs` | Add test cases |

## Implementation Priority

**High** - Direct API contract change affecting training operations.
