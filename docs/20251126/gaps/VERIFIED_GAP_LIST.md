# Verified Gap List - Tinker → Tinkex Port

**Date:** November 26, 2025
**Method:** Code review of specified Python and Elixir files

---

## Confirmed Present (No Gap)

These were claimed as gaps but are actually implemented:

### 1. Session Heartbeats ✅
- **Elixir**: `lib/tinkex/session_manager.ex:80-152` (scheduling + logic), `lib/tinkex/api/session.ex:58-63` (POST to `/api/v1/heartbeat`)
- **Status**: Fully implemented, only path differs (`/api/v1/heartbeat` vs Python's `/api/v1/session_heartbeat`)

### 2. Tinker Path Parsing ✅
- **Elixir**: `lib/tinkex/api/rest.ex:249-265` → `parse_tinker_path/1` function
- **Status**: Fully implemented, parses `tinker://run_id/part1/part2` format

### 3. Custom Loss/Regularizer Pipeline ✅
- **Elixir**:
  - `lib/tinkex/training_client.ex:140-201` → `forward_backward_custom/4`
  - `lib/tinkex/regularizer/pipeline.ex` (224 lines) - full orchestration
  - `lib/tinkex/regularizer/executor.ex` - parallel execution
  - `lib/tinkex/regularizer/gradient_tracker.ex` - gradient norms
  - `lib/tinkex/regularizer/telemetry.ex` - event emission
- **Status**: Fully implemented with telemetry integration

### 4. Save/Load Weight Endpoints ✅
- **Elixir**: `lib/tinkex/api/weights.ex`
  - `save_weights/2` (line 13)
  - `load_weights/2` (line 26)
  - `save_weights_for_sampler/2` (line 39)
- **Status**: Endpoints exist; typed responses are missing (see gap #7)

### 5. Training Run Endpoints ✅
- **Elixir**: `lib/tinkex/api/rest.ex`
  - `get_training_run/2` (lines 222-226)
  - `list_training_runs/3` (lines 243-246)
  - `get_training_run_by_tinker_path/2` (lines 201-206)
- **Status**: Endpoints exist; typed response structs missing (see gap #8)

---

## Confirmed Missing/Partial

### Critical Gaps

#### GAP-001: NotGiven Sentinel
- **Severity**: Critical
- **Python**: `_types.py:107-134` - `NotGiven` class distinguishes omitted kwargs from `None`
- **Elixir**: No equivalent; `lib/tinkex/api/api.ex` uses raw maps
- **Impact**: Cannot distinguish explicit `nil` from "field not provided" in requests

#### GAP-002: Response Wrappers/Metadata
- **Severity**: Critical
- **Python**: `_response.py:54-855` - `BaseAPIResponse`, `APIResponse`, `AsyncAPIResponse` with:
  - `.headers`, `.status_code`, `.url`, `.method`, `.elapsed`
  - `.retries_taken`, `.http_response`
  - `.parse()`, `.read()`, `.json()`, `.iter_bytes()`
- **Elixir**: `lib/tinkex/api/api.ex:276-290` returns `{:ok, map()}` from `Jason.decode`
- **Impact**: No access to response metadata, headers, or raw bytes

#### GAP-003: Transform/Serialization System
- **Severity**: Critical
- **Python**: `_utils/_transform.py` - Field aliasing, type coercion, discriminator injection, optional field omission
- **Elixir**: No equivalent module
- **Impact**: Request bodies may have wrong field names or include fields that should be omitted

#### GAP-004: Server Capabilities Endpoint
- **Severity**: Critical
- **Python**: `resources/service.py:22-42` → `get_server_capabilities()` → `/api/v1/get_server_capabilities`
- **Elixir**: `lib/tinkex/api/service.ex` missing - only has `create_model/2` and `create_sampling_session/2`
- **Impact**: Cannot discover supported models/features at runtime

#### GAP-005: Health Check Endpoint
- **Severity**: Critical
- **Python**: `resources/service.py:44-64` → `health_check()` → `/api/v1/healthz`
- **Elixir**: `lib/tinkex/api/service.ex` missing
- **Impact**: No health monitoring for load balancing or readiness probes

---

### High Priority Gaps

#### GAP-006: compute_logprobs
- **Severity**: High
- **Python**: `lib/public_interfaces/sampling_client.py:257-296` → `compute_logprobs(prompt)` returns `list[float | None]`
- **Elixir**: `lib/tinkex/sampling_client.ex` - no such function
- **Impact**: Cannot compute prompt token log probabilities for evaluation

#### GAP-007: Typed Weight Response Structs
- **Severity**: High
- **Python types**:
  - `save_weights_response.py`
  - `save_weights_for_sampler_response.py`
  - `load_weights_response.py`
- **Elixir types**: Only `weights_info_response.ex` exists
- **Impact**: Weight operations return untyped maps

#### GAP-008: Training Run Type Structs
- **Severity**: High
- **Python types**:
  - `training_run.py` - TrainingRun model with fields: `training_run_id`, `base_model`, `model_owner`, `is_lora`, `lora_rank`, `last_request_time`, `corrupted`, `last_checkpoint`, `last_sampler_checkpoint`, `user_metadata`
  - `training_runs_response.py` - TrainingRunsResponse with `training_runs` list and `cursor`
- **Elixir types**: None (glob found no `training_run*.ex`)
- **Impact**: Training run queries return untyped maps

#### GAP-009: SSE Streaming
- **Severity**: High
- **Python**: `_streaming.py` - `Stream`, `AsyncStream` for server-sent events
- **Elixir**: No streaming module
- **Impact**: No support for streaming responses

---

### Medium Priority Gaps

#### GAP-010: CLI Management Commands
- **Severity**: Medium
- **Python CLI commands** (`cli/commands/checkpoint.py`, `cli/commands/run.py`):
  - `checkpoint list` - list checkpoints with pagination
  - `checkpoint info` - show checkpoint details
  - `checkpoint download` - download and extract archive
  - `checkpoint publish/unpublish` - toggle visibility
  - `checkpoint delete` - permanent deletion
  - `run list` - list training runs
  - `run info` - show run details
- **Elixir CLI** (`lib/tinkex/cli.ex`):
  - `checkpoint` - save weights (execution, not management)
  - `run` - sample text (execution, not management)
  - `version` - show version
- **Impact**: Management operations require direct REST client usage

---

### Low Priority Gaps

#### GAP-011: Heartbeat Path Alignment
- **Severity**: Low
- **Python**: `/api/v1/session_heartbeat` (`resources/service.py:150`)
- **Elixir**: `/api/v1/heartbeat` (`lib/tinkex/api/session.ex:58`)
- **Impact**: Functional but path differs; document or align

---

## Summary

| Category | Count |
|----------|-------|
| **False Positives (Implemented)** | 5 |
| **Critical Gaps** | 5 |
| **High Priority Gaps** | 4 |
| **Medium Priority Gaps** | 1 |
| **Low Priority Gaps** | 1 |
| **Total Real Gaps** | 11 |

### Revised Completeness Estimate

Based on verified gaps vs total Python features examined:
- **Endpoints**: ~85% (missing health, capabilities)
- **Types**: ~75% (missing weight responses, training run)
- **Core Infrastructure**: ~60% (missing NotGiven, transform, response wrappers, SSE)
- **CLI**: ~35% (execution only, no management)

**Overall**: ~70-75% complete (revised from original 57%)

---

## Recommended Priority Order

1. **NotGiven sentinel** + basic transform utilities (blocks correct wire format)
2. **Server capabilities + health endpoints** (blocks discovery/monitoring)
3. **Response wrapper** with metadata access (enables debugging)
4. **compute_logprobs** in SamplingClient (enables evaluation)
5. **Typed response structs** for weights and training runs
6. **CLI management commands** (nice-to-have for UX)
7. **SSE streaming** (only if server uses it)
