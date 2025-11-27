# Wire Protocol Analysis: LoadWeightsRequest Field Name Mismatch

**Date:** 2025-11-26
**Severity:** CRITICAL
**Type:** Breaking Incompatibility
**Status:** Bug - Must Fix

## Problem Statement

The Elixir `LoadWeightsRequest` type uses a different field name than the Python implementation, causing **complete wire protocol incompatibility**. The server expects Python's field name and will not recognize Elixir's requests.

---

## Python Wire Format

### Type Definition

**File:** `tinkex/tinker/src/tinker/types/load_weights_request.py` (Line 17)

```python
class LoadWeightsRequest(StrictBase):
    model_id: ModelID
    path: str

    optimizer: bool  # ← FIELD NAME
    """Whether to load optimizer state along with model weights"""

    seq_id: Optional[int] = None
    type: Literal["load_weights"] = "load_weights"
```

### JSON Payload (Load without optimizer)

```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 2,
  "optimizer": false,
  "type": "load_weights"
}
```

### JSON Payload (Load with optimizer)

```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 2,
  "optimizer": true,
  "type": "load_weights"
}
```

**Field Name:** `"optimizer"`

---

## Elixir Wire Format (INCORRECT)

### Type Definition

**File:** `tinkex/lib/tinkex/types/load_weights_request.ex` (Line 35)

```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}
  defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]
  # ↑ WRONG FIELD NAME

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          load_optimizer_state: boolean(),  # ← WRONG FIELD NAME
          type: String.t()
        }
end
```

### JSON Payload (Current - WRONG)

```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 2,
  "load_optimizer_state": true,
  "type": "load_weights"
}
```

**Field Name:** `"load_optimizer_state"` (WRONG!)

---

## Server Expectation

The Tinker server is the source of truth. Based on the Python SDK (which is the canonical implementation), the server expects:

**Field Name:** `"optimizer"` (boolean)

**Server Behavior:**
- Recognizes `"optimizer": true` → Loads weights + optimizer state
- Recognizes `"optimizer": false` → Loads weights only
- **Does NOT recognize** `"load_optimizer_state"` → Field ignored or error

---

## Impact Analysis

### 1. Request Failure Scenarios

#### Scenario A: Field Ignored (Silent Failure)

```
Client sends:   {"load_optimizer_state": true}
Server reads:   {} (field not recognized)
Server action:  Loads weights without optimizer (wrong behavior!)
Client expects: Weights + optimizer
Result:         Data inconsistency, training dynamics corrupted
```

**Severity:** CRITICAL - Silent data corruption

#### Scenario B: Request Rejected (Explicit Failure)

```
Client sends:   {"load_optimizer_state": true}
Server reads:   Unknown field
Server action:  Returns 400 Bad Request
Client receives: Error
Result:          Feature completely broken
```

**Severity:** CRITICAL - Complete feature failure

### 2. Cross-Language Incompatibility

| Scenario | Python Client | Elixir Client | Result |
|----------|---------------|---------------|--------|
| Python saves, Python loads | ✅ Works | N/A | Compatible |
| Python saves, Elixir loads | N/A | ❌ Broken | Wrong field name |
| Elixir saves, Python loads | ❌ Can't save | N/A | No save_state() |
| Elixir saves, Elixir loads | ❌ Can't save | ❌ Broken | Both broken |

**Conclusion:** Zero cross-language checkpoint compatibility

### 3. Production Impact

**If deployed with current code:**
1. All checkpoint load requests fail or behave incorrectly
2. Training cannot be resumed
3. Optimizer state never restored (even if requested)
4. Silent data corruption possible
5. Incompatible with Python clients

---

## Root Cause Analysis

### Why the Mismatch Exists

The Elixir developer chose a more descriptive field name (`load_optimizer_state`) but didn't verify it against the Python implementation or server API.

**Python rationale:**
- Shorter field name: `optimizer`
- Matches common terminology
- Established convention

**Elixir rationale:**
- More explicit: `load_optimizer_state`
- Self-documenting
- Follows Elixir naming conventions

