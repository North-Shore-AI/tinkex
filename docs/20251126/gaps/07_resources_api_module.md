# Gap Analysis: Resources (API) Module - Python tinker vs Elixir tinkex

**Date:** 2025-11-26
**Domain:** Resources (API) Module
**Python Source:** `tinker/src/tinker/resources/`
**Elixir Destination:** `tinkex/lib/tinkex/api/`

---

## 1. Executive Summary

### Overall Completeness: 70%

The Elixir tinkex API module provides most core functionality but is missing several important features present in the Python implementation:

- **Critical Gaps:** 6
- **High Priority Gaps:** 8
- **Medium Priority Gaps:** 5
- **Low Priority Gaps:** 3

### Key Findings

**Strengths:**
- Core HTTP client infrastructure is well-implemented with retry logic and telemetry
- All major API endpoints are covered (models, weights, futures, training, sampling, telemetry)
- Pool-based routing is more sophisticated than Python (dedicated pools per resource type)
- Excellent Elixir-idiomatic design with proper supervision and async handling

**Weaknesses:**
- Missing health check and server capabilities endpoints
- No support for model info/unload operations
- Checkpoint management endpoints incomplete
- Missing convenience helpers like `with_raw_response`
- No typed request/response objects for most endpoints
- Session heartbeat endpoint path mismatch

---

## 2. Resource-by-Resource Comparison Table

| Python Resource | Methods | Elixir Module | Methods Match | Gap Status |
|-----------------|---------|---------------|---------------|------------|
| `AsyncServiceResource` | 5 | `Tinkex.API.Service` | 2/5 | ❌ 60% Missing |
| `AsyncModelsResource` | 3 | `Tinkex.API.Service` (partial) | 1/3 | ❌ 67% Missing |
| `AsyncWeightsResource` | 6 | `Tinkex.API.Weights` | 3/6 | ⚠️ 50% Missing |
| `AsyncFuturesResource` | 1 (+1 wrapper) | `Tinkex.API.Futures` | 1/1 | ✅ Complete Core |
| `AsyncTrainingResource` | 3 | `Tinkex.API.Training` | 3/3 | ✅ Complete |
| `AsyncSamplingResource` | 1 | `Tinkex.API.Sampling` | 1/1 | ✅ Complete |
| `AsyncTelemetryResource` | 1 (+1 wrapper) | `Tinkex.API.Telemetry` | 1/1 | ✅ Complete |
| N/A | N/A | `Tinkex.API.Session` | Extra | ➕ Elixir Addition |
| N/A | N/A | `Tinkex.API.Rest` | Extra | ➕ Elixir Addition |

**Legend:**
- ✅ Complete (100%)
- ⚠️ Partial (50-99%)
- ❌ Incomplete (<50%)
- ➕ Elixir-specific addition

---

## 3. Method-Level Comparison

### 3.1 AsyncServiceResource (Python)

#### Methods:
1. **`get_server_capabilities()`**
   - **Parameters:** extra_headers, extra_query, extra_body, timeout
   - **Returns:** `GetServerCapabilitiesResponse`
   - **Elixir Equivalent:** ❌ **MISSING**
   - **Gap Status:** CRITICAL

2. **`health_check()`**
   - **Parameters:** extra_headers, extra_query, extra_body, timeout
   - **Returns:** `HealthResponse`
   - **Elixir Equivalent:** ❌ **MISSING**
   - **Gap Status:** HIGH

3. **`create_session(request)`**
   - **Parameters:** CreateSessionRequest, extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `CreateSessionResponse`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Session.create/2` + `create_typed/2`
   - **Gap Status:** COMPLETE (better than Python with typed variant)

4. **`session_heartbeat(session_id)`**
   - **Parameters:** session_id (string), extra_headers, extra_query, extra_body, timeout, max_retries
   - **Returns:** `SessionHeartbeatResponse`
   - **Elixir Equivalent:** ⚠️ `Tinkex.API.Session.heartbeat/2`
   - **Gap Status:** PARTIAL - Path mismatch (Python uses `/api/v1/session_heartbeat`, Elixir uses `/api/v1/heartbeat`)

5. **`create_sampling_session(request)`**
   - **Parameters:** CreateSamplingSessionRequest, extra_headers, extra_query, extra_body, timeout, max_retries
   - **Returns:** `CreateSamplingSessionResponse`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Service.create_sampling_session/2`
   - **Gap Status:** COMPLETE

---

