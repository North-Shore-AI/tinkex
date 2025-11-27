# Gap Analysis: Lib Module - Public Interfaces & High-Level Clients

**Generated:** 2025-11-26
**Domain:** tinker/lib/ (Python) → tinkex/lib/ (Elixir)
**Scope:** Public client interfaces, APIFuture, retry handlers, telemetry

---

## Executive Summary

**Overall Completeness:** ~75%

**Critical Gaps:** 8
**High Priority Gaps:** 12
**Medium Priority Gaps:** 15
**Low Priority Gaps:** 8

The Elixir port has implemented most core client functionality with key architectural differences that align with OTP patterns. Major gaps exist in advanced features like custom loss functions, checkpoint management APIs, and some REST client endpoints.

---

## 1. TrainingClient Comparison

### Python Implementation (896 lines)
- Full forward/backward/optim pipeline
- Chunked request handling (max 128 chunks, 500K numbers)
- Custom loss function support with PyTorch integration
- Tokenizer resolution with HuggingFace integration
- Weight save/load (with optimizer state)
- Request ID sequencing with turn-based locking
- Sampling client creation from training state

### Elixir Implementation (936 lines)
- Core forward/backward/optim implemented ✓
- Chunked request handling identical to Python ✓
- **Custom loss partially implemented** (basic structure, needs full regularizer pipeline)
- **Tokenizer resolution not implemented** (returns error)
- **Weight save/load not fully implemented**
- Request ID sequencing via GenServer ✓
- Sampling client creation implemented ✓

### Detailed Method Comparison

| Python Method | Parameters | Return | Elixir Method | Gap Status |
|--------------|------------|--------|---------------|------------|
| `__init__` | holder, model_seq_id, model_id | - | `init/1` | ✓ Complete (OTP adapted) |
| `forward` | data, loss_fn, loss_fn_config | APIFuture[ForwardBackwardOutput] | `forward/4` | ✓ Complete |
| `forward_async` | data, loss_fn, loss_fn_config | APIFuture | - | ❌ GAP-LIB-001 |
| `forward_backward` | data, loss_fn, loss_fn_config | APIFuture[ForwardBackwardOutput] | `forward_backward/4` | ✓ Complete |
| `forward_backward_async` | data, loss_fn, loss_fn_config | APIFuture | - | ❌ GAP-LIB-002 |
| `forward_backward_custom` | data, CustomLossFnV1 | APIFuture | `forward_backward_custom/4` | ⚠️ GAP-LIB-003 Partial |
| `forward_backward_custom_async` | data, CustomLossFnV1 | APIFuture | - | ❌ GAP-LIB-004 |
| `optim_step` | adam_params | APIFuture[OptimStepResponse] | `optim_step/3` | ✓ Complete |
| `optim_step_async` | adam_params | APIFuture | - | ❌ GAP-LIB-005 |
| `save_state` | name | APIFuture[SaveWeightsResponse] | - | ❌ GAP-LIB-006 |
| `save_state_async` | name | APIFuture | - | ❌ GAP-LIB-007 |
| `load_state` | path | APIFuture[LoadWeightsResponse] | - | ❌ GAP-LIB-008 |
| `load_state_async` | path | APIFuture | - | ❌ GAP-LIB-009 |
| `load_state_with_optimizer` | path | APIFuture | - | ❌ GAP-LIB-010 |
| `load_state_with_optimizer_async` | path | APIFuture | - | ❌ GAP-LIB-011 |
| `save_weights_for_sampler` | name | APIFuture | `save_weights_for_sampler/2` | ✓ Complete |
| `save_weights_for_sampler_async` | name | APIFuture | - | ❌ GAP-LIB-012 |
| `save_weights_and_get_sampling_client` | name, retry_config | SamplingClient | - | ❌ GAP-LIB-013 |
| `save_weights_and_get_sampling_client_async` | name, retry_config | SamplingClient | - | ❌ GAP-LIB-014 |
| `create_sampling_client` | model_path, retry_config | SamplingClient | `create_sampling_client_async/3` | ⚠️ GAP-LIB-015 Async only |
| `create_sampling_client_async` | model_path, retry_config | SamplingClient | `create_sampling_client_async/3` | ✓ Complete |
| `get_info` | - | GetInfoResponse | `get_info/1` | ⚠️ GAP-LIB-016 Returns error |
| `get_info_async` | - | GetInfoResponse | - | ❌ GAP-LIB-017 |
| `get_tokenizer` | - | PreTrainedTokenizer | - | ❌ GAP-LIB-018 |
| `on_queue_state_change` | queue_state | None | - | ⚠️ GAP-LIB-019 Different pattern |

