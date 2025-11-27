# Training Persistence Gap Matrix

**Date:** 2025-11-26
**Analysis Type:** Feature-by-Feature Comparison
**Status:** Complete

## Executive Summary

The Elixir port is missing **4 critical methods** and has **1 breaking wire protocol incompatibility**. The underlying API infrastructure exists but is not exposed through high-level TrainingClient/ServiceClient methods.

### Gap Statistics

- **Total Features Compared:** 12
- **Python Features:** 12 (100%)
- **Elixir Features:** 7 (58%)
- **Missing Features:** 5 (42%)
- **Breaking Incompatibilities:** 1 (wire protocol)

---

## TrainingClient Method Comparison

| Feature | Python | Elixir | Status | Impact | Priority |
|---------|--------|--------|--------|--------|----------|
| **save_state(name)** | ✅ Complete<br/>Lines 479-524 | ❌ Missing | **GAP** | Cannot save training checkpoints | **CRITICAL** |
| **load_state(path)** | ✅ Complete<br/>Lines 560-578 | ❌ Missing | **GAP** | Cannot load checkpoints for transfer learning | **CRITICAL** |
| **load_state_with_optimizer(path)** | ✅ Complete<br/>Lines 585-605 | ❌ Missing | **GAP** | Cannot resume training with optimizer state | **CRITICAL** |
| **save_weights_for_sampler(name)** | ✅ Complete<br/>Lines 652-681 | ✅ Complete<br/>Lines 116-122 | **MATCH** | Sampler weights work correctly | LOW |

### Detailed Method Breakdown

#### 1. save_state(name)

**Python Implementation:**
```python
def save_state(self, name: str) -> APIFuture[types.SaveWeightsResponse]:
    """Save model weights to persistent storage."""
    # Creates SaveWeightsRequest
    # POSTs to /api/v1/save_weights
    # Returns SaveWeightsResponse with tinker:// path
```

**Elixir Implementation:**
```elixir
# MISSING - Does not exist
```

**Gap Details:**
- No method exists in TrainingClient
- API.Weights.save_weights() exists but not exposed
- SaveWeightsRequest type is defined
- SaveWeightsResponse type is defined

**Workaround:** NONE

**Fix Complexity:** LOW
- API already exists
- Types already exist
- Just need to add GenServer handler and public function

---

#### 2. load_state(path)

**Python Implementation:**
```python
def load_state(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights from a saved checkpoint."""
    # Calls _load_state_impl(request_id, path, optimizer=False)
    # POSTs to /api/v1/load_weights
    # Returns LoadWeightsResponse
```

**Elixir Implementation:**
```elixir
# MISSING - Does not exist
```

**Gap Details:**
- No method exists in TrainingClient
- API.Weights.load_weights() exists but not exposed
- LoadWeightsRequest type is defined BUT HAS WRONG FIELD NAME
- LoadWeightsResponse type is defined

**Workaround:** NONE

**Fix Complexity:** MEDIUM
- Must fix wire protocol issue first (optimizer field)
- Then add GenServer handler
- Then add public function

---

#### 3. load_state_with_optimizer(path)

**Python Implementation:**
```python
def load_state_with_optimizer(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights and optimizer state from a checkpoint."""
    # Calls _load_state_impl(request_id, path, optimizer=True)
    # POSTs to /api/v1/load_weights with optimizer=true
    # Returns LoadWeightsResponse
```

**Elixir Implementation:**
```elixir
# MISSING - Does not exist
```

**Gap Details:**
- No method exists in TrainingClient
- Same underlying API as load_state() (just different parameter)
- LoadWeightsRequest type needs field fix

**Workaround:** NONE

**Fix Complexity:** MEDIUM
- Same fix as load_state()
- Just passes different optimizer flag

---

#### 4. save_weights_for_sampler(name)

**Python Implementation:**
```python
def save_weights_for_sampler(self, name: str) -> APIFuture[types.SaveWeightsForSamplerResponse]:
    """Save model weights for use with a SamplingClient."""
    # Creates SaveWeightsForSamplerRequest
    # POSTs to /api/v1/save_weights_for_sampler
    # Returns SaveWeightsForSamplerResponse
```

**Elixir Implementation:**
```elixir
def save_weights_for_sampler(client, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:save_weights_for_sampler, opts}, :infinity)
   end)}
end
```

**Status:** ✅ **IMPLEMENTED AND WORKING**

**Differences:**
- Python passes `name` as positional arg
- Elixir uses keyword opts with `:path` key
- Both call same endpoint
- Both return similar response

---

## ServiceClient Method Comparison

