# Python Training Persistence Implementation

**Date:** 2025-11-26
**Status:** Complete Analysis
**Source:** `tinkex/tinker/src/tinker/lib/public_interfaces/training_client.py`

## Overview

The Python Tinker SDK provides comprehensive checkpoint persistence capabilities through the `TrainingClient` and `ServiceClient` classes. This document provides a complete analysis of the implementation.

---

## TrainingClient Methods

### 1. `save_state(name: str)` → `APIFuture[SaveWeightsResponse]`

**Location:** Lines 479-524

**Purpose:** Save model weights to persistent storage

**Implementation:**

```python
@capture_exceptions(fatal=True)
def save_state(self, name: str) -> APIFuture[types.SaveWeightsResponse]:
    """Save model weights to persistent storage.

    Args:
    - `name`: Name for the saved checkpoint

    Returns:
    - `APIFuture` containing the save response with checkpoint path
    """
    request_id = self._get_request_id()

    @capture_exceptions(fatal=True)
    async def _save_state_async():
        start_time = time.time()

        async def _send_request():
            request = types.SaveWeightsRequest(
                model_id=self._guaranteed_model_id(),
                path=name,
                seq_id=request_id + 1,
            )
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                return await client.weights.save(
                    request=request,
                )

        async with self._take_turn(request_id):
            future = await self.holder.execute_with_retries(_send_request)
        return await _APIFuture(
            types.SaveWeightsResponse,
            self.holder,
            future,
            request_start_time=start_time,
            request_type="SaveWeights",
            queue_state_observer=self,
        )

    return self.holder.run_coroutine_threadsafe(_save_state_async())
```

**Key Features:**
- Sequential request ordering via `_get_request_id()` and `_take_turn()`
- Retry logic via `execute_with_retries()`
- Request type tracking: "SaveWeights"
- Returns `SaveWeightsResponse` with checkpoint path
- Exception handling with `@capture_exceptions`

**HTTP Details:**
- Endpoint: `POST /api/v1/save_weights`
- Request type: `SaveWeightsRequest`
- Response type: `SaveWeightsResponse`

---

### 2. `load_state(path: str)` → `APIFuture[LoadWeightsResponse]`

**Location:** Lines 560-578

**Purpose:** Load model weights WITHOUT optimizer state

**Implementation:**

```python
@capture_exceptions(fatal=True)
def load_state(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights from a saved checkpoint.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

    Returns:
    - `APIFuture` containing the load response
    """
    request_id = self._get_request_id()
    return self.holder.run_coroutine_threadsafe(self._load_state_impl(request_id, path, False))
```

**Key Features:**
- Calls `_load_state_impl(request_id, path, optimizer=False)`
- Does NOT load optimizer state (momentum, variance)
- Useful for transfer learning or inference from checkpoint
- Lighter weight than `load_state_with_optimizer`

---

### 3. `load_state_with_optimizer(path: str)` → `APIFuture[LoadWeightsResponse]`

**Location:** Lines 585-605

**Purpose:** Load model weights AND optimizer state for training continuation

**Implementation:**

```python
@capture_exceptions(fatal=True)
def load_state_with_optimizer(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights and optimizer state from a checkpoint.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

    Returns:
    - `APIFuture` containing the load response

    Example:
    ```python
    # Resume training with optimizer state
    load_future = training_client.load_state_with_optimizer(
        "tinker://run-id/weights/checkpoint-001"
    )
    await load_future
    # Continue training with restored optimizer momentum
    ```
    """
    request_id = self._get_request_id()
    return self.holder.run_coroutine_threadsafe(self._load_state_impl(request_id, path, True))
```

**Key Features:**
- Calls `_load_state_impl(request_id, path, optimizer=True)`
- **CRITICAL:** Loads optimizer state (Adam momentum and variance)
- Essential for resuming training with same convergence characteristics
- Heavier weight than `load_state`

**Use Cases:**
- Resume training after interruption
- Continue fine-tuning from checkpoint
- Maintain optimizer momentum across training sessions

---

### 4. `_load_state_impl(request_id, path, optimizer)` → `LoadWeightsResponse`

**Location:** Lines 531-557

**Purpose:** Shared implementation for both load methods

**Implementation:**

```python
@capture_exceptions(fatal=True)
async def _load_state_impl(
    self, request_id: int, path: str, optimizer: bool
) -> types.LoadWeightsResponse:
    start_time = time.time()

    async def _send_request():
        request = types.LoadWeightsRequest(
            model_id=self._guaranteed_model_id(),
            path=path,
            seq_id=request_id + 1,
            optimizer=optimizer,  # ← CRITICAL: Field name is "optimizer"
        )
        with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
            return await client.weights.load(
                request=request,
            )

    async with self._take_turn(request_id):
        future = await self.holder.execute_with_retries(_send_request)
    return await _APIFuture(
        types.LoadWeightsResponse,
        self.holder,
        future,
        request_start_time=start_time,
        request_type="LoadWeights",
        queue_state_observer=self,
    )
```