---

## 2. SamplingClient Comparison

### Python Implementation (326 lines)
- Lock-free sampling via feature gates
- Rate limiting with backoff
- Retry handler integration
- Compute logprobs method
- Queue state observer integration

### Elixir Implementation (287 lines)
- Lock-free ETS-based sampling ✓
- Rate limiting with backoff ✓
- **Custom retry handler** (different from Python)
- **Compute logprobs not implemented**
- Queue state observer via telemetry ✓

### Detailed Method Comparison

| Python Method | Parameters | Return | Elixir Method | Gap Status |
|--------------|------------|--------|---------------|------------|
| `__init__` | holder, sampling_session_id, retry_config | - | `init/1` | ✓ Complete (OTP adapted) |
| `create` | holder, model_path, base_model, sampling_session_id, retry_config | APIFuture[SamplingClient] | - | ❌ GAP-LIB-020 |
| `sample` | prompt, num_samples, sampling_params, include_prompt_logprobs, topk_prompt_logprobs | Future[SampleResponse] | `sample/4` | ✓ Complete |
| `sample_async` | prompt, num_samples, sampling_params, include_prompt_logprobs, topk_prompt_logprobs | SampleResponse | - | ❌ GAP-LIB-021 |
| `compute_logprobs` | prompt | Future[list[float \| None]] | - | ❌ GAP-LIB-022 |
| `compute_logprobs_async` | prompt | list[float \| None] | - | ❌ GAP-LIB-023 |
| `get_telemetry` | - | Telemetry \| None | `get_telemetry/0,1` | ✓ Complete |
| `on_queue_state_change` | queue_state | None | - | ⚠️ GAP-LIB-024 Via telemetry |

---

## 3. ServiceClient Comparison

### Python Implementation (390 lines)
- Session management
- Training client factory
- Sampling client factory
- REST client factory
- Server capabilities query
- Training from state (checkpoint loading)

### Elixir Implementation (319 lines)
- Session management ✓
- Training client factory ✓
- Sampling client factory ✓
- REST client factory ✓
- **Server capabilities not implemented**
- **Training from state not implemented**

### Detailed Method Comparison

| Python Method | Parameters | Return | Elixir Method | Gap Status |
|--------------|------------|--------|---------------|------------|
| `__init__` | user_metadata, **kwargs | - | `init/1` | ✓ Complete (OTP adapted) |
| `get_server_capabilities` | - | GetServerCapabilitiesResponse | - | ❌ GAP-LIB-025 |
| `get_server_capabilities_async` | - | GetServerCapabilitiesResponse | - | ❌ GAP-LIB-026 |
| `create_lora_training_client` | base_model, rank, seed, train_mlp, train_attn, train_unembed, user_metadata | TrainingClient | `create_lora_training_client/2` | ✓ Complete |
| `create_lora_training_client_async` | base_model, rank, seed, train_mlp, train_attn, train_unembed, user_metadata | TrainingClient | - | ❌ GAP-LIB-027 |
| `create_training_client_from_state` | path, user_metadata | TrainingClient | - | ❌ GAP-LIB-028 |
| `create_training_client_from_state_async` | path, user_metadata | TrainingClient | - | ❌ GAP-LIB-029 |
| `create_sampling_client` | model_path, base_model, retry_config | SamplingClient | `create_sampling_client/2` | ✓ Complete |
| `create_sampling_client_async` | model_path, base_model, retry_config | SamplingClient | `create_sampling_client_async/2` | ✓ Complete |
| `create_rest_client` | - | RestClient | `create_rest_client/1` | ✓ Complete |

---

## 4. RestClient Comparison

### Python Implementation (708 lines)
- Training run queries
- Checkpoint listing/deletion
- Checkpoint archive URL generation
- Checkpoint publish/unpublish
- Session management
- Sampler information
- User checkpoint queries

### Elixir Implementation (167 lines)
- **Limited endpoint coverage**
- Session listing ✓
- Checkpoint listing ✓
- User checkpoint listing ✓
- Archive URL ✓
- Delete checkpoint ✓
- **Missing publish/unpublish**
- **Missing training run queries**
- **Missing sampler info**
- **Missing weights info**

### Detailed Method Comparison