| Feature | Python | Elixir | Status | Impact | Priority |
|---------|--------|--------|--------|--------|----------|
| **create_training_client_from_state(path)** | ✅ Complete<br/>Lines 222-254 | ❌ Missing | **GAP** | Cannot create client from checkpoint | **HIGH** |
| **create_lora_training_client(base_model)** | ✅ Complete<br/>Lines 153-196 | ✅ Complete<br/>Lines 37-39 | **MATCH** | Fresh client creation works | LOW |

### Detailed Method Breakdown

#### 1. create_training_client_from_state(path, user_metadata)

**Python Implementation:**
```python
def create_training_client_from_state(
    self, path: str, user_metadata: dict[str, str] | None = None
) -> TrainingClient:
    """Create a TrainingClient from saved model weights."""
    rest_client = self.create_rest_client()
    weights_info = rest_client.get_weights_info_by_tinker_path(path).result()

    training_client = self.create_lora_training_client(
        base_model=weights_info.base_model,
        rank=weights_info.lora_rank,
        user_metadata=user_metadata,
    )

    training_client.load_state(path).result()
    return training_client
```

**Elixir Implementation:**
```elixir
# MISSING - Does not exist
```

**Gap Details:**
- No method exists in ServiceClient
- Depends on TrainingClient.load_state() which also doesn't exist
- RestClient likely has get_weights_info() equivalent

**Workaround:** Manual multi-step process
```elixir
# 1. Get weights info
{:ok, rest} = ServiceClient.create_rest_client(service)
{:ok, info} = RestClient.get_weights_info_by_tinker_path(rest, path)

# 2. Create client
{:ok, training} = ServiceClient.create_lora_training_client(service,
  base_model: info.base_model,
  rank: info.lora_rank
)

# 3. Load weights - BUT THIS DOESN'T EXIST!
# {:ok, task} = TrainingClient.load_state(training, path)
# Task.await(task)
```

**Fix Complexity:** HIGH
- Requires TrainingClient.load_state() to be implemented first
- Requires REST API integration
- Requires multi-step orchestration

---

## Type Definition Comparison

| Type | Python Field Names | Elixir Field Names | Status | Issue |
|------|-------------------|-------------------|--------|-------|
| **SaveWeightsRequest** | `model_id`, `path`, `seq_id`, `type` | `model_id`, `path`, `seq_id`, `type` | ✅ **MATCH** | None |
| **SaveWeightsResponse** | `path`, `type` | `path`, `type` | ✅ **MATCH** | None |
| **LoadWeightsRequest** | `model_id`, `path`, `seq_id`, **`optimizer`**, `type` | `model_id`, `path`, `seq_id`, **`load_optimizer_state`**, `type` | ❌ **BREAKING** | **Field name mismatch** |
| **LoadWeightsResponse** | `path`, `type` | `path`, `type` | ✅ **MATCH** | None |
| **SaveWeightsForSamplerRequest** | `model_id`, `path`, `seq_id`, `sampling_session_seq_id`, `type` | `model_id`, `path`, `seq_id`, `sampling_session_seq_id`, `type` | ✅ **MATCH** | None |
| **SaveWeightsForSamplerResponse** | `path`, `sampling_session_id`, `type` | `path`, `sampling_session_id`, `type` | ✅ **MATCH** | None |

### Type Definition Details

#### LoadWeightsRequest - CRITICAL ISSUE

**Python:**
```python
class LoadWeightsRequest(StrictBase):
    model_id: ModelID
    path: str
    optimizer: bool  # ← Field name
    seq_id: Optional[int] = None
    type: Literal["load_weights"] = "load_weights"
```

**Elixir:**
```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}
  defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]
  # ↑ Field name: load_optimizer_state
end
```

**Wire Protocol Comparison:**

| Language | Field Name | Wire Format |
|----------|------------|-------------|
| Python | `optimizer` | `{"optimizer": true}` |
| Elixir | `load_optimizer_state` | `{"load_optimizer_state": true}` |
| **Server Expects** | `optimizer` | `{"optimizer": true}` |

**Impact:** Server will NOT recognize `load_optimizer_state` field

**Severity:** **CRITICAL** - Complete failure of load operations

**Fix:**
```elixir
# Change from:
defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]
@derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}

# To:
defstruct [:model_id, :path, :seq_id, optimizer: false, type: "load_weights"]
@derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :optimizer, :type]}
```

---

## API Module Comparison

| Endpoint | Python Function | Elixir Function | Exposed in TrainingClient |
|----------|----------------|-----------------|---------------------------|
| `POST /api/v1/save_weights` | ✅ `weights.save()` | ✅ `Weights.save_weights()` | ❌ Python: Yes<br/>❌ Elixir: No |
| `POST /api/v1/load_weights` | ✅ `weights.load()` | ✅ `Weights.load_weights()` | ❌ Python: Yes<br/>❌ Elixir: No |
| `POST /api/v1/save_weights_for_sampler` | ✅ `weights.save_for_sampler()` | ✅ `Weights.save_weights_for_sampler()` | ✅ Python: Yes<br/>✅ Elixir: Yes |

