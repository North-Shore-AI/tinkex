# Type Parity Analysis: Python vs Elixir

**Date**: December 4, 2025

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| Python Types | 71 files |
| Elixir Types | 69 files |
| Full Parity | 42 types |
| Wire-Compatible | 15 types |
| Mismatches | 3 types |
| Missing in Elixir | 8 categories |
| Elixir-Only | 3 types |

---

## Full Parity Types (42)

These types have identical structure in both SDKs:

### Core Data Types
| Type | Fields | Status |
|------|--------|--------|
| TensorData | data, dtype, shape | ✅ PARITY |
| TensorDtype | int64, float32 | ✅ PARITY |
| Datum | model_input, loss_fn_inputs | ✅ PARITY |
| ModelInput | chunks | ✅ PARITY |
| EncodedTextChunk | tokens, type | ✅ PARITY |

### Request Types
| Type | Status |
|------|--------|
| CreateSessionRequest | ✅ PARITY |
| CreateModelRequest | ✅ PARITY |
| ForwardRequest | ✅ PARITY |
| ForwardBackwardRequest | ✅ PARITY |
| ForwardBackwardInput | ✅ PARITY |
| OptimStepRequest | ✅ PARITY |
| SampleRequest | ✅ PARITY |
| CreateSamplingSessionRequest | ✅ PARITY |
| SaveWeightsRequest | ✅ PARITY |
| LoadWeightsRequest | ✅ PARITY |

### Response Types
| Type | Status |
|------|--------|
| CreateSessionResponse | ✅ PARITY |
| CreateModelResponse | ✅ PARITY |
| ForwardBackwardOutput | ✅ PARITY |
| OptimStepResponse | ✅ PARITY |
| SampleResponse | ✅ PARITY |
| SampledSequence | ✅ PARITY |
| CreateSamplingSessionResponse | ✅ PARITY |
| SaveWeightsResponse | ✅ PARITY |
| LoadWeightsResponse | ✅ PARITY |

### Configuration Types
| Type | Fields | Status |
|------|--------|--------|
| AdamParams | learning_rate, beta1, beta2, eps | ✅ PARITY (same defaults) |
| LoraConfig | rank, seed, train_mlp, train_attn, train_unembed | ✅ PARITY |
| SamplingParams | max_tokens, seed, stop, temperature, top_k, top_p | ✅ PARITY |

### Checkpoint Types
| Type | Status |
|------|--------|
| ParsedCheckpointTinkerPath | ✅ PARITY |

### Metadata Types
| Type | Status |
|------|--------|
| SupportedModel | ✅ PARITY |
| GetServerCapabilitiesResponse | ✅ PARITY |
| HealthResponse | ✅ PARITY |
| Cursor | ✅ PARITY |
| ModelData | ✅ PARITY |
| GetInfoResponse | ✅ PARITY |
| WeightsInfoResponse | ✅ PARITY |

### Error Types
| Type | Status |
|------|--------|
| RequestFailedResponse | ✅ PARITY |

---

## Wire-Compatible Types (15)

These types work correctly but use different Elixir conventions:

### Atom vs String Enums

| Type | Python | Elixir | Wire Format |
|------|--------|--------|-------------|
| TensorDtype | `"int64"`, `"float32"` | `:int64`, `:float32` | String (converted) |
| EventType | `"SESSION_START"` | `:session_start` | String (uppercase) |
| Severity | `"DEBUG"`, `"INFO"` | `:debug`, `:info` | String (uppercase) |
| RequestErrorCategory | `"unknown"`, `"server"` | `:unknown`, `:server` | String (lowercase) |
| QueueState | `"active"` | `:active` | String (lowercase) |
| StopReason | `"length"`, `"stop"` | `:length`, `:stop` | String (lowercase) |
| LossFnType | `"cross_entropy"` | `:cross_entropy` | String (lowercase) |

### Telemetry Event Types

| Type | Python Fields | Elixir Fields | Status |
|------|---------------|---------------|--------|
| GenericEvent | event, event_id, event_session_index, severity, timestamp, event_name, event_data | Same | ✅ Compatible |
| SessionStartEvent | event, event_id, event_session_index, severity, timestamp | Same | ✅ Compatible |
| SessionEndEvent | event, event_id, event_session_index, severity, timestamp, duration | Same | ✅ Compatible |
| TryAgainResponse | type, request_id, queue_state, retry_after_ms | Same | ✅ Compatible |

---

## Type Mismatches (3)

### 1. ImageChunk - CRITICAL

**Python (Required Fields):**
```python
class ImageChunk:
    data: bytes
    format: Literal["png", "jpeg"]
    height: int          # ← REQUIRED
    width: int           # ← REQUIRED
    tokens: int          # ← REQUIRED
    expected_tokens: int | None
    type: Literal["image"]
```

**Elixir (Missing Fields):**
```elixir
defstruct [
  :data,               # base64 string
  :format,             # :png | :jpeg
  :expected_tokens,    # optional
  :type                # "image"
  # MISSING: height, width, tokens
]
```

**Impact**: Cannot construct valid ImageChunk for multimodal inputs

**Fix Required**: Add `height`, `width`, `tokens` fields to Elixir struct

---