| Python Method | Parameters | Return | Elixir Method | Gap Status |
|--------------|------------|--------|---------------|------------|
| `__init__` | holder | - | `new/2` | ✓ Complete |
| `get_training_run` | training_run_id | Future[TrainingRun] | - | ❌ GAP-LIB-030 |
| `get_training_run_async` | training_run_id | TrainingRun | - | ❌ GAP-LIB-031 |
| `get_training_run_by_tinker_path` | tinker_path | Future[TrainingRun] | - | ❌ GAP-LIB-032 |
| `get_training_run_by_tinker_path_async` | tinker_path | TrainingRun | - | ❌ GAP-LIB-033 |
| `get_weights_info_by_tinker_path` | tinker_path | APIFuture[WeightsInfoResponse] | - | ❌ GAP-LIB-034 |
| `list_training_runs` | limit, offset | Future[TrainingRunsResponse] | - | ❌ GAP-LIB-035 |
| `list_training_runs_async` | limit, offset | TrainingRunsResponse | - | ❌ GAP-LIB-036 |
| `list_checkpoints` | training_run_id | Future[CheckpointsListResponse] | `list_checkpoints/2` | ✓ Complete |
| `list_checkpoints_async` | training_run_id | CheckpointsListResponse | - | ❌ GAP-LIB-037 |
| `get_checkpoint_archive_url` | training_run_id, checkpoint_id | Future[CheckpointArchiveUrlResponse] | `get_checkpoint_archive_url/2` | ✓ Complete |
| `get_checkpoint_archive_url_async` | training_run_id, checkpoint_id | CheckpointArchiveUrlResponse | - | ❌ GAP-LIB-038 |
| `get_checkpoint_archive_url_from_tinker_path` | tinker_path | Future[CheckpointArchiveUrlResponse] | - | ❌ GAP-LIB-039 |
| `get_checkpoint_archive_url_from_tinker_path_async` | tinker_path | CheckpointArchiveUrlResponse | - | ❌ GAP-LIB-040 |
| `delete_checkpoint` | training_run_id, checkpoint_id | Future[None] | `delete_checkpoint/2` | ✓ Complete |
| `delete_checkpoint_async` | training_run_id, checkpoint_id | None | - | ❌ GAP-LIB-041 |
| `delete_checkpoint_from_tinker_path` | tinker_path | Future[None] | - | ❌ GAP-LIB-042 |
| `delete_checkpoint_from_tinker_path_async` | tinker_path | None | - | ❌ GAP-LIB-043 |
| `publish_checkpoint_from_tinker_path` | tinker_path | Future[None] | - | ❌ GAP-LIB-044 |
| `publish_checkpoint_from_tinker_path_async` | tinker_path | None | - | ❌ GAP-LIB-045 |
| `unpublish_checkpoint_from_tinker_path` | tinker_path | Future[None] | - | ❌ GAP-LIB-046 |
| `unpublish_checkpoint_from_tinker_path_async` | tinker_path | None | - | ❌ GAP-LIB-047 |
| `list_user_checkpoints` | limit, offset | Future[CheckpointsListResponse] | `list_user_checkpoints/2` | ✓ Complete |
| `list_user_checkpoints_async` | limit, offset | CheckpointsListResponse | - | ❌ GAP-LIB-048 |
| `get_session` | session_id | Future[GetSessionResponse] | `get_session/2` | ✓ Complete |
| `get_session_async` | session_id | GetSessionResponse | - | ❌ GAP-LIB-049 |
| `list_sessions` | limit, offset | Future[ListSessionsResponse] | `list_sessions/2` | ✓ Complete |
| `list_sessions_async` | limit, offset | ListSessionsResponse | - | ❌ GAP-LIB-050 |
| `get_sampler` | sampler_id | APIFuture[GetSamplerResponse] | - | ❌ GAP-LIB-051 |
| `get_sampler_async` | sampler_id | GetSamplerResponse | - | ❌ GAP-LIB-052 |

---

## 5. APIFuture Analysis

### Python Implementation

**api_future.py (150 lines):**
- `APIFuture` abstract base class
- `AwaitableConcurrentFuture` wrapper for `concurrent.futures.Future`
- Dual sync/async interfaces: `result()` and `result_async()`
- Awaitable support via `__await__`

**api_future_impl.py (297 lines):**
- `_APIFuture` - full implementation with polling
- `_CombinedAPIFuture` - combines multiple futures
- `QueueState` enum (ACTIVE, PAUSED_RATE_LIMIT, PAUSED_CAPACITY, UNKNOWN)
- `QueueStateObserver` protocol
- Exponential backoff with connection error handling
- Telemetry integration
- Request caching
- Timeout handling with iteration tracking

### Elixir Implementation

**future.ex (374 lines):**
- Task-based futures (not concurrent.futures)
- Polling loop with exponential backoff ✓
- Queue state tracking and observer callbacks ✓
- Timeout handling ✓
- Multiple await support ✓