**Key Insight:** Elixir has all the low-level API functions, but only `save_weights_for_sampler` is exposed in TrainingClient!

---

## Request Sequencing Comparison

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Sequential request ID allocation | ✅ `_get_request_id()` | ✅ `allocate_request_ids()` | ✅ MATCH |
| Request ordering guarantee | ✅ `_take_turn()` async context manager | ✅ GenServer sequential execution | ✅ MATCH |
| Retry logic | ✅ `execute_with_retries()` | ✅ Future retry mechanisms | ✅ MATCH |
| Request type tracking | ✅ "SaveWeights", "LoadWeights" | ✅ Similar tracking | ✅ MATCH |

**Infrastructure:** Both implementations have equivalent sequencing infrastructure. Elixir's is ready to be used.

---

## Checkpoint Lifecycle Comparison

### Python Workflow (Complete)

```python
# 1. Save checkpoint
save_future = training_client.save_state("checkpoint-001")
result = await save_future  # tinker://run-123/weights/checkpoint-001

# 2. Load checkpoint (weights only)
load_future = training_client.load_state("tinker://run-123/weights/checkpoint-001")
await load_future

# 3. Load checkpoint (weights + optimizer)
load_future = training_client.load_state_with_optimizer("tinker://run-123/weights/checkpoint-001")
await load_future

# 4. Create client from checkpoint
new_client = service_client.create_training_client_from_state(
    "tinker://run-123/weights/checkpoint-001"
)
```

### Elixir Workflow (Broken)

```elixir
# 1. Save checkpoint - DOESN'T EXIST
# {:ok, task} = TrainingClient.save_state(client, "checkpoint-001")
# {:ok, result} = Task.await(task)

# 2. Load checkpoint (weights only) - DOESN'T EXIST
# {:ok, task} = TrainingClient.load_state(client, "tinker://run-123/weights/checkpoint-001")
# {:ok, _} = Task.await(task)

# 3. Load checkpoint (weights + optimizer) - DOESN'T EXIST
# {:ok, task} = TrainingClient.load_state_with_optimizer(client, "tinker://run-123/weights/checkpoint-001")
# {:ok, _} = Task.await(task)

# 4. Create client from checkpoint - DOESN'T EXIST
# {:ok, new_client} = ServiceClient.create_training_client_from_state(
#   service, "tinker://run-123/weights/checkpoint-001"
# )
```

**Current Capability:** NONE of the checkpoint persistence features work in Elixir

---

## Impact Analysis

### Critical Gaps

1. **No Training Checkpoint Saving**
   - Cannot save training progress
   - No disaster recovery
   - No multi-session training
   - **Workaround:** Use save_weights_for_sampler() (NOT intended for this)

2. **No Checkpoint Loading**
   - Cannot resume training
   - Cannot do transfer learning from checkpoints
   - Cannot load saved state
   - **Workaround:** NONE

3. **No Optimizer State Persistence**
   - Cannot maintain training dynamics across sessions
   - Optimizer must re-learn momentum
   - Slower convergence after resume
   - **Workaround:** NONE

4. **Wire Protocol Incompatibility**
   - load_optimizer_state field won't be recognized by server
   - Silent failures or errors
   - Incompatible with Python clients
   - **Workaround:** NONE (breaking bug)

### High-Impact Gaps

1. **No ServiceClient Helper**
   - Manual multi-step process required
   - Error-prone architecture detection
   - Poor developer experience
   - **Workaround:** Manual orchestration (but still fails due to missing load_state)

---

## Priority Matrix

### P0 - CRITICAL (Blocking)

| Feature | Reason | Est. Effort |
|---------|--------|-------------|
| Fix LoadWeightsRequest field name | Wire protocol incompatibility | 2 hours |
| Add TrainingClient.load_state() | Required for all checkpoint loading | 4 hours |
| Add TrainingClient.load_state_with_optimizer() | Required for training resumption | 2 hours |
| Add TrainingClient.save_state() | Required for checkpoint creation | 4 hours |

**Total P0 Effort:** ~12 hours

### P1 - HIGH (Important)

| Feature | Reason | Est. Effort |
|---------|--------|-------------|
| Add ServiceClient.create_training_client_from_state() | Developer convenience, depends on P0 | 4 hours |

**Total P1 Effort:** ~4 hours

### P2 - MEDIUM (Nice to have)

| Feature | Reason | Est. Effort |
|---------|--------|-------------|
| Add async versions of all methods | Consistency with existing API | 2 hours |
| Add comprehensive tests | Quality assurance | 8 hours |

**Total P2 Effort:** ~10 hours

---

## Implementation Sequence

### Phase 1: Type Fixes (2 hours)

