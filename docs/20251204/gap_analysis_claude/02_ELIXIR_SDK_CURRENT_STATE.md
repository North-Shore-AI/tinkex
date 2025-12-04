# Elixir tinkex SDK: Current State Analysis

**Source**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/`
**Date**: December 4, 2025

---

## Architecture Overview

```
lib/tinkex/
├── api/                    # Low-level HTTP API
│   ├── api.ex              # HTTP client core (1115 lines)
│   ├── training.ex         # Training operations
│   ├── weights.ex          # Weight save/load
│   ├── sampling.ex         # Text generation
│   ├── rest.ex             # REST endpoints
│   ├── models.ex           # Model lifecycle
│   ├── service.ex          # Service & session
│   ├── session.ex          # Session heartbeat
│   ├── futures.ex          # Future polling
│   ├── telemetry.ex        # Telemetry events
│   └── helpers.ex          # Response utilities
├── types/                  # Type definitions (69 files)
├── training_client.ex      # GenServer training orchestrator
├── sampling_client.ex      # Sampling client
├── rest_client.ex          # REST client wrapper
├── session_manager.ex      # Session lifecycle
├── checkpoint_download.ex  # Streaming downloads
├── retry*.ex               # Retry infrastructure
├── future.ex               # Future polling
└── error.ex                # Error types
```

---

## 1. API Module Functions

### api.ex - HTTP Client Core

| Function | Purpose | Notes |
|----------|---------|-------|
| `post(path, body, opts)` | POST with retries | Telemetry instrumented |
| `get(path, opts)` | GET with retries | |
| `delete(path, opts)` | DELETE with retries | |
| `stream_get(path, opts)` | SSE streaming | |

**Features:**
- Finch-based HTTP client
- Separate connection pools per operation type
- Automatic retry with exponential backoff
- Telemetry events on all requests

### training.ex - Training Operations

| Function | Returns | Python Equivalent |
|----------|---------|-------------------|
| `forward(request, opts)` | result | `training.forward()` |
| `forward_future(request, opts)` | future_id | N/A (enhancement) |
| `forward_backward(request, opts)` | result | `training.forward_backward()` |
| `forward_backward_future(request, opts)` | future_id | N/A (enhancement) |
| `optim_step(request, opts)` | result | `training.optim_step()` |
| `optim_step_future(request, opts)` | future_id | N/A (enhancement) |

### weights.ex - Weight Management

| Function | Returns | Python Equivalent |
|----------|---------|-------------------|
| `save_weights(request, opts)` | result | `weights.save()` |
| `save_weights_typed(request, opts)` | SaveWeightsResponse.t() | N/A (enhancement) |
| `load_weights(request, opts)` | result | `weights.load()` |
| `load_weights_typed(request, opts)` | LoadWeightsResponse.t() | N/A (enhancement) |
| `save_weights_for_sampler(request, opts)` | result | `weights.save_for_sampler()` |
| `save_weights_for_sampler_typed(request, opts)` | typed response | N/A (enhancement) |

### sampling.ex - Text Generation

| Function | Notes |
|----------|-------|
| `sample_async(request, opts)` | Uses `:sampling` pool (100 connections) |

**Features:**
- `max_retries: 0` at HTTP layer (client-side rate limiting)
- Backpressure header: `x-tinker-sampling-backpressure`
- Nil value filtering

### rest.ex - REST Endpoints (14 functions)

| Function | Python Equivalent |
|----------|-------------------|
| `get_session(config, session_id)` | `rest_client.get_session()` |
| `list_sessions(config, limit, offset)` | `rest_client.list_sessions()` |
| `list_checkpoints(config, run_id)` | `rest_client.list_checkpoints()` |
| `list_user_checkpoints(config, limit, offset)` | `rest_client.list_user_checkpoints()` |
| `get_checkpoint_archive_url(config, path)` | `rest_client.get_checkpoint_archive_url_from_tinker_path()` |
| `get_checkpoint_archive_url(config, run_id, cp_id)` | `rest_client.get_checkpoint_archive_url()` |
| `delete_checkpoint(config, path)` | `rest_client.delete_checkpoint_from_tinker_path()` |
| `delete_checkpoint(config, run_id, cp_id)` | `rest_client.delete_checkpoint()` |
| `get_sampler(config, sampler_id)` | `rest_client.get_sampler()` |
| `get_weights_info_by_tinker_path(config, path)` | `rest_client.get_weights_info_by_tinker_path()` |
| `get_training_run_by_tinker_path(config, path)` | `rest_client.get_training_run_by_tinker_path()` |
| `get_training_run(config, run_id)` | `rest_client.get_training_run()` |
| `list_training_runs(config, limit, offset)` | `rest_client.list_training_runs()` |
| `publish_checkpoint(config, path)` | `rest_client.publish_checkpoint_from_tinker_path()` |
| `unpublish_checkpoint(config, path)` | `rest_client.unpublish_checkpoint_from_tinker_path()` |

---

## 2. High-Level Clients

### TrainingClient (GenServer)

**File**: `training_client.ex`

| Function | Status |
|----------|--------|
| `forward/2` | ✅ Implemented |
| `forward_backward/2` | ✅ Implemented |
| `optim_step/2` | ✅ Implemented |
| `save_weights/2` | ✅ Implemented |
| `load_weights/2` | ✅ Implemented |
| `get_tokenizer/2` | ✅ Implemented |
| `load_weights_with_optimizer/2` | ❌ **MISSING** |

**Architecture:**
- GenServer managing single model training
- Sequential operation execution via `:training` pool
- Integrates with Future polling

### SamplingClient

**File**: `sampling_client.ex`

| Function | Status |
|----------|--------|
| `sample/4` | ✅ Implemented |
| `compute_logprobs/2` | ❌ **MISSING** |

### RestClient

**File**: `rest_client.ex`

All REST operations implemented with both sync and async variants.

### SessionManager (GenServer)

**File**: `session_manager.ex`

| Feature | Status |
|---------|--------|
| Session creation | ✅ |
| Heartbeats (10s) | ✅ |
| ETS persistence | ✅ |
| Failure tracking | ✅ |
| Auto-removal unhealthy | ✅ |

---

## 3. Retry Infrastructure

### RetryConfig

**File**: `retry_config.ex`

```elixir
defstruct [
  max_retries: :infinity,
  base_delay_ms: 500,
  max_delay_ms: 10_000,
  jitter_pct: 0.25,
  progress_timeout_ms: 7_200_000,  # 2 hours
  max_connections: 1000,
  enable_retry_logic: true
]
```

### RetryHandler

**File**: `retry_handler.ex`

- Exponential backoff: `base * 2^attempt`, capped at max
- Jitter: ±(jitter_pct * capped_delay)
- Progress timeout tracking
- Methods: `retry?/2`, `next_delay/1`, `progress_timeout?/1`

### Retry Module

**File**: `retry.ex`

- `with_retry/2` - Core retry wrapper
- Telemetry events: `:start`, `:stop`, `:retry`, `:failed`
- Wraps both errors and exceptions

---

## 4. Type System

### Implemented Types (69 files)

**Core Data:**
- TensorData, TensorDtype
- Datum, ModelInput
- EncodedTextChunk, ImageChunk, ImageAssetPointerChunk

**Requests:**
- CreateSessionRequest/Response
- CreateModelRequest/Response
- ForwardRequest, ForwardBackwardRequest, ForwardBackwardInput
- OptimStepRequest/Response
- SampleRequest/Response, SampledSequence, SamplingParams
- CreateSamplingSessionRequest/Response

**Checkpoints:**
- Checkpoint
- ParsedCheckpointTinkerPath
- SaveWeightsRequest/Response
- LoadWeightsRequest/Response

**Configuration:**
- AdamParams (defaults match Python: lr=0.0001, beta1=0.9, beta2=0.95, eps=1e-12)
- LoraConfig

**Telemetry:**
- TelemetryEvent (union)
- EventType, Severity
- GenericEvent, SessionStartEvent, SessionEndEvent

**Errors:**
- RequestErrorCategory
- RequestFailedResponse
- TryAgainResponse
- QueueState, StopReason, LossFnType

**Metadata:**
- TrainingRun (partial - see gaps)
- SupportedModel
- GetServerCapabilitiesResponse
- HealthResponse
- Cursor, ModelData, GetInfoResponse
- WeightsInfoResponse

### Elixir-Specific Extensions

Types not in Python SDK (research features):

- `RegularizerSpec` - Regularizer configuration
- `RegularizerOutput` - Regularizer computation results
- `CustomLossOutput` - Loss with regularizer breakdown

---

## 5. Checkpoint Download

**File**: `checkpoint_download.ex`

**Features:**
- Streaming via `Finch.stream_while/5` (O(1) memory)
- Progress callbacks
- Automatic tar extraction
- Force overwrite option
- Handles 100MB-GB files

---

## 6. Future Polling

**File**: `future.ex`

| Function | Purpose |
|----------|---------|
| `poll/2` | Returns Task for background polling |
| `await/2` | Await single future with timeout |
| `await_many/2` | Await multiple futures |

**Features:**
- Exponential backoff: 1s to 30s
- Queue state tracking: `:active`, `:paused_rate_limit`, `:paused_capacity`
- Handles all future response types

---

## 7. Error Handling

**File**: `error.ex`

```elixir
defstruct [
  type: :api_connection | :api_timeout | :api_status | :request_failed | :validation,
  message: String.t(),
  status_code: integer() | nil,
  category: RequestErrorCategory.t() | nil,
  retry_after_ms: integer() | nil
]
```

**Helpers:**
- `user_error?/1` - Detects 4xx (except 408/429)
- `retryable?/1` - Checks if error is retryable

---

## 8. Telemetry Events

**Namespace**: `[:tinkex, ...]`

| Event | Purpose |
|-------|---------|
| `[:tinkex, :http, :request, :start]` | HTTP request start |
| `[:tinkex, :http, :request, :stop]` | HTTP request complete |
| `[:tinkex, :http, :request, :exception]` | HTTP request failed |
| `[:tinkex, :queue, :state_change]` | Queue state changed |
| `[:tinkex, :retry, :start]` | Retry attempt start |
| `[:tinkex, :retry, :stop]` | Retry attempt complete |
| `[:tinkex, :retry, :failed]` | All retries exhausted |

---

## 9. Connection Pools

| Pool | Purpose | Connections |
|------|---------|-------------|
| `:training` | Training operations | Default |
| `:sampling` | Sample requests | 100 |
| `:session` | Heartbeats | Default |
| `:futures` | Future polling | 50 |

---

## Summary: What's Working

| Category | Status | Notes |
|----------|--------|-------|
| HTTP client | ✅ Complete | Finch-based, pooled |
| Retry logic | ✅ Complete | Matches Python SDK |
| Training ops | ✅ Complete | All 3 operations |
| Weight ops | ✅ Complete | Save/load basic |
| Sampling | ✅ Complete | With backpressure |
| REST endpoints | ✅ Complete | All 14 endpoints |
| Session mgmt | ✅ Complete | Heartbeats, persistence |
| Checkpoint download | ✅ Complete | Streaming |
| Future polling | ✅ Complete | With queue state |
| Error handling | ✅ Complete | Categorized |
| Telemetry | ✅ Complete | Full instrumentation |
| Types | ⚠️ Partial | 69/71 files, gaps exist |