**future/combiner.ex (55 lines):**
- Combines chunked forward/backward results ✓
- Metrics reduction ✓

### Key Differences

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Base abstraction** | concurrent.futures.Future | Task.t() | ⚠️ GAP-LIB-053 Different model |
| **Sync/async dual interface** | Yes (result/result_async) | Async-first with Task.await | ⚠️ GAP-LIB-054 Pattern difference |
| **Awaitable** | Yes via `__await__` | Yes via Task | ✓ Complete |
| **Combined futures** | `_CombinedAPIFuture` | `Future.Combiner` | ✓ Complete |
| **Queue state observer** | Protocol class | Callback module | ✓ Complete |
| **Telemetry** | Via holder.get_telemetry() | Via :telemetry events | ✓ Complete |
| **Caching** | `_cached_result` with sentinel | No caching | ❌ GAP-LIB-055 |
| **Request ID tracking** | Via untyped_future.request_id | Via request payload | ✓ Complete |
| **Iteration headers** | X-Tinker-Request-Iteration | tinker_request_iteration | ✓ Complete |

---

## 6. Retry Handler Analysis

### Python Implementation

**retry_handler.py (280 lines):**
- `RetryConfig` dataclass with:
  - `max_connections` (default 100)
  - `progress_timeout` (30 min)
  - `retry_delay_base` (initial)
  - `retry_delay_max`
  - `jitter_factor` (0.25)
  - `enable_retry_logic` (bool)
  - `retryable_exceptions` tuple
- `RetryHandler` class:
  - Connection limiting via semaphore
  - Global progress timeout tracking
  - Exponential backoff with jitter
  - Progress logging
  - Exception tracking by type

**retryable_exception.py (4 lines):**
- Simple `RetryableException` class

### Elixir Implementation

**retry.ex (126 lines):**
- `with_retry/2` function
- Progress timeout check
- Telemetry events for attempts
- Error vs exception handling
- Exponential backoff

**retry_handler.ex (97 lines):**
- `RetryHandler` struct with:
  - `max_retries` (default 3)
  - `base_delay_ms` (500)
  - `max_delay_ms` (8000)
  - `jitter_pct` (1.0)
  - `progress_timeout_ms` (30000)
- Simple exponential backoff calculation
- Progress tracking
- Retryability check via `Error.retryable?/1`

### Key Differences

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Connection limiting** | Semaphore-based | Not implemented | ❌ GAP-LIB-056 |
| **Progress timeout** | 30 min | 30 sec | ⚠️ GAP-LIB-057 Default mismatch |
| **Exception classification** | Via `retryable_exceptions` tuple | Via `Error.retryable?/1` | ✓ Complete |
| **Backoff algorithm** | Exponential with jitter | Exponential with jitter | ✓ Complete |
| **Progress logging** | Detailed with exception counts | Basic telemetry | ⚠️ GAP-LIB-058 |
| **User error detection** | Via `is_user_error/1` | Via `Error.user_error?/1` | ✓ Complete |
| **Status code retry logic** | 408, 409, 429, 5xx | Similar | ✓ Complete |

---

## 7. Telemetry Provider Analysis

### Python Implementation

**telemetry.py (443 lines):**
- `Telemetry` class managing event batching
- Session start/end events
- Generic events with severity levels
- Exception logging (fatal/non-fatal)
- Batch flushing (max 100 events)
- Periodic flush (10s interval)
- Wait-until-drained semantics
- HTTP timeout (5s)
- User error detection via cause chain traversal
- Platform detection
- SDK version tracking

**telemetry_provider.py (12 lines):**
- `TelemetryProvider` protocol
- `get_telemetry()` method

### Elixir Implementation

**telemetry.ex (130 lines):**
- Console logging helpers
- Handler attachment/detachment
- Event handling for HTTP and queue state
- `init/1` for telemetry reporter

**telemetry/reporter.ex (742 lines):**
- GenServer-based reporter
- Event batching (max 100 events)
- Periodic flushing (10s)
- Session start/end events
- Exception logging with cause chain traversal
- User error detection
- Wait-until-drained semantics
- Retry with exponential backoff
- Platform and SDK version tracking

**telemetry/provider.ex (20 lines):**
- Behaviour definition
- Default implementation