**Key Features:**
- Single implementation serving both load methods
- `optimizer` parameter controls whether optimizer state is loaded
- Sequential request ordering via `_take_turn()`
- Retry logic
- Request type tracking: "LoadWeights"

**HTTP Details:**
- Endpoint: `POST /api/v1/load_weights`
- Request type: `LoadWeightsRequest`
- Response type: `LoadWeightsResponse`

---

## ServiceClient Methods

### 5. `create_training_client_from_state(path, user_metadata)` → `TrainingClient`

**Location:** Lines 222-254

**Purpose:** Create a new TrainingClient loaded from a checkpoint

**Implementation:**

```python
@sync_only
@capture_exceptions(fatal=True)
def create_training_client_from_state(
    self, path: str, user_metadata: dict[str, str] | None = None
) -> TrainingClient:
    """Create a TrainingClient from saved model weights.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
    - `user_metadata`: Optional metadata to attach to the new training run

    Returns:
    - `TrainingClient` loaded with the specified weights

    Example:
    ```python
    # Resume training from a checkpoint
    training_client = service_client.create_training_client_from_state(
        "tinker://run-id/weights/checkpoint-001"
    )
    # Continue training from the loaded state
    ```
    """
    rest_client = self.create_rest_client()
    # Use weights info endpoint which allows access to models with public checkpoints
    weights_info = rest_client.get_weights_info_by_tinker_path(path).result()

    training_client = self.create_lora_training_client(
        base_model=weights_info.base_model,
        rank=weights_info.lora_rank,
        user_metadata=user_metadata,
    )

    training_client.load_state(path).result()
    return training_client
```

**Workflow:**
1. **Query checkpoint metadata** via REST API (`get_weights_info_by_tinker_path`)
2. **Extract base model and LoRA rank** from checkpoint metadata
3. **Create new TrainingClient** with same architecture
4. **Load weights** into new client (WITHOUT optimizer state)
5. **Return configured client** ready for training

**Key Features:**
- Automatic architecture detection from checkpoint
- Creates fresh optimizer state (does NOT load old optimizer)
- Two-step process: create client → load weights
- Supports public checkpoints via REST API

**Async Version:** Lines 257-276 (`create_training_client_from_state_async`)

---

## Type Definitions

### SaveWeightsRequest

**Location:** `tinkex/tinker/src/tinker/types/save_weights_request.py`

```python
class SaveWeightsRequest(StrictBase):
    model_id: ModelID
    path: Optional[str] = None
    seq_id: Optional[int] = None
    type: Literal["save_weights"] = "save_weights"
```

**Wire Format:**
```json
{
  "model_id": "run-123",
  "path": "checkpoint-001",
  "seq_id": 1,
  "type": "save_weights"
}
```

---

### SaveWeightsResponse

**Location:** `tinkex/tinker/src/tinker/types/save_weights_response.py`

```python
class SaveWeightsResponse(BaseModel):
    path: str
    """A tinker URI for model weights at a specific step"""
    type: Optional[Literal["save_weights"]] = None
```

**Wire Format:**
```json
{
  "path": "tinker://run-123/weights/checkpoint-001",
  "type": "save_weights"
}
```

---

### LoadWeightsRequest

**Location:** `tinkex/tinker/src/tinker/types/load_weights_request.py`

```python
class LoadWeightsRequest(StrictBase):
    model_id: ModelID
    path: str
    """A tinker URI for model weights at a specific step"""

    optimizer: bool  # ← CRITICAL: Field name is "optimizer"
    """Whether to load optimizer state along with model weights"""

    seq_id: Optional[int] = None
    type: Literal["load_weights"] = "load_weights"
```

**Wire Format:**
```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 2,
  "optimizer": true,
  "type": "load_weights"
}
```

**CRITICAL:** The field name is `optimizer`, NOT `load_optimizer_state`

---

### LoadWeightsResponse

**Location:** `tinkex/tinker/src/tinker/types/load_weights_response.py`

```python
class LoadWeightsResponse(BaseModel):
    path: Optional[str] = None
    """A tinker URI for model weights at a specific step"""
    type: Optional[Literal["load_weights"]] = None
```

**Wire Format:**
```json
{
  "path": "tinker://run-123/weights/checkpoint-001",
  "type": "load_weights"
}
```

---

## HTTP Endpoints

### POST /api/v1/save_weights

**Location:** `tinkex/tinker/src/tinker/resources/weights.py` lines 68-112

```python
async def save(
    self,
    *,
    request: SaveWeightsRequest,
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    idempotency_key: str | None = None,
    max_retries: int | NotGiven = NOT_GIVEN,
) -> UntypedAPIFuture:
    """
    Saves model weights to disk

    Args:
      request: The save weights request containing model_id, path, and seq_id
    """
    options = make_request_options(
        extra_headers=extra_headers,
        extra_query=extra_query,
        extra_body=extra_body,
        timeout=timeout,
        idempotency_key=idempotency_key,
    )
    if max_retries is not NOT_GIVEN:
        options["max_retries"] = max_retries

    return await self._post(
        "/api/v1/save_weights",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=UntypedAPIFuture,
    )
```