### 2. Checkpoint.time - Type Mismatch

**Python:**
```python
class Checkpoint:
    time: datetime  # Python datetime object
```

**Elixir:**
```elixir
defstruct [
  :time  # String.t() (ISO 8601 format)
]
```

**Impact**: Serialization works (ISO strings), but Elixir lacks datetime operations

**Fix Recommended**: Parse to DateTime.t() or keep string with clear documentation

---

### 3. TrainingRun - Partial Implementation

**Python:**
```python
class TrainingRun:
    training_run_id: str
    base_model: str
    model_owner: str
    is_lora: bool
    corrupted: bool = False    # ← CRITICAL FIELD
    lora_rank: int | None
    last_request_time: datetime
    last_checkpoint: Checkpoint | None
    last_sampler_checkpoint: Checkpoint | None
    user_metadata: dict[str, str] | None
```

**Elixir:**
```elixir
# Fields exist but need verification of complete parsing
defstruct [
  :training_run_id,
  :base_model,
  :model_owner,
  :is_lora,
  :corrupted,              # ← Verify this exists and is parsed
  :lora_rank,
  :last_request_time,
  :last_checkpoint,
  :last_sampler_checkpoint,
  :user_metadata
]
```

**Impact**: Cannot detect poisoned/corrupted jobs without `corrupted` field

---

## Missing Type Categories (8)

### 1. Session Query Types

**Missing:**
- `GetSessionResponse` - Session info with training_run_ids, sampler_ids
- `ListSessionsResponse` - Paginated session list

**Python:**
```python
class GetSessionResponse(BaseModel):
    training_run_ids: list[ModelID]
    sampler_ids: list[str]

class ListSessionsResponse(BaseModel):
    sessions: list[SessionInfo]
    cursor: Cursor
```

---

### 2. Telemetry Batch Types

**Missing:**
- `TelemetryBatch` - Batch container
- `TelemetrySendRequest` - Send request with events, platform, sdk_version
- `TelemetryResponse` - Send response

**Python:**
```python
class TelemetrySendRequest(BaseModel):
    events: List[TelemetryEvent]
    platform: str
    sdk_version: str
    session_id: str
```

---

### 3. Future Polling Types

**Missing:**
- `FutureRetrieveRequest` - Request to poll future
- `FutureRetrieveResponse` - Response with result or pending status
- `FutureResponses` - Union of response types

---

### 4. Checkpoint Archive Types

**Missing (or incomplete):**
- `CheckpointArchiveUrlResponse` - Signed URL + expiration
- `CheckpointsListResponse` - List of checkpoints

**Python:**
```python
class CheckpointArchiveUrlResponse(BaseModel):
    url: str        # Signed download URL
    expires: datetime  # Expiration timestamp
```

---

### 5. Sampler Weights Types

**Missing:**
- `SaveWeightsForSamplerRequest` - Save for sampler request
- `SaveWeightsForSamplerResponse` - Response with path

---

### 6. Session Heartbeat Types

**Missing:**
- `SessionHeartbeatRequest` - Heartbeat request
- `SessionHeartbeatResponse` - Heartbeat response

---

### 7. Unhandled Exception Event

**Missing:**
- `UnhandledExceptionEvent` - Exception telemetry with traceback

**Python:**
```python
class UnhandledExceptionEvent(BaseModel):
    error_message: str
    error_type: str
    event: EventType
    event_id: str
    event_session_index: int
    severity: Severity
    timestamp: datetime
    traceback: Optional[str]
```

---

### 8. Training Runs Response

**Missing:**
- `TrainingRunsResponse` - Paginated training runs list

**Python:**
```python
class TrainingRunsResponse(BaseModel):
    training_runs: list[TrainingRun]
    cursor: Cursor
```

---

## Elixir-Only Extensions (3)

These types exist in Elixir but not in the Python SDK:

### 1. RegularizerSpec
```elixir
defstruct [
  :fn,       # function()
  :weight,   # number()
  :name,     # String.t()
  :async     # boolean()
]
```

### 2. RegularizerOutput
```elixir
defstruct [
  :name,
  :value,
  :weight,
  :contribution,
  :grad_norm,
  :grad_norm_weighted,
  :custom
]
```

### 3. CustomLossOutput
```elixir
defstruct [
  :loss_total,
  :base_loss,
  :regularizers,
  :regularizer_total,
  :total_grad_norm
]
```

These are research extensions for advanced regularization workflows.

---

## Priority Fix List

### P0 (Critical)
1. **ImageChunk** - Add `height`, `width`, `tokens` fields
2. **TrainingRun.corrupted** - Ensure field is parsed correctly

### P1 (High)
3. **GetSessionResponse** - Add type
4. **ListSessionsResponse** - Add type
5. **TelemetrySendRequest** - Add for batched telemetry
6. **CheckpointArchiveUrlResponse** - Complete type

### P2 (Medium)
7. **FutureRetrieveRequest/Response** - Add types
8. **SessionHeartbeatRequest/Response** - Add types
9. **TrainingRunsResponse** - Add type
10. **UnhandledExceptionEvent** - Add type

### P3 (Low)
11. **Checkpoint.time** - Consider DateTime parsing
12. Document Elixir-only extensions