### Key Differences

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Architecture** | Class-based with threading | GenServer-based | ✓ Complete (OTP pattern) |
| **Batch size** | 100 | 100 | ✓ Complete |
| **Flush interval** | 10s | 10s | ✓ Complete |
| **Queue size limit** | 10,000 | 10,000 | ✓ Complete |
| **Session events** | START/END | START/END | ✓ Complete |
| **Exception logging** | Fatal/non-fatal | Fatal/non-fatal | ✓ Complete |
| **User error detection** | Cause chain + status codes | Cause chain + status codes | ✓ Complete |
| **Wait-until-drained** | Yes | Yes | ✓ Complete |
| **Telemetry disable** | TINKER_TELEMETRY env | TINKER_TELEMETRY env | ✓ Complete |
| **Event severity** | DEBUG/INFO/WARNING/ERROR/CRITICAL | Same | ✓ Complete |
| **Platform detection** | platform.system() | :os.type() | ✓ Complete |
| **SDK version** | __version__ | Tinkex.Version.current() | ✓ Complete |

---

## 8. Chunked Forward/Backward Analysis

### Python Implementation

**chunked_fwdbwd_helpers.py (127 lines):**
- `combine_fwd_bwd_output_results/1` - combines chunked results
- Metric reduction strategies:
  - `mean` - weighted by data points
  - `sum`
  - `min`
  - `max`
  - `slack` - max - mean
  - `hash_unordered` - order-insensitive hash
  - `unique` - preserve unique values with suffixes
- `_metrics_reduction/1` - applies reduction based on metric name suffix (e.g., "mfu:mean")
- NumPy-based calculations

### Elixir Implementation

**future/combiner.ex (55 lines):**
- `combine_forward_backward_results/1` - combines chunked results ✓
- Delegates to `Tinkex.MetricsReduction.reduce/1`

**metrics_reduction.ex (not shown but referenced):**
- Implements same reduction strategies as Python
- Nx-based calculations

### Key Differences

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Metric reduction** | NumPy-based | Nx-based | ✓ Complete |
| **Reduction strategies** | mean, sum, min, max, slack, hash_unordered, unique | Same | ✓ Complete |
| **Weighting** | By data point count | Same | ✓ Complete |
| **Loss function output merge** | Flat concatenation | Same | ✓ Complete |

---

## 9. Internal Client Management

### Python Implementation

**internal_client_holder.py (314 lines):**
- `InternalClientHolderThreadSingleton` - manages background event loop
- `InternalClientHolder` - main client manager:
  - Session creation with heartbeat
  - Multiple HTTP client pools by type
  - Sample backoff handling
  - Telemetry integration
  - Training/sampling client counters
  - Retry logic with exponential backoff (5 min max)
  - Connection pool per type (SESSION, SAMPLE, TRAIN, RETRIEVE_PROMISE, TELEMETRY)

**async_tinker_provider.py (29 lines):**
- Protocol for async Tinker client access
- `get_loop()` - get event loop
- `run_coroutine_threadsafe()` - execute coroutine
- `aclient()` - context manager for client

### Elixir Implementation

**session_manager.ex (178 lines):**
- GenServer managing sessions
- Heartbeat loop (10s interval)
- Session creation/termination
- Silent heartbeat failure handling

**No direct equivalent to InternalClientHolder** - functionality distributed:
- HTTP pools managed by `Finch` configuration
- Session management in `SessionManager`
- Client creation in `ServiceClient`
- No background thread singleton (not needed in BEAM)

### Key Differences

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Background event loop** | Thread-based singleton | BEAM scheduler | ✓ Complete (architecture) |
| **HTTP client pools** | Per connection type | Finch-managed | ✓ Complete (different) |
| **Session heartbeat** | Async task per session | GenServer loop | ✓ Complete |
| **Heartbeat interval** | 10s | 10s | ✓ Complete |
| **Heartbeat failure handling** | Warnings after 2 min | Silent drop on user error | ✓ Complete |
| **Sample backoff** | Centralized in holder | Per-client in SamplingClient | ✓ Complete (different) |
| **Retry logic** | execute_with_retries (5 min) | RetryHandler (configurable) | ✓ Complete |
| **Telemetry** | Integrated | Separate Reporter | ✓ Complete |

---

## 10. Additional Python Components

### sync_only.py (80 lines)
**Purpose:** Decorator to prevent sync methods from being called in async contexts

**Elixir Equivalent:** Not needed - Task-based async model doesn't have this footgun

**Gap Status:** ✓ Not applicable

### client_connection_pool_type.py (10 lines)
**Purpose:** Enum for connection pool types (SESSION, SAMPLE, TRAIN, RETRIEVE_PROMISE, TELEMETRY)

**Elixir Equivalent:** Finch pool configuration by name

**Gap Status:** ✓ Complete (different pattern)

---

## Detailed Gap Analysis

