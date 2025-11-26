# Implementation Checklist: Structured Regularizers

Quick reference for implementing the structured regularizers enhancement in Python Tinker SDK.

---

## Files to Modify

### 1. `src/tinker/lib/public_interfaces/training_client.py`

- [ ] **Line 11**: Add imports
  ```python
  from typing import Union, Awaitable, TypedDict
  import inspect
  ```

- [ ] **Line 47-48**: Add new type definitions after `CustomLossFnV1`
  ```python
  RegularizerSpec = TypedDict("RegularizerSpec", {
      "fn": Callable[..., Union[Tuple[Any, Dict[str, float]], Awaitable[Tuple[Any, Dict[str, float]]]]],
      "weight": float,
      "name": str,
  })
  RegularizerList = List[RegularizerSpec]
  ```

- [ ] **Lines 328-361**: Update `forward_backward_custom` signature
  ```python
  def forward_backward_custom(
      self,
      data: List[types.Datum],
      loss_fn: CustomLossFnV1 | None = None,
      regularizers: RegularizerList | None = None,
  ) -> APIFuture[types.ForwardBackwardOutput]:
  ```

- [ ] **Lines 363-412**: Rewrite `forward_backward_custom_async` with structured regularizer support
  - Add validation (at least one of loss_fn or regularizers required)
  - Loop over regularizers with async detection
  - Build structured metrics dict
  - Preserve existing linearization logic

### 2. `docs/api/trainingclient.md`

- [ ] **Lines 126-168**: Update documentation for `forward_backward_custom`
  - Add `regularizers` parameter documentation
  - Add structured regularizers example
  - Document telemetry output structure
  - Add async regularizer example

### 3. New file: `tests/test_training_client_regularizers.py`

- [ ] Test: Multiple sync regularizers compose correctly
- [ ] Test: Single async regularizer awaited properly
- [ ] Test: Mixed sync/async regularizers work together
- [ ] Test: Backward compat - legacy single loss_fn still works
- [ ] Test: Metrics structure matches schema
- [ ] Test: Error on neither loss_fn nor regularizers provided
- [ ] Test: Weight=0 regularizer contributes no loss but still metrics

---

## Metrics Schema Validation

Ensure returned `result.metrics` matches:

```python
{
    "loss_total": float,
    "regularizers": {
        "<name>": {
            "value": float,
            "weight": float,
            "contribution": float,
            "custom": Dict[str, float]
        }
    },
    "regularizer_total": float,
    # Optional, if base loss_fn provided:
    "base_loss": {
        "value": float,
        "custom": Dict[str, float]
    }
}
```

---

## Test Cases

### Basic Functionality

```python
def test_single_regularizer():
    def my_reg(data, logprobs):
        return torch.mean(logprobs[0]), {"test": 1.0}

    regularizers = [{"fn": my_reg, "weight": 0.1, "name": "test_reg"}]
    result = training_client.forward_backward_custom(data, regularizers=regularizers)

    assert "regularizers" in result.metrics
    assert "test_reg" in result.metrics["regularizers"]
    assert result.metrics["regularizers"]["test_reg"]["weight"] == 0.1
```

### Async Regularizer

```python
async def test_async_regularizer():
    async def async_reg(data, logprobs):
        await asyncio.sleep(0.01)  # Simulate I/O
        return torch.tensor(1.0), {"async": True}

    regularizers = [{"fn": async_reg, "weight": 0.5, "name": "async_test"}]
    result = await training_client.forward_backward_custom_async(data, regularizers=regularizers)

    assert result.metrics["regularizers"]["async_test"]["custom"]["async"] == True
```

### Backward Compatibility

```python
def test_backward_compat():
    def old_style_loss(data, logprobs):
        return torch.mean(logprobs[0]), {"legacy": 1.0}

    # Old API still works
    result = training_client.forward_backward_custom(data, old_style_loss)
    assert "legacy" in result.metrics
```

---

## PR Checklist

- [ ] Implementation complete
- [ ] All tests pass
- [ ] Docs updated
- [ ] Type hints complete
- [ ] Backward compat verified
- [ ] No breaking changes to existing API
- [ ] Telemetry schema documented

---

## Estimated Effort

| Task | Time |
|------|------|
| Core implementation | 4-6 hours |
| Tests | 2-3 hours |
| Documentation | 1-2 hours |
| Review/iteration | 2-4 hours |
| **Total** | **~1-2 days** |