**Problem:** Wire protocol compatibility > naming conventions

---

## Required Fix

### Change #1: Struct Definition

**Before (WRONG):**
```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}
  defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          load_optimizer_state: boolean(),
          type: String.t()
        }
end
```

**After (CORRECT):**
```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :optimizer, :type]}
  defstruct [:model_id, :path, :seq_id, optimizer: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          optimizer: boolean(),  # ← FIXED
          type: String.t()
        }
end
```

### Change #2: Constructor Function

**Before (WRONG):**
```elixir
def new(model_id, path, opts \\ []) do
  %__MODULE__{
    model_id: model_id,
    path: path,
    seq_id: Keyword.get(opts, :seq_id),
    load_optimizer_state: Keyword.get(opts, :load_optimizer_state, false),
    type: "load_weights"
  }
end
```

**After (CORRECT):**
```elixir
def new(model_id, path, opts \\ []) do
  %__MODULE__{
    model_id: model_id,
    path: path,
    seq_id: Keyword.get(opts, :seq_id),
    optimizer: Keyword.get(opts, :optimizer, false),  # ← FIXED
    type: "load_weights"
  }
end
```

### Change #3: Documentation

**Before:**
```elixir
@moduledoc """
## Load Optimizer State

When `load_optimizer_state` is true, the optimizer state...
```

**After:**
```elixir
@moduledoc """
## Load Optimizer State

When `optimizer` is true, the optimizer state...
```

---

## Wire Format Verification

### Test Case 1: Load Without Optimizer

**Expected Wire Format:**
```json
{
  "model_id": "run-abc123",
  "path": "tinker://run-abc123/weights/checkpoint-001",
  "seq_id": 5,
  "optimizer": false,
  "type": "load_weights"
}
```

**Elixir Code:**
```elixir
request = %LoadWeightsRequest{
  model_id: "run-abc123",
  path: "tinker://run-abc123/weights/checkpoint-001",
  seq_id: 5,
  optimizer: false
}

Jason.encode!(request)
# Should produce: {"model_id":"run-abc123","path":"tinker://run-abc123/weights/checkpoint-001","seq_id":5,"optimizer":false,"type":"load_weights"}
```

### Test Case 2: Load With Optimizer

**Expected Wire Format:**
```json
{
  "model_id": "run-xyz789",
  "path": "tinker://run-xyz789/weights/checkpoint-042",
  "seq_id": 10,
  "optimizer": true,
  "type": "load_weights"
}
```

**Elixir Code:**
```elixir
request = %LoadWeightsRequest{
  model_id: "run-xyz789",
  path: "tinker://run-xyz789/weights/checkpoint-042",
  seq_id: 10,
  optimizer: true
}

Jason.encode!(request)
# Should produce: {"model_id":"run-xyz789","path":"tinker://run-xyz789/weights/checkpoint-042","seq_id":10,"optimizer":true,"type":"load_weights"}
```

---

## Compatibility Matrix After Fix

| Scenario | Before Fix | After Fix |
|----------|------------|-----------|
| Elixir → Server (without optimizer) | ❌ Broken | ✅ Works |
| Elixir → Server (with optimizer) | ❌ Broken | ✅ Works |
| Python → Server | ✅ Works | ✅ Works |
| Cross-language checkpoints | ❌ Incompatible | ✅ Compatible |

---

## Migration Path

### For Existing Code (None Exists)

Since `load_state()` and `load_state_with_optimizer()` don't exist in Elixir yet, there's **no migration needed**. The fix can be applied before any code uses the type.