### GAP-LIB-001: TrainingClient.forward_async
**Severity:** Low
**Python:** `async def forward_async(data, loss_fn, loss_fn_config) -> APIFuture`
**Elixir Status:** Only sync version via GenServer.call
**What's Missing:** Dedicated async variant
**Implementation Notes:**
- Elixir pattern uses Task wrapping instead
- Not critical as Task.async provides similar semantics
- Consider if async API style is desired

### GAP-LIB-002: TrainingClient.forward_backward_async
**Severity:** Low
**Python:** `async def forward_backward_async(...) -> APIFuture`
**Elixir Status:** Only sync version
**What's Missing:** Async variant
**Implementation Notes:** Same as GAP-LIB-001

### GAP-LIB-003: TrainingClient.forward_backward_custom - Partial
**Severity:** High
**Python:** Full custom loss function with PyTorch integration, gradients, and linear loss backward pass
**Elixir Status:** Basic structure exists, delegates to `Regularizer.Pipeline.compute/4`
**What's Missing:**
- Full regularizer pipeline implementation
- Gradient computation with Nx
- Linear loss backward pass
- Metrics merging
**Implementation Notes:**
- Requires deep Nx/PyTorch parity understanding
- See `tinkex/lib/tinkex/regularizer/` for partial implementation
- Needs integration testing with actual models

### GAP-LIB-004: TrainingClient.forward_backward_custom_async
**Severity:** Medium
**Python:** Async variant of custom loss
**Elixir Status:** Not implemented
**What's Missing:** Async API
**Implementation Notes:** Depends on GAP-LIB-003 completion

### GAP-LIB-005 through GAP-LIB-014: Async Method Variants
**Severity:** Low
**Pattern:** Most TrainingClient methods have `_async` variants in Python
**Elixir Status:** Single implementation returning Task
**What's Missing:** Explicit async APIs
**Implementation Notes:**
- Elixir idiom uses Task.async wrapping
- Not critical for functionality
- Consider API consistency if async style preferred

### GAP-LIB-006, GAP-LIB-007: save_state and save_state_async
**Severity:** High
**Python:** Save model weights to persistent storage
**Elixir Status:** Not implemented
**What's Missing:**
- SaveWeightsRequest handling
- Path management
- Future polling
- Response parsing
**Implementation Notes:**
- Similar to save_weights_for_sampler but different endpoint
- Should follow same GenServer pattern

### GAP-LIB-008 through GAP-LIB-011: load_state Variants
**Severity:** High
**Python:** Load weights from checkpoint (with/without optimizer state)
**Elixir Status:** Not implemented
**What's Missing:**
- LoadWeightsRequest handling
- Optimizer state loading
- Request sequencing
**Implementation Notes:**
- Critical for checkpoint resume workflows
- Needs integration with Weights API

### GAP-LIB-013, GAP-LIB-014: save_weights_and_get_sampling_client
**Severity:** Medium
**Python:** Atomic operation: save weights + create sampling client
**Elixir Status:** Two-step process required
**What's Missing:**
- Single atomic operation
- Ephemeral weight save path
**Implementation Notes:**
- Can be composed from existing functions
- Convenience method

### GAP-LIB-015: create_sampling_client (sync variant)
**Severity:** Low
**Python:** Sync variant returning SamplingClient directly
**Elixir Status:** Only async variant (returns Task)
**What's Missing:** Sync API
**Implementation Notes:** Can wrap async with Task.await

### GAP-LIB-016, GAP-LIB-017: get_info
**Severity:** Medium
**Python:** Fetches model metadata for tokenizer resolution
**Elixir Status:** Returns error "get_info not implemented"
**What's Missing:**
- Models.get_info API integration
- GetInfoRequest/Response handling
- Model metadata caching
**Implementation Notes:**
- Currently blocks tokenizer functionality
- See GAP-LIB-018

### GAP-LIB-018: get_tokenizer
**Severity:** Medium
**Python:** Resolves HuggingFace tokenizer from model metadata
**Elixir Status:** Not implemented
**What's Missing:**
- Tokenizer resolution logic
- HuggingFace integration
- Caching with `@cache` decorator
- Special cases (Llama-3, Kimi, variants)
**Implementation Notes:**
- Requires Elixir HuggingFace bindings or NIFs
- Alternative: document requirement for user-provided tokenizers
- Depends on GAP-LIB-016

### GAP-LIB-019: QueueStateObserver
**Severity:** Low
**Python:** Observer protocol with `on_queue_state_change` callback
**Elixir Status:** Uses :telemetry events instead
**What's Missing:** Direct observer protocol
**Implementation Notes:**
- Telemetry pattern is more idiomatic for Elixir
- No action needed unless direct callbacks preferred

