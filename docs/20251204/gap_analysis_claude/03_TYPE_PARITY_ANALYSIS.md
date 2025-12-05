# Type Parity Analysis: Python vs Elixir

**Date**: December 4, 2025

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| Python Types (documented) | 71 files |
| Elixir Types | 74 modules |
| Full/Wire Parity | All documented |
| Mismatches | 1 (timestamp normalization) |
| Missing in Elixir | 0 |
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

## Type Mismatches (1)

### Checkpoint.time - Type Normalization

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

## Missing Type Categories

None. Session queries, telemetry batch/send, future polling, sampler weights, heartbeat, unhandled exception events, and training run pagination are all implemented in `lib/tinkex/types/`.

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

### P1 (High)
1. Normalize checkpoint timestamps (`Checkpoint.time`) to `DateTime.t()` for downstream consumers.

### P2 (Medium)
2. Add integration/property tests for `TrainingRun.from_map/1` to keep `corrupted` parsing regression-proof.
3. Standardize timestamp parsing across related types (CheckpointsListResponse, TrainingRunsResponse).

### P3 (Low)
4. Document Elixir-only extensions and custom loss helpers alongside Python equivalents.