1. Fix LoadWeightsRequest field name: `load_optimizer_state` → `optimizer`
2. Update @derive directive
3. Update documentation

### Phase 2: TrainingClient Load Methods (6 hours)

1. Add `load_state(client, path, opts)`
   - GenServer handler
   - Public function
   - Task wrapper
   - Error handling

2. Add `load_state_with_optimizer(client, path, opts)`
   - Reuse same GenServer handler
   - Different optimizer flag
   - Public function

3. Add internal `_load_state_impl(request_id, path, optimizer, state)`
   - Request builder
   - API call
   - Response handling

### Phase 3: TrainingClient Save Method (4 hours)

1. Add `save_state(client, name, opts)`
   - GenServer handler
   - Public function
   - Task wrapper
   - Response parsing

### Phase 4: ServiceClient Integration (4 hours)

1. Add `create_training_client_from_state(service, path, opts)`
   - REST API integration
   - Architecture detection
   - Client creation
   - Weight loading
   - Error handling

### Phase 5: Testing (8 hours)

1. Unit tests for each method
2. Integration tests for workflows
3. Round-trip tests (save → load → verify)
4. Wire protocol compatibility tests

**Total Implementation Time:** ~24 hours (3 days)

---

## Compatibility Matrix

| Feature | Python→Python | Python→Elixir | Elixir→Python | Elixir→Elixir |
|---------|---------------|---------------|---------------|---------------|
| Save checkpoint | ✅ Works | ❌ Cannot read (no load_state) | ❌ Cannot write (no save_state) | ❌ Neither works |
| Load checkpoint | ✅ Works | ❌ Cannot load | ❌ Wrong field name | ❌ Both broken |
| Load with optimizer | ✅ Works | ❌ Cannot load | ❌ Wrong field name | ❌ Both broken |
| Sampler weights | ✅ Works | ✅ Works | ✅ Works | ✅ Works |

**Cross-language compatibility:** BROKEN for all training checkpoints

---

## Risk Assessment

### High Risks

1. **Data Loss Risk**
   - Cannot save training checkpoints in Elixir
   - No disaster recovery
   - Training progress lost on crash

2. **Migration Risk**
   - Cannot migrate from Python to Elixir (can't load checkpoints)
   - Cannot share checkpoints between languages
   - Vendor lock-in to Python

3. **Production Risk**
   - Cannot resume long-running training
   - Cannot do checkpoint-based deployment
   - Cannot perform rolling updates with state

### Medium Risks

1. **Developer Experience Risk**
   - Confusing partial implementation
   - Documentation mismatch
   - API inconsistency

2. **Testing Risk**
   - Cannot test checkpoint workflows
   - Cannot verify state persistence
   - Cannot do integration testing

---

## Recommendations

### Immediate Actions (This Sprint)

1. **Fix wire protocol bug** - 2 hours, unblocks everything
2. **Implement load_state()** - 4 hours, enables checkpoint loading
3. **Implement save_state()** - 4 hours, enables checkpoint creation
4. **Basic testing** - 4 hours, ensures correctness

**Total:** ~14 hours (1.5 days) - Gets to minimal viable checkpoint support

### Short-Term Actions (Next Sprint)

1. **Implement load_state_with_optimizer()** - 2 hours
2. **Implement create_training_client_from_state()** - 4 hours
3. **Comprehensive testing** - 8 hours
4. **Documentation** - 4 hours

**Total:** ~18 hours (2 days) - Full feature parity

### Long-Term Actions (Future)

1. Add async versions for consistency
2. Add advanced checkpoint features (versioning, metadata, etc.)
3. Add checkpoint migration utilities
4. Performance optimization

---

## Success Criteria

The gap is closed when:

1. ✅ LoadWeightsRequest uses correct field name (`optimizer`)
2. ✅ TrainingClient.save_state() saves training checkpoints
3. ✅ TrainingClient.load_state() loads checkpoints without optimizer
4. ✅ TrainingClient.load_state_with_optimizer() loads checkpoints with optimizer
5. ✅ ServiceClient.create_training_client_from_state() creates clients from checkpoints
6. ✅ All tests pass (unit + integration)
7. ✅ Python and Elixir clients can share checkpoints
8. ✅ Documentation is complete and accurate

---

## Conclusion

The Elixir implementation has **58% feature coverage** and is missing **5 critical features**. The good news is that all the underlying infrastructure exists - the API functions work, the types are mostly defined, and the sequencing mechanisms are ready. The gap is primarily in the **high-level API surface** exposed through TrainingClient and ServiceClient.

The **wire protocol incompatibility** is the most critical issue and must be fixed before any checkpoint loading can work. After that, implementing the missing methods is straightforward - they all follow the same patterns as existing methods like `save_weights_for_sampler()`.

**Estimated total effort:** 24-32 hours (3-4 days) for complete feature parity.