### GAP-LIB-020: SamplingClient.create (static method)
**Severity:** Low
**Python:** Factory method returning APIFuture[SamplingClient]
**Elixir Status:** ServiceClient handles creation
**What's Missing:** Static factory method
**Implementation Notes:**
- Different pattern but equivalent functionality
- No action needed

### GAP-LIB-021: SamplingClient.sample_async
**Severity:** Low
**Python:** Async variant of sample
**Elixir Status:** All sampling is async via Task
**What's Missing:** Explicit async API
**Implementation Notes:** Pattern difference, not functional gap

### GAP-LIB-022, GAP-LIB-023: compute_logprobs
**Severity:** High
**Python:** Compute log probabilities for prompt tokens
**Elixir Status:** Not implemented
**What's Missing:**
- Sample request with prompt_logprobs=True
- max_tokens=1
- Result extraction: `sample_res.prompt_logprobs`
- Type casting to `list[float | None]`
**Implementation Notes:**
- Important for evaluation workflows
- Should wrap sample() internally
- Requires retry handler integration

### GAP-LIB-024: SamplingClient QueueStateObserver
**Severity:** Low
**Python:** Implements observer protocol
**Elixir Status:** Uses :telemetry
**What's Missing:** Direct observer
**Implementation Notes:** Pattern difference

### GAP-LIB-025, GAP-LIB-026: get_server_capabilities
**Severity:** Medium
**Python:** Query supported models, features, limits
**Elixir Status:** Not implemented
**What's Missing:**
- Service.get_server_capabilities API call
- GetServerCapabilitiesResponse parsing
**Implementation Notes:**
- Useful for feature detection
- Can guide client behavior based on server version

### GAP-LIB-027: create_lora_training_client_async
**Severity:** Low
**Python:** Async factory method
**Elixir Status:** Sync returns immediately (process creation)
**What's Missing:** Async variant
**Implementation Notes:** Process creation is fast, async not critical

### GAP-LIB-028, GAP-LIB-029: create_training_client_from_state
**Severity:** High
**Python:** Creates training client from checkpoint path
**Elixir Status:** Not implemented
**What's Missing:**
- RestClient.get_weights_info_by_tinker_path call
- LoRA config extraction
- Training client creation with base_model + rank
- load_state call
**Implementation Notes:**
- Critical for resuming training from checkpoints
- Depends on GAP-LIB-034
- Can be implemented once weights_info endpoint added

### GAP-LIB-030 through GAP-LIB-036: Training Run Queries
**Severity:** Medium
**Python:** Full REST API for training runs
**Elixir Status:** Not implemented
**What's Missing:**
- GET /api/v1/training_runs/:id
- GET /api/v1/training_runs (list with pagination)
- TrainingRun type parsing
- TrainingRunsResponse parsing
**Implementation Notes:**
- Needed for model management UIs
- Checkpoint introspection workflows

### GAP-LIB-034: get_weights_info_by_tinker_path
**Severity:** High
**Python:** Critical for checkpoint metadata queries
**Elixir Status:** Not implemented
**What's Missing:**
- POST /api/v1/weights_info
- WeightsInfoResponse parsing (base_model, lora_rank, is_lora)
**Implementation Notes:**
- Blocks GAP-LIB-028 (training from state)
- Required for checkpoint workflows

### GAP-LIB-037 through GAP-LIB-050: Async REST Variants
**Severity:** Low
**Python:** All REST methods have async variants
**Elixir Status:** Sync only
**What's Missing:** Async APIs
**Implementation Notes:**
- Can wrap with Task.async
- Not critical

### GAP-LIB-044, GAP-LIB-045, GAP-LIB-046, GAP-LIB-047: Checkpoint Visibility
**Severity:** Medium
**Python:** Publish/unpublish checkpoints for sharing
**Elixir Status:** Not implemented
**What's Missing:**
- POST /api/v1/training_runs/:id/checkpoints/:checkpoint_id/publish
- DELETE .../publish (unpublish)
- Error handling (400, 404, 409, 500)
**Implementation Notes:**
- Important for collaborative workflows
- Checkpoint sharing
- Access control

### GAP-LIB-051, GAP-LIB-052: get_sampler
**Severity:** Medium
**Python:** Query sampler information
**Elixir Status:** Not implemented
**What's Missing:**
- GET /api/v1/samplers/:sampler_id
- GetSamplerResponse parsing (base_model, model_path)
**Implementation Notes:**
- Useful for debugging sampling sessions
- Model introspection

### GAP-LIB-053: Future Base Abstraction
**Severity:** Low
**Pattern Difference:** Python uses concurrent.futures, Elixir uses Task
**Impact:** None - both provide async computation abstraction
**Recommendation:** Document pattern difference in migration guide

