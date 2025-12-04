# Python Tinker SDK: Complete API Inventory

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/`
**Date**: December 4, 2025

---

## 1. ServiceClient (Entry Point)

**File**: `lib/public_interfaces/service_client.py`

### Constructor
```python
ServiceClient(user_metadata: dict[str, str] | None = None, **kwargs)
```

### Client Creation Methods

| Method | Parameters | Returns | Notes |
|--------|------------|---------|-------|
| `create_lora_training_client()` | base_model, rank=32, seed, train_mlp, train_attn, train_unembed, user_metadata | TrainingClient | 10-30s latency |
| `create_lora_training_client_async()` | (same) | TrainingClient | Async variant |
| `create_training_client_from_state()` | path, user_metadata | TrainingClient | Weights only |
| `create_training_client_from_state_async()` | (same) | TrainingClient | Async variant |
| `create_training_client_from_state_with_optimizer()` | path, user_metadata | TrainingClient | **Full state restore** |
| `create_training_client_from_state_with_optimizer_async()` | (same) | TrainingClient | Async variant |
| `create_sampling_client()` | model_path, base_model, retry_config | SamplingClient | <1s latency |
| `create_sampling_client_async()` | (same) | SamplingClient | Async variant |
| `create_rest_client()` | (none) | RestClient | Instant |

### Server Operations

| Method | Returns |
|--------|---------|
| `get_server_capabilities()` | GetServerCapabilitiesResponse |
| `get_server_capabilities_async()` | GetServerCapabilitiesResponse |
| `get_telemetry()` | Telemetry \| None |

---

## 2. TrainingClient

**File**: `lib/public_interfaces/training_client.py` (906 lines)

### Training Operations

| Method | Parameters | Returns |
|--------|------------|---------|
| `forward()` | data, loss_fn, loss_fn_config | APIFuture[ForwardBackwardOutput] |
| `forward_async()` | (same) | APIFuture[ForwardBackwardOutput] |
| `forward_backward()` | data, loss_fn, loss_fn_config | APIFuture[ForwardBackwardOutput] |
| `forward_backward_async()` | (same) | APIFuture[ForwardBackwardOutput] |
| `forward_backward_custom()` | data, loss_fn (callable) | APIFuture[ForwardBackwardOutput] |
| `forward_backward_custom_async()` | (same) | APIFuture[ForwardBackwardOutput] |
| `optim_step()` | adam_params | APIFuture[OptimStepResponse] |
| `optim_step_async()` | (same) | APIFuture[OptimStepResponse] |

### Checkpoint Operations

| Method | Parameters | Returns | Notes |
|--------|------------|---------|-------|
| `save_state()` | name | APIFuture[SaveWeightsResponse] | Returns tinker:// path |
| `save_state_async()` | (same) | APIFuture[SaveWeightsResponse] | |
| `load_state()` | path | APIFuture[LoadWeightsResponse] | **Weights only** |
| `load_state_async()` | (same) | APIFuture[LoadWeightsResponse] | |
| `load_state_with_optimizer()` | path | APIFuture[LoadWeightsResponse] | **Full state** |
| `load_state_with_optimizer_async()` | (same) | APIFuture[LoadWeightsResponse] | |
| `save_weights_for_sampler()` | name | APIFuture[SaveWeightsForSamplerResponse] | |
| `save_weights_for_sampler_async()` | (same) | APIFuture[SaveWeightsForSamplerResponse] | |

### Sampler Creation from Training

| Method | Parameters | Returns |
|--------|------------|---------|
| `create_sampling_client()` | model_path, retry_config | SamplingClient |
| `create_sampling_client_async()` | (same) | SamplingClient |
| `save_weights_and_get_sampling_client()` | name, retry_config | SamplingClient |
| `save_weights_and_get_sampling_client_async()` | (same) | SamplingClient |

### Metadata

| Method | Returns |
|--------|---------|
| `get_info()` | GetInfoResponse |
| `get_info_async()` | GetInfoResponse |
| `get_tokenizer()` | PreTrainedTokenizer |
| `get_telemetry()` | Telemetry \| None |

---

## 3. SamplingClient

**File**: `lib/public_interfaces/sampling_client.py` (325 lines)

| Method | Parameters | Returns | Notes |
|--------|------------|---------|-------|
| `sample()` | prompt, num_samples, sampling_params, include_prompt_logprobs, topk_prompt_logprobs | ConcurrentFuture[SampleResponse] | |
| `sample_async()` | (same) | ConcurrentFuture[SampleResponse] | |
| `compute_logprobs()` | prompt | ConcurrentFuture[list[float\|None]] | **Missing in Elixir** |
| `compute_logprobs_async()` | (same) | ConcurrentFuture[list[float\|None]] | |

### Concurrency Control
- `_sample_dispatch_semaphore`: 400 concurrent requests max
- `_sample_backoff_until`: 1-second backoff on 429

---

## 4. RestClient

**File**: `lib/public_interfaces/rest_client.py` (708 lines)

### Training Run Operations

| Method | Parameters | Returns |
|--------|------------|---------|
| `get_training_run()` | training_run_id | TrainingRun |
| `get_training_run_async()` | (same) | TrainingRun |
| `get_training_run_by_tinker_path()` | tinker_path | TrainingRun |
| `get_training_run_by_tinker_path_async()` | (same) | TrainingRun |
| `list_training_runs()` | limit=20, offset=0 | TrainingRunsResponse |
| `list_training_runs_async()` | (same) | TrainingRunsResponse |

### Checkpoint Operations

| Method | Parameters | Returns |
|--------|------------|---------|
| `list_checkpoints()` | training_run_id | CheckpointsListResponse |
| `list_checkpoints_async()` | (same) | CheckpointsListResponse |
| `list_user_checkpoints()` | limit=100, offset=0 | CheckpointsListResponse |
| `list_user_checkpoints_async()` | (same) | CheckpointsListResponse |
| `get_checkpoint_archive_url()` | training_run_id, checkpoint_id | CheckpointArchiveUrlResponse |
| `get_checkpoint_archive_url_async()` | (same) | CheckpointArchiveUrlResponse |
| `get_checkpoint_archive_url_from_tinker_path()` | tinker_path | CheckpointArchiveUrlResponse |
| `get_checkpoint_archive_url_from_tinker_path_async()` | (same) | CheckpointArchiveUrlResponse |
| `delete_checkpoint()` | training_run_id, checkpoint_id | None |
| `delete_checkpoint_async()` | (same) | None |
| `delete_checkpoint_from_tinker_path()` | tinker_path | None |
| `delete_checkpoint_from_tinker_path_async()` | (same) | None |
| `publish_checkpoint_from_tinker_path()` | tinker_path | None |
| `publish_checkpoint_from_tinker_path_async()` | (same) | None |
| `unpublish_checkpoint_from_tinker_path()` | tinker_path | None |
| `unpublish_checkpoint_from_tinker_path_async()` | (same) | None |

### Session Operations

| Method | Parameters | Returns |
|--------|------------|---------|
| `get_session()` | session_id | GetSessionResponse |
| `get_session_async()` | (same) | GetSessionResponse |
| `list_sessions()` | limit=20, offset=0 | ListSessionsResponse |
| `list_sessions_async()` | (same) | ListSessionsResponse |

### Metadata Operations

| Method | Parameters | Returns |
|--------|------------|---------|
| `get_sampler()` | sampler_id | GetSamplerResponse |
| `get_sampler_async()` | (same) | GetSamplerResponse |
| `get_weights_info_by_tinker_path()` | tinker_path | WeightsInfoResponse |

---

## 5. Low-Level Resources

### training.py
- `forward()` → POST /api/v1/forward
- `forward_backward()` → POST /api/v1/forward_backward
- `optim_step()` → POST /api/v1/optim_step

### weights.py
- `save()` → POST /api/v1/save_weights
- `load()` → POST /api/v1/load_weights
- `save_for_sampler()` → POST /api/v1/save_weights_for_sampler

### sampling.py
- `asample()` → POST /api/v1/asample

### models.py
- `create()` → POST /api/v1/create_model
- `get_info()` → POST /api/v1/get_info
- `unload()` → POST /api/v1/unload_model

### service.py
- `get_server_capabilities()` → GET /api/v1/get_server_capabilities
- `health_check()` → GET /api/v1/healthz
- `create_session()` → POST /api/v1/create_session
- `session_heartbeat()` → POST /api/v1/session_heartbeat
- `create_sampling_session()` → POST /api/v1/create_sampling_session

---

## 6. Retry & Error Handling

### RetryConfig
```python
@dataclass
class RetryConfig:
    max_connections: int = 100
    progress_timeout: float = 7200  # 2 hours
    retry_delay_base: float = 0.5   # 500ms
    retry_delay_max: float = 10.0   # 10s
    jitter_factor: float = 0.25
    enable_retry_logic: bool = True
    retryable_exceptions: tuple = (
        asyncio.TimeoutError,
        tinker.APIConnectionError,
        httpx.TimeoutException,
        RetryableException,
    )