**Breaking Changes:** NONE (feature doesn't exist yet)

**Deployment Impact:** NONE (no users to break)

---

## Verification Steps

### 1. Unit Test

```elixir
defmodule Tinkex.Types.LoadWeightsRequestTest do
  use ExUnit.Case
  alias Tinkex.Types.LoadWeightsRequest

  test "encodes optimizer field correctly (false)" do
    request = %LoadWeightsRequest{
      model_id: "test-run",
      path: "tinker://test-run/weights/001",
      optimizer: false
    }

    json = Jason.encode!(request)
    decoded = Jason.decode!(json)

    assert decoded["optimizer"] == false
    refute Map.has_key?(decoded, "load_optimizer_state")
  end

  test "encodes optimizer field correctly (true)" do
    request = %LoadWeightsRequest{
      model_id: "test-run",
      path: "tinker://test-run/weights/001",
      optimizer: true
    }

    json = Jason.encode!(request)
    decoded = Jason.decode!(json)

    assert decoded["optimizer"] == true
    refute Map.has_key?(decoded, "load_optimizer_state")
  end
end
```

### 2. Integration Test

```elixir
test "load_state sends correct wire format" do
  # Mock HTTP client to capture request
  mock_http_client = fn _url, body, _headers ->
    decoded = Jason.decode!(body)
    assert decoded["optimizer"] == false
    {:ok, %{status: 200, body: Jason.encode!(%{path: "tinker://test", type: "load_weights"})}}
  end

  # Test load_state (optimizer: false)
  {:ok, task} = TrainingClient.load_state(client, "tinker://test")
  {:ok, _response} = Task.await(task)
end

test "load_state_with_optimizer sends correct wire format" do
  mock_http_client = fn _url, body, _headers ->
    decoded = Jason.decode!(body)
    assert decoded["optimizer"] == true  # ← Must be true
    {:ok, %{status: 200, body: Jason.encode!(%{path: "tinker://test", type: "load_weights"})}}
  end

  {:ok, task} = TrainingClient.load_state_with_optimizer(client, "tinker://test")
  {:ok, _response} = Task.await(task)
end
```

### 3. Server Compatibility Test

```elixir
test "matches Python SDK wire format" do
  elixir_request = %LoadWeightsRequest{
    model_id: "test",
    path: "tinker://test/weights/001",
    seq_id: 1,
    optimizer: true
  }

  python_expected = """
  {
    "model_id": "test",
    "path": "tinker://test/weights/001",
    "seq_id": 1,
    "optimizer": true,
    "type": "load_weights"
  }
  """

  elixir_json = Jason.encode!(elixir_request)
  python_json = String.replace(python_expected, ~r/\s/, "")

  assert elixir_json == python_json
end
```

---

## Recommended Actions

### Immediate (P0)

1. ✅ **Fix LoadWeightsRequest struct**
   - Change field name to `optimizer`
   - Update @derive directive
   - Update type spec
   - Est: 30 minutes

2. ✅ **Fix documentation**
   - Update moduledoc
   - Update field comments
   - Update examples
   - Est: 30 minutes

3. ✅ **Add unit tests**
   - Test wire format
   - Test both true/false values
   - Verify no old field name
   - Est: 1 hour

### Next (P1)

4. **Integration tests**
   - Test with mock server
   - Verify server accepts requests
   - Test round-trip (save → load)
   - Est: 2 hours

5. **Cross-SDK compatibility tests**
   - Python saves, Elixir loads
   - Verify optimizer state
   - Est: 2 hours

---

## Risk Assessment

### Before Fix

- **Risk Level:** CRITICAL
- **Impact:** Complete feature failure
- **Probability:** 100% (guaranteed to fail)
- **Detectability:** High (will see errors or wrong behavior)

### After Fix

- **Risk Level:** LOW
- **Impact:** None (correct behavior)
- **Probability:** 0% (wire format matches)
- **Detectability:** N/A (no issues to detect)

---

## Conclusion

This is a **critical wire protocol bug** that must be fixed before implementing any checkpoint loading functionality. The fix is straightforward (rename one field) but has **zero tolerance for error** - the field name must exactly match the Python implementation and server expectations.

**Priority:** P0 - Must fix before any other checkpoint work
**Effort:** 2-3 hours (fix + tests + verification)
**Risk:** None (no existing usage to break)
**Impact:** Unblocks all checkpoint loading features