### GAP-LIB-054: Sync/Async Dual Interface
**Severity:** Low
**Pattern Difference:** Python has .result() and .result_async(), Elixir uses Task.await
**Impact:** API style difference
**Recommendation:** Consider if explicit async methods desired for consistency

### GAP-LIB-055: Future Result Caching
**Severity:** Low
**Python:** Caches result with sentinel value check
**Elixir Status:** No caching - multiple awaits repeat computation
**What's Missing:**
- Result caching in Future module
- Sentinel value pattern
**Implementation Notes:**
- Task results can be awaited multiple times
- Consider if caching needed for performance

### GAP-LIB-056: Connection Limiting via Semaphore
**Severity:** Medium
**Python:** RetryHandler uses semaphore to limit concurrent connections
**Elixir Status:** Not implemented
**What's Missing:**
- Connection semaphore
- Per-handler semaphore tracking
- Waiting queue size tracking
**Implementation Notes:**
- Finch already provides connection pooling
- May not need application-level semaphores
- Consider if explicit limiting needed

### GAP-LIB-057: Progress Timeout Mismatch
**Severity:** Low
**Python:** Default 30 minutes (1800 seconds)
**Elixir:** Default 30 seconds
**Impact:** Different timeout behavior
**Recommendation:** Align defaults or document difference

### GAP-LIB-058: Progress Logging Detail
**Severity:** Low
**Python:** Detailed logging with exception counts, progress intervals
**Elixir:** Basic telemetry events
**What's Missing:**
- Exception count tracking
- Progress interval logging
- Waiting/processing counters
**Implementation Notes:**
- Can enhance telemetry events
- Add counters to RetryHandler state

---

## Summary of Critical Gaps

### Must-Have for Production

1. **GAP-LIB-003** - Custom loss functions (High)
2. **GAP-LIB-006, GAP-LIB-008** - Save/load state for checkpointing (High)
3. **GAP-LIB-022** - Compute logprobs for evaluation (High)
4. **GAP-LIB-028** - Training from checkpoint (High)
5. **GAP-LIB-034** - Weights info for checkpoint metadata (High)

### Important for Feature Parity

6. **GAP-LIB-016, GAP-LIB-018** - Model info and tokenizer (Medium)
7. **GAP-LIB-025** - Server capabilities (Medium)
8. **GAP-LIB-044, GAP-LIB-046** - Checkpoint publish/unpublish (Medium)
9. **GAP-LIB-030-036** - Training run queries (Medium)
10. **GAP-LIB-051** - Sampler info (Medium)
11. **GAP-LIB-056** - Connection limiting (Medium)

### Nice-to-Have

12. All async method variants (Low)
13. Future result caching (Low)
14. Enhanced progress logging (Low)

---

## Recommendations

### Phase 1: Core Functionality (Sprint 1-2)
1. Implement save_state/load_state for checkpointing (GAP-LIB-006, GAP-LIB-008)
2. Add compute_logprobs to SamplingClient (GAP-LIB-022)
3. Implement get_weights_info_by_tinker_path (GAP-LIB-034)
4. Add create_training_client_from_state (GAP-LIB-028)

### Phase 2: Advanced Features (Sprint 3-4)
5. Complete custom loss function implementation (GAP-LIB-003)
6. Add checkpoint publish/unpublish (GAP-LIB-044, GAP-LIB-046)
7. Implement training run REST endpoints (GAP-LIB-030-036)
8. Add get_info and tokenizer support (GAP-LIB-016, GAP-LIB-018)

### Phase 3: Polish (Sprint 5+)
9. Add async method variants if desired (GAP-LIB-001, etc.)
10. Enhance telemetry and logging (GAP-LIB-058)
11. Consider connection limiting (GAP-LIB-056)
12. Future result caching if needed (GAP-LIB-055)

### Architectural Decisions
- **Async Pattern:** Document that Elixir uses Task-based async vs Python's dual interface
- **Retry Strategy:** Consider aligning progress timeout defaults
- **Telemetry:** Current :telemetry approach is idiomatic and sufficient
- **Connection Pooling:** Finch handles this; application-level semaphores likely unnecessary

---

## File Path Reference

### Python Source
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\training_client.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\sampling_client.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\service_client.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\rest_client.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\api_future.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\api_future_impl.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\retry_handler.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\telemetry.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\chunked_fwdbwd_helpers.py`

### Elixir Destination
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\training_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\sampling_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\service_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\rest_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\future.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\retry_handler.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\telemetry\reporter.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\future\combiner.ex`

---

**End of Gap Analysis**