```

### Retryable Status Codes
- 408 (Request Timeout)
- 409 (Conflict)
- 429 (Rate Limited)
- 5xx (Server Errors)

---

## 7. Session Management

### Heartbeat
- Period: 10 seconds
- Warning threshold: 2 minutes without success
- Auto-reconnection attempts

### Connection Pooling
- Separate pools: TRAIN, SAMPLE, SESSION, FUTURES
- Max concurrent samples: 400

---

## 8. Key Types Reference

### TrainingRun (Critical for Recovery)
```python
class TrainingRun(BaseModel):
    training_run_id: str
    base_model: str
    model_owner: str
    is_lora: bool
    corrupted: bool = False  # ← CRITICAL FIELD
    lora_rank: int | None
    last_request_time: datetime
    last_checkpoint: Checkpoint | None
    last_sampler_checkpoint: Checkpoint | None
    user_metadata: dict[str, str] | None
```

### Checkpoint
```python
class Checkpoint(BaseModel):
    checkpoint_id: str
    checkpoint_type: CheckpointType  # "training" | "sampler"
    time: datetime
    tinker_path: str
    size_bytes: int | None
    public: bool = False
```

### AdamParams
```python
class AdamParams(StrictBase):
    learning_rate: float = 0.0001
    beta1: float = 0.9
    beta2: float = 0.95  # Note: non-standard default
    eps: float = 1e-12
```