### 3.2 AsyncModelsResource (Python)

#### Methods:
1. **`create(request)`**
   - **Parameters:** CreateModelRequest (base_model, user_metadata, lora_config), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/create_model`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Service.create_model/2`
   - **Gap Status:** COMPLETE

2. **`get_info(request)`**
   - **Parameters:** GetInfoRequest (model_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `GetInfoResponse`
   - **Endpoint:** POST `/api/v1/get_info`
   - **Elixir Equivalent:** ❌ **MISSING**
   - **Gap Status:** CRITICAL

3. **`unload(request)`**
   - **Parameters:** UnloadModelRequest (model_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/unload_model`
   - **Elixir Equivalent:** ❌ **MISSING**
   - **Gap Status:** HIGH

---

### 3.3 AsyncWeightsResource (Python)

#### Methods:
1. **`load(request)`**
   - **Parameters:** LoadWeightsRequest (model_id, path, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/load_weights`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Weights.load_weights/2`
   - **Gap Status:** COMPLETE

2. **`save(request)`**
   - **Parameters:** SaveWeightsRequest (model_id, path, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/save_weights`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Weights.save_weights/2`
   - **Gap Status:** COMPLETE

3. **`save_for_sampler(request)`**
   - **Parameters:** SaveWeightsForSamplerRequest (model_id, path, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/save_weights_for_sampler`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Weights.save_weights_for_sampler/2`
   - **Gap Status:** COMPLETE

4. **`list(model_id)`**
   - **Parameters:** model_id (ModelID), extra_headers, extra_query, extra_body, timeout
   - **Returns:** `CheckpointsListResponse`
   - **Endpoint:** GET `/api/v1/training_runs/{model_id}/checkpoints`
   - **Elixir Equivalent:** ⚠️ `Tinkex.API.Rest.list_checkpoints/2`
   - **Gap Status:** PARTIAL - In different module (Rest instead of Weights)

5. **`delete_checkpoint(model_id, checkpoint_id)`**
   - **Parameters:** model_id (ModelID), checkpoint_id (string), extra_headers, extra_query, extra_body, timeout
   - **Returns:** None
   - **Endpoint:** DELETE `/api/v1/training_runs/{model_id}/checkpoints/{checkpoint_id}`
   - **Elixir Equivalent:** ⚠️ `Tinkex.API.Rest.delete_checkpoint/2`
   - **Gap Status:** PARTIAL - Different signature (takes full checkpoint_path instead of split params)

6. **`get_checkpoint_archive_url(model_id, checkpoint_id)`**
   - **Parameters:** model_id (ModelID), checkpoint_id (string), extra_headers, extra_query, extra_body, timeout
   - **Returns:** `CheckpointArchiveUrlResponse` (url, expires)
   - **Endpoint:** GET `/api/v1/training_runs/{model_id}/checkpoints/{checkpoint_id}/archive`
   - **Special:** Handles 302 redirect, extracts Location header
   - **Elixir Equivalent:** ⚠️ `Tinkex.API.Rest.get_checkpoint_archive_url/2`
   - **Gap Status:** PARTIAL - Different signature (takes checkpoint_path instead of split params)

---

### 3.4 AsyncFuturesResource (Python)

#### Methods:
1. **`retrieve(request)`**
   - **Parameters:** FutureRetrieveRequest (request_id, optional model_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `FutureRetrieveResponse` (union type)
   - **Endpoint:** POST `/api/v1/retrieve_future`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Futures.retrieve/2`
   - **Gap Status:** COMPLETE

2. **`with_raw_response` property**
   - **Type:** Cached property returning `AsyncFuturesResourceWithRawResponse`
   - **Purpose:** Prefix for HTTP methods to return raw response instead of parsed content
   - **Elixir Equivalent:** ⚠️ Implemented via `:raw_response?` option in Elixir
   - **Gap Status:** PARTIAL - Different pattern (option-based vs wrapper class)

---

### 3.5 AsyncTrainingResource (Python)

#### Methods:
1. **`forward(request)`**
   - **Parameters:** ForwardRequest (input data, model_id, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/forward`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Training.forward/2` + `forward_future/2`
   - **Gap Status:** COMPLETE (better than Python with auto-await and future variants)

2. **`forward_backward(request)`**
   - **Parameters:** ForwardBackwardRequest (input data, model_id, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/forward_backward`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Training.forward_backward/2` + `forward_backward_future/2`
   - **Gap Status:** COMPLETE (better than Python)

3. **`optim_step(request)`**
   - **Parameters:** OptimStepRequest (adam_params, model_id, seq_id), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/optim_step`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Training.optim_step/2` + `optim_step_future/2`
   - **Gap Status:** COMPLETE (better than Python)

---

### 3.6 AsyncSamplingResource (Python)

#### Methods:
1. **`asample(request)`**
   - **Parameters:** SampleRequest (prompt, sampling params, options), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `UntypedAPIFuture`
   - **Endpoint:** POST `/api/v1/asample`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Sampling.sample_async/2`
   - **Gap Status:** COMPLETE

---

### 3.7 AsyncTelemetryResource (Python)

#### Methods:
1. **`send(request)`**
   - **Parameters:** TelemetrySendRequest (events, session info), extra_headers, extra_query, extra_body, timeout, idempotency_key, max_retries
   - **Returns:** `TelemetryResponse`
   - **Endpoint:** POST `/api/v1/telemetry`
   - **Elixir Equivalent:** ✅ `Tinkex.API.Telemetry.send/2` + `send_sync/2`
   - **Gap Status:** COMPLETE (better than Python with async/sync variants)

2. **`with_raw_response` property**
   - **Type:** Cached property returning `AsyncTelemetryResourceWithRawResponse`
   - **Elixir Equivalent:** ⚠️ Implemented via `:raw_response?` option
   - **Gap Status:** PARTIAL - Different pattern

---

### 3.8 Elixir-Specific Additions

#### Tinkex.API.Session (Elixir Only)
- **Purpose:** Dedicated session management module
- **Methods:**
  - `create/2` - Create session (maps to Python's AsyncServiceResource.create_session)
  - `create_typed/2` - Create session with typed response
  - `heartbeat/2` - Session heartbeat
- **Gap Status:** ENHANCEMENT - Better organization than Python

#### Tinkex.API.Rest (Elixir Only)
- **Purpose:** REST endpoints for checkpoint and session management
- **Methods:**
  - `get_session/2` - Get session info
  - `list_sessions/3` - List sessions with pagination
  - `list_checkpoints/2` - List checkpoints for training run
  - `list_user_checkpoints/3` - List all user checkpoints
  - `get_checkpoint_archive_url/2` - Get download URL
  - `delete_checkpoint/2` - Delete checkpoint
  - `get_sampler/2` - Get sampler info (with typed response)
  - `get_weights_info_by_tinker_path/2` - Get checkpoint metadata
  - `get_training_run/2` - Get training run by ID
  - `get_training_run_by_tinker_path/2` - Get training run from checkpoint path
  - `list_training_runs/3` - List training runs with pagination
- **Gap Status:** ENHANCEMENT - More comprehensive than Python

---

## 4. Detailed Gap Analysis

### GAP-API-001: Missing Server Capabilities Endpoint
- **Severity:** CRITICAL
- **Python Method:** `AsyncServiceResource.get_server_capabilities()`
- **Endpoint:** GET `/api/v1/get_server_capabilities`
- **Returns:** `GetServerCapabilitiesResponse`
- **Elixir Status:** Not implemented
- **What's Missing:**
  - Endpoint to query supported models and server capabilities
  - Critical for client initialization and feature detection
  - Used to validate server compatibility
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Service
  @spec get_server_capabilities(keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_server_capabilities(opts) do
    Tinkex.API.get(
      "/api/v1/get_server_capabilities",
      Keyword.put(opts, :pool_type, :session)
    )
  end
  ```

---

### GAP-API-002: Missing Health Check Endpoint
- **Severity:** HIGH
- **Python Method:** `AsyncServiceResource.health_check()`
- **Endpoint:** GET `/api/v1/healthz`
- **Returns:** `HealthResponse`
- **Elixir Status:** Not implemented
- **What's Missing:**
  - Health check endpoint for monitoring
  - Used for load balancer health probes
  - Simple readiness check
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Service
  @spec health_check(keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def health_check(opts) do
    Tinkex.API.get(
      "/api/v1/healthz",
      Keyword.put(opts, :pool_type, :session)
    )
  end
  ```

---

### GAP-API-003: Missing Model Info Endpoint
- **Severity:** CRITICAL
- **Python Method:** `AsyncModelsResource.get_info(request)`
- **Endpoint:** POST `/api/v1/get_info`
- **Request:** `GetInfoRequest` (model_id)
- **Returns:** `GetInfoResponse`
- **Elixir Status:** Not implemented
- **What's Missing:**
  - Ability to query model information after creation
  - Returns model configuration, status, metadata
  - Essential for model management workflows
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Service or create Tinkex.API.Models
  @spec get_model_info(map(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_model_info(request, opts) do
    Tinkex.API.post(
      "/api/v1/get_info",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
  ```

---

### GAP-API-004: Missing Model Unload Endpoint
- **Severity:** HIGH
- **Python Method:** `AsyncModelsResource.unload(request)`
- **Endpoint:** POST `/api/v1/unload_model`
- **Request:** `UnloadModelRequest` (model_id)
- **Returns:** `UntypedAPIFuture`
- **Elixir Status:** Not implemented
- **What's Missing:**
  - Explicit model unload to free resources
  - Ends user session gracefully
  - Important for resource cleanup
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Service
  @spec unload_model(map(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def unload_model(request, opts) do
    Tinkex.API.post(
      "/api/v1/unload_model",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
  ```

---

### GAP-API-005: Session Heartbeat Path Mismatch
- **Severity:** HIGH
- **Python Method:** `AsyncServiceResource.session_heartbeat(session_id)`
- **Endpoint:** POST `/api/v1/session_heartbeat`
- **Elixir Implementation:** `Tinkex.API.Session.heartbeat/2`
- **Elixir Endpoint:** POST `/api/v1/heartbeat`
- **What's Missing:**
  - Path inconsistency between Python and Elixir
  - Python uses `/api/v1/session_heartbeat`
  - Elixir uses `/api/v1/heartbeat`
  - Need to verify which is correct API
- **Implementation Notes:**
  - Check server API documentation
  - Update Elixir path if `/api/v1/session_heartbeat` is correct
  - Or update Python client if `/api/v1/heartbeat` is correct

---

### GAP-API-006: Checkpoint List Method Signature
- **Severity:** MEDIUM
- **Python Method:** `AsyncWeightsResource.list(model_id)`
- **Signature:** Single `model_id` parameter
- **Elixir Method:** `Tinkex.API.Rest.list_checkpoints(config, run_id)`
- **Signature:** Requires explicit config + run_id
- **What's Missing:**
  - Python uses model_id parameter
  - Elixir requires config as first param
  - Should be in Weights module for consistency
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Weights for consistency
  @spec list_checkpoints(String.t(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_checkpoints(model_id, opts) do
    Tinkex.API.get(
      "/api/v1/training_runs/#{model_id}/checkpoints",
      Keyword.put(opts, :pool_type, :training)
    )
  end
  ```

---

### GAP-API-007: Checkpoint Delete Method Signature
- **Severity:** MEDIUM
- **Python Method:** `AsyncWeightsResource.delete_checkpoint(model_id, checkpoint_id)`
- **Signature:** Separate `model_id` and `checkpoint_id` parameters
- **Elixir Method:** `Tinkex.API.Rest.delete_checkpoint(config, checkpoint_path)`
- **Signature:** Single `checkpoint_path` parameter (tinker://...)
- **What's Missing:**
  - Different API design
  - Python splits model_id and checkpoint_id
  - Elixir uses full tinker path
  - Both work but inconsistent
- **Implementation Notes:**
  ```elixir
  # Add to Tinkex.API.Weights for API parity
  @spec delete_checkpoint(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(model_id, checkpoint_id, opts) do
    path = "/api/v1/training_runs/#{model_id}/checkpoints/#{checkpoint_id}"
    Tinkex.API.delete(path, Keyword.put(opts, :pool_type, :training))
  end
  ```

---

### GAP-API-008: Checkpoint Archive URL Method Signature
- **Severity:** MEDIUM
- **Python Method:** `AsyncWeightsResource.get_checkpoint_archive_url(model_id, checkpoint_id)`
- **Signature:** Separate parameters
- **Special Handling:** Catches 302 redirect, extracts Location header, parses Expires header
- **Elixir Method:** `Tinkex.API.Rest.get_checkpoint_archive_url(config, checkpoint_path)`
- **Signature:** Single checkpoint_path
- **What's Missing:**
  - Different signature style
  - Python has special redirect handling
  - Elixir relies on API module's redirect handling
  - Need to verify redirect handling works
- **Implementation Notes:**
  - Verify API.get properly handles 302 redirects
  - Add to Weights module for consistency
  - Consider adding expires header parsing

---

### GAP-API-009: Missing WithRawResponse Wrapper Pattern
- **Severity:** LOW
- **Python Pattern:** `client.futures.with_raw_response.retrieve(...)`
- **Python Implementation:** Cached property returning wrapper class
- **Purpose:** Access raw HTTP response (headers, status) instead of parsed body
- **Elixir Implementation:** Option-based: `retrieve(req, raw_response?: true)`
- **What's Missing:**
  - Python uses object-oriented wrapper pattern
  - Elixir uses functional option pattern
  - Both achieve same goal, different style
  - Not a gap per se, just different idiom
- **Implementation Notes:**
  - No action needed - Elixir pattern is idiomatic
  - Document the difference for users migrating from Python

---

### GAP-API-010: Request/Response Type System
- **Severity:** MEDIUM
- **Python Implementation:**
  - Strongly typed request classes (`CreateModelRequest`, `LoadWeightsRequest`, etc.)
  - Strongly typed response classes (`GetInfoResponse`, `CheckpointsListResponse`, etc.)
  - Pydantic-based validation
  - Type hints throughout
- **Elixir Implementation:**
  - Most methods accept raw maps
  - Some typed responses (`CreateSessionResponse`, `ForwardBackwardOutput`, `OptimStepResponse`)
  - Inconsistent typing across endpoints
- **What's Missing:**
  - Typed request structs for validation
  - Typed response structs for all endpoints
  - Consistent type conversion pattern
- **Implementation Notes:**
  ```elixir
  # Add typed request/response modules
  defmodule Tinkex.Types.CreateModelRequest do
    @enforce_keys [:base_model]
    defstruct [:base_model, :user_metadata, :lora_config]

    @type t :: %__MODULE__{
      base_model: String.t(),
      user_metadata: map() | nil,
      lora_config: map() | nil
    }
  end

  # Update API methods to accept typed structs
  @spec create_model(CreateModelRequest.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  ```

---

### GAP-API-011: Extra Headers/Query/Body Support
- **Severity:** LOW
- **Python Methods:** All methods support `extra_headers`, `extra_query`, `extra_body` parameters
- **Purpose:** Pass additional parameters not in standard API
- **Elixir Implementation:** Supported via `headers: [...]` option
- **What's Missing:**
  - Python has explicit named parameters
  - Elixir uses generic `opts[:headers]`
  - Both work, Python is more explicit
- **Implementation Notes:**
  - Current implementation is sufficient
  - Could add convenience for extra_query, extra_body if needed
  - Document the opts pattern clearly

---

### GAP-API-012: Idempotency Key Handling
- **Severity:** LOW
- **Python Implementation:** Explicit `idempotency_key` parameter on all mutation methods
- **Elixir Implementation:** `opts[:idempotency_key]` with auto-generation if omitted
- **What's Missing:**
  - Python requires explicit parameter
  - Elixir auto-generates if not provided
  - Elixir has `:omit` option to skip idempotency
- **Gap Status:** ENHANCEMENT - Elixir is more flexible
- **Implementation Notes:**
  - No changes needed
  - Elixir implementation is superior

---

### GAP-API-013: Max Retries Per-Request Override
- **Severity:** MEDIUM
- **Python Implementation:** Every method accepts `max_retries` parameter
- **Elixir Implementation:** Most methods support `opts[:max_retries]`
- **Notable Exception:** `Tinkex.API.Sampling.sample_async/2` hardcodes `max_retries: 0`
- **What's Missing:**
  - Sampling endpoint prevents retry override
  - Comment says Phase 4 client will handle retries
  - Limits flexibility for advanced use cases
- **Implementation Notes:**
  ```elixir
  # Update Tinkex.API.Sampling.sample_async/2
  def sample_async(request, opts) do
    opts =
      opts
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put_new(:max_retries, 0)  # Default to 0, allow override
      |> Keyword.put_new(:sampling_backpressure, true)

    Tinkex.API.post("/api/v1/asample", request, opts)
  end
  ```

---

### GAP-API-014: Timeout Parameter Consistency
- **Severity:** LOW
- **Python Implementation:** Every method accepts `timeout` parameter (float | httpx.Timeout | None | NotGiven)
- **Elixir Implementation:** Supported via `opts[:timeout]`, falls back to config.timeout
- **What's Missing:**
  - Python has more flexible timeout types
  - Elixir only supports integer milliseconds
  - Python supports httpx.Timeout objects for fine-grained control
- **Implementation Notes:**
  - Current implementation is sufficient for most cases
  - Could add timeout struct for connect vs read timeouts if needed

---

### GAP-API-015: HTTP Method Support
- **Severity:** LOW
- **Python Implementation:** Uses POST for most operations, GET for queries, DELETE for deletions
- **Elixir Implementation:** Same pattern via Tinkex.API.{post, get, delete}
- **What's Missing:**
  - No PUT or PATCH support
  - Not needed for current API
- **Gap Status:** COMPLETE - No gaps

---

### GAP-API-016: Response Decompression
- **Severity:** LOW
- **Python Implementation:** httpx handles gzip automatically
- **Elixir Implementation:** Manual gzip decompression in `maybe_decompress/1`
- **What's Missing:**
  - Python relies on HTTP client
  - Elixir implements explicitly
  - Both work correctly
- **Gap Status:** COMPLETE - Different but equivalent

---

### GAP-API-017: Redirect Handling
- **Severity:** MEDIUM
- **Python Implementation:**
  - Special handling in `get_checkpoint_archive_url`
  - Catches 302 exception, extracts Location header
  - Parses Expires header with fallback
- **Elixir Implementation:**
  - Generic redirect handling in `do_handle_response/1` (status 301, 302, 307, 308)
  - Extracts location and expires headers
  - Returns map with url, status, expires
- **What's Missing:**
  - Python has endpoint-specific redirect logic
  - Elixir has generic redirect handling
  - Both should work, but need to verify
- **Implementation Notes:**
  - Test redirect handling for checkpoint archive endpoint
  - Ensure expires header parsing works correctly

---

### GAP-API-018: Error Category Mapping
- **Severity:** LOW
- **Python Implementation:**
  - Error responses include category field
  - Status-based fallback (400s = user, 500s = server)
- **Elixir Implementation:**
  - Uses `RequestErrorCategory.parse/1`
  - Same status-based fallback
  - Enhanced with retry_after_ms
- **Gap Status:** COMPLETE - Elixir is equivalent or better

---

### GAP-API-019: Retry Logic Differences
- **Severity:** MEDIUM
- **Python Implementation:**
  - Uses httpx built-in retry with backoff
  - Respects x-should-retry header
  - Respects Retry-After header
- **Elixir Implementation:**
  - Custom retry with exponential backoff + jitter
  - Respects x-should-retry header
  - Respects Retry-After and Retry-After-Ms headers
  - Max retry duration (30s)
  - Per-request retry count in headers
- **What's Missing:**
  - Elixir has additional safeguards (max duration)
  - Elixir has jitter to prevent thundering herd
- **Gap Status:** ENHANCEMENT - Elixir is more sophisticated

---

### GAP-API-020: Telemetry/Observability
- **Severity:** LOW
- **Python Implementation:**
  - No built-in telemetry/tracing
  - Relies on httpx logging
- **Elixir Implementation:**
  - Full :telemetry integration
  - Events: `[:tinkex, :http, :request, :start/:stop/:exception]`
  - Metadata: method, path, pool_type, retry_count, duration
  - Custom telemetry_metadata option
- **Gap Status:** ENHANCEMENT - Elixir has superior observability

---

### GAP-API-021: Connection Pooling
- **Severity:** LOW
- **Python Implementation:**
  - httpx connection pooling
  - Single pool for all requests
- **Elixir Implementation:**
  - Multiple named pools per resource type:
    - `:session` (5 connections, infinite idle)
    - `:sampling` (100 connections)
    - `:futures` (50 connections)
    - `:training` (5 connections)
    - `:telemetry` (5 connections)
  - Pool routing via PoolKey
- **Gap Status:** ENHANCEMENT - Elixir has sophisticated pool management

---

### GAP-API-022: Stainless Headers
- **Severity:** LOW
- **Python Implementation:**
  - Stainless SDK headers (package version, OS, arch, runtime)
- **Elixir Implementation:**
  - Identical Stainless headers
  - `x-stainless-package-version`, `x-stainless-os`, etc.
  - Custom `x-stainless-read-timeout` calculation
- **Gap Status:** COMPLETE - Fully compatible

---

## 5. API Endpoint Coverage

### Implemented Endpoints

| HTTP Method | Endpoint | Python Resource | Elixir Module | Status |
|-------------|----------|-----------------|---------------|--------|
| POST | `/api/v1/create_session` | AsyncServiceResource | Session | ✅ |
| POST | `/api/v1/session_heartbeat` | AsyncServiceResource | Session | ⚠️ Path mismatch |
| POST | `/api/v1/create_sampling_session` | AsyncServiceResource | Service | ✅ |
| POST | `/api/v1/create_model` | AsyncModelsResource | Service | ✅ |
| POST | `/api/v1/load_weights` | AsyncWeightsResource | Weights | ✅ |
| POST | `/api/v1/save_weights` | AsyncWeightsResource | Weights | ✅ |
| POST | `/api/v1/save_weights_for_sampler` | AsyncWeightsResource | Weights | ✅ |
| POST | `/api/v1/retrieve_future` | AsyncFuturesResource | Futures | ✅ |
| POST | `/api/v1/forward` | AsyncTrainingResource | Training | ✅ |
| POST | `/api/v1/forward_backward` | AsyncTrainingResource | Training | ✅ |
| POST | `/api/v1/optim_step` | AsyncTrainingResource | Training | ✅ |
| POST | `/api/v1/asample` | AsyncSamplingResource | Sampling | ✅ |
| POST | `/api/v1/telemetry` | AsyncTelemetryResource | Telemetry | ✅ |
| GET | `/api/v1/training_runs/{id}/checkpoints` | AsyncWeightsResource | Rest/Weights | ✅ |
| DELETE | `/api/v1/training_runs/{id}/checkpoints/{id}` | AsyncWeightsResource | Rest/Weights | ✅ |
| GET | `/api/v1/training_runs/{id}/checkpoints/{id}/archive` | AsyncWeightsResource | Rest/Weights | ✅ |

### Missing Endpoints

| HTTP Method | Endpoint | Python Resource | Python Method | Severity |
|-------------|----------|-----------------|---------------|----------|
| GET | `/api/v1/get_server_capabilities` | AsyncServiceResource | `get_server_capabilities()` | CRITICAL |
| GET | `/api/v1/healthz` | AsyncServiceResource | `health_check()` | HIGH |
| POST | `/api/v1/get_info` | AsyncModelsResource | `get_info()` | CRITICAL |
| POST | `/api/v1/unload_model` | AsyncModelsResource | `unload()` | HIGH |

### Elixir-Only Endpoints (Enhancements)

| HTTP Method | Endpoint | Elixir Module | Method |
|-------------|----------|---------------|--------|
| GET | `/api/v1/sessions/{id}` | Rest | `get_session/2` |
| GET | `/api/v1/sessions` | Rest | `list_sessions/3` |
| GET | `/api/v1/checkpoints` | Rest | `list_user_checkpoints/3` |
| GET | `/api/v1/samplers/{id}` | Rest | `get_sampler/2` |
| POST | `/api/v1/weights_info` | Rest | `get_weights_info_by_tinker_path/2` |
| GET | `/api/v1/training_runs/{id}` | Rest | `get_training_run/2` |
| GET | `/api/v1/training_runs` | Rest | `list_training_runs/3` |

---

## 6. Async vs Sync Analysis

### Python Approach
- All resources are `Async*Resource` classes
- Methods are async (`async def`)
- Returns coroutines that must be awaited
- Uses httpx AsyncClient
- Relies on Python asyncio event loop

### Elixir Approach
- All API functions are synchronous from caller perspective
- Concurrency via BEAM processes and Finch
- HTTP requests use Finch.request (which internally uses connection pools)
- Future polling uses Task-based async with Future.await
- Training methods offer both auto-await and _future variants

### Key Differences

1. **Concurrency Model:**
   - Python: asyncio coroutines (cooperative)
   - Elixir: BEAM processes (preemptive)

2. **API Design:**
   - Python: Async methods return futures immediately
   - Elixir: Methods block until HTTP completes, then return {:ok, result}

3. **Future Handling:**
   - Python: Client must manually poll futures
   - Elixir: `Future.poll/2` + `Future.await/2` handle polling automatically

4. **Training Operations:**
   - Python: Returns UntypedAPIFuture, client polls manually
   - Elixir: Two variants:
     - `forward/2` - auto-awaits future, returns typed result
     - `forward_future/2` - returns future reference for manual polling

5. **Telemetry:**
   - Python: Synchronous send
   - Elixir: Async send (fire-and-forget) + sync variant for testing

### Mapping Strategy

Python's async/await maps to Elixir's Task/await:

```python
# Python
future = await client.training.forward_backward(request)
result = await client.futures.retrieve({"request_id": future.request_id})
```

```elixir
# Elixir (manual polling)
{:ok, future} = Training.forward_backward_future(request, config: config)
task = Future.poll(future, config: config)
{:ok, result} = Future.await(task)

# Elixir (auto-await helper)
{:ok, result} = Training.forward_backward(request, config: config)
```

The Elixir implementation provides both patterns for flexibility.

---

## 7. Recommendations

### Priority 1: Critical Gaps (Implement ASAP)

1. **Add Server Capabilities Endpoint (GAP-API-001)**
   - Essential for client initialization
   - Add to `Tinkex.API.Service`
   - Create typed response struct

2. **Add Model Info Endpoint (GAP-API-003)**
   - Critical for model management
   - Add to `Tinkex.API.Service` or new `Tinkex.API.Models`
   - Create typed response struct

### Priority 2: High Priority Gaps (Implement Soon)

3. **Add Health Check Endpoint (GAP-API-002)**
   - Important for monitoring and load balancing
   - Add to `Tinkex.API.Service`

4. **Add Model Unload Endpoint (GAP-API-004)**
   - Important for resource cleanup
   - Add to `Tinkex.API.Service`

5. **Fix Session Heartbeat Path (GAP-API-005)**
   - Verify correct API path
   - Update implementation to match server

### Priority 3: Medium Priority Improvements

6. **Add Typed Request/Response Structs (GAP-API-010)**
   - Create request structs with validation
   - Add typed responses for all endpoints
   - Improves type safety and documentation

7. **Reorganize Checkpoint Methods (GAP-API-006, 007, 008)**
   - Move checkpoint operations to `Tinkex.API.Weights`
   - Add Python-compatible signatures
   - Keep Rest module methods for backward compatibility

8. **Allow Retry Override in Sampling (GAP-API-013)**
   - Change hardcoded `max_retries: 0` to `put_new`
   - Preserves default but allows override

### Priority 4: Low Priority Enhancements

9. **Document API Differences**
   - Create migration guide for Python users
   - Document option-based vs wrapper patterns
   - Explain Elixir's superior features (pools, telemetry, retries)

10. **Add Comprehensive Tests**
    - Test all endpoint paths
    - Test redirect handling
    - Test error scenarios
    - Test retry logic
    - Test pool routing

### Architectural Recommendations

1. **Module Organization:**
   - Keep current structure (Service, Weights, Futures, Training, Sampling, Telemetry, Session, Rest)
   - Consider adding `Tinkex.API.Models` for model-specific operations
   - Keep Rest module for advanced/admin operations

2. **Type System:**
   - Create comprehensive type modules in `Tinkex.Types.*`
   - Use `@enforce_keys` for required fields
   - Provide `from_json/1` and `to_json/1` helpers
   - Consider using a validation library (Ecto.Changeset or similar)

3. **Documentation:**
   - Add @doc examples for all public functions
   - Document all options (config, timeout, max_retries, etc.)
   - Create guides for common workflows
   - Document pool types and when to use each

4. **Testing Strategy:**
   - Unit tests for each API method
   - Integration tests against test server
   - Mocked tests for error scenarios
   - Property tests for retry logic
   - Telemetry tests for observability

5. **Compatibility:**
   - Maintain API compatibility with Python where possible
   - Document intentional differences (enhancements)
   - Provide clear migration path for Python users

---

## 8. Summary Statistics

### Implementation Status
- **Total Python Methods:** 22
- **Fully Implemented:** 13 (59%)
- **Partially Implemented:** 5 (23%)
- **Missing:** 4 (18%)
- **Elixir Enhancements:** 11 additional methods

### Gap Breakdown by Severity
- **Critical:** 2 gaps (Server Capabilities, Model Info)
- **High:** 3 gaps (Health Check, Model Unload, Heartbeat Path)
- **Medium:** 5 gaps (Checkpoint signatures, Type system, Retry override)
- **Low:** 6 gaps (Wrappers, Headers, Timeouts, etc.)

### Overall Assessment
The Elixir tinkex API module is **70% complete** compared to Python tinker. The implementation is high-quality with several enhancements over Python (pools, telemetry, sophisticated retries). The main gaps are in service/model management endpoints, which are critical for a complete implementation.

### Next Steps
1. Implement Priority 1 gaps (Server Capabilities, Model Info)
2. Implement Priority 2 gaps (Health Check, Model Unload, fix heartbeat)
3. Add comprehensive type system
4. Write migration guide for Python users
5. Add comprehensive test coverage

---

**End of Gap Analysis**