**Request:** `SaveWeightsRequest`
**Response:** `UntypedAPIFuture` → eventually `SaveWeightsResponse`

---

### POST /api/v1/load_weights

**Location:** `tinkex/tinker/src/tinker/resources/weights.py` lines 22-66

```python
async def load(
    self,
    *,
    request: LoadWeightsRequest,
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    idempotency_key: str | None = None,
    max_retries: int | NotGiven = NOT_GIVEN,
) -> UntypedAPIFuture:
    """
    Loads model weights from disk

    Args:
      request: The load weights request containing model_id, path, and seq_id
    """
    options = make_request_options(
        extra_headers=extra_headers,
        extra_query=extra_query,
        extra_body=extra_body,
        timeout=timeout,
        idempotency_key=idempotency_key,
    )
    if max_retries is not NOT_GIVEN:
        options["max_retries"] = max_retries

    return await self._post(
        "/api/v1/load_weights",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=UntypedAPIFuture,
    )
```

**Request:** `LoadWeightsRequest`
**Response:** `UntypedAPIFuture` → eventually `LoadWeightsResponse`

---

## Complete Checkpoint Lifecycle

### 1. Save Checkpoint During Training

```python
# During training loop
training_client = service_client.create_lora_training_client(
    base_model="Qwen/Qwen2.5-7B"
)

# Train...
fwdbwd_future = training_client.forward_backward(data, "cross_entropy")
optim_future = training_client.optim_step(types.AdamParams(learning_rate=1e-4))

# Save checkpoint
save_future = training_client.save_state("checkpoint-001")
result = await save_future
print(f"Saved to: {result.path}")  # tinker://run-123/weights/checkpoint-001
```

### 2. Resume Training (WITH optimizer state)

```python
# Create new client from checkpoint
training_client = service_client.create_training_client_from_state(
    "tinker://run-123/weights/checkpoint-001"
)

# Continue training - optimizer state preserved
fwdbwd_future = training_client.forward_backward(data, "cross_entropy")
optim_future = training_client.optim_step(types.AdamParams(learning_rate=1e-4))
```

**Note:** `create_training_client_from_state` calls `load_state()` (NOT `load_state_with_optimizer()`), so optimizer state is NOT preserved.

### 3. Manual Load with Optimizer State

```python
# Create fresh client
training_client = service_client.create_lora_training_client(
    base_model="Qwen/Qwen2.5-7B", rank=32
)

# Load weights AND optimizer state
load_future = training_client.load_state_with_optimizer(
    "tinker://run-123/weights/checkpoint-001"
)
await load_future

# Continue training with full state
```

---

## Key Observations

### 1. Sequential Request Ordering

All persistence operations use:
- `_get_request_id()` to allocate unique IDs
- `_take_turn(request_id)` to ensure sequential execution
- Prevents race conditions in checkpoint loading/saving

### 2. Retry Logic

All operations use `execute_with_retries()`:
- Automatic retry on transient failures
- Configurable retry policy
- Exception handling and logging

### 3. Optimizer State Separation

Two distinct load modes:
- `load_state()` - Weights only (lighter, fresh optimizer)
- `load_state_with_optimizer()` - Weights + optimizer (full state)

This enables:
- Transfer learning (weights only)
- Training continuation (weights + optimizer)

### 4. Async/Sync Wrappers

Most methods have both:
- Sync version (blocking, for simple usage)
- Async version (non-blocking, for advanced usage)

Example:
- `save_state()` - sync
- `save_state_async()` - async

### 5. REST API Integration

`create_training_client_from_state` uses REST API to:
- Query checkpoint metadata
- Extract base model and architecture
- Support public checkpoints

---

## Missing Features in Elixir

Based on this analysis, Elixir is missing:

1. **TrainingClient.save_state()** - Only has `save_weights_for_sampler()`
2. **TrainingClient.load_state()** - No checkpoint loading
3. **TrainingClient.load_state_with_optimizer()** - No optimizer state loading
4. **ServiceClient.create_training_client_from_state()** - No checkpoint-based client creation

---

## Wire Protocol Compatibility Issues

**CRITICAL MISMATCH:**

Python uses:
```json
{
  "optimizer": true
}
```

Elixir uses:
```json
{
  "load_optimizer_state": true
}
```

This will cause **wire protocol incompatibility**. The server will not understand Elixir's field name.

---

## Summary

The Python SDK provides a complete, production-ready checkpoint persistence system with:
- Sequential request ordering
- Retry logic
- Optimizer state management
- REST API integration
- Full async/sync support

The Elixir port is missing all checkpoint loading capabilities and has a wire protocol compatibility issue that must be fixed.
