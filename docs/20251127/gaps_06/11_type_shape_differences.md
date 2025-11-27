# Gap #11: Minor Type-Shape Differences - Deep Dive Analysis

**Date:** 2025-11-27
**Investigator:** Claude Code
**Status:** Comprehensive Analysis Complete

## Executive Summary

This document provides a comprehensive type-by-type analysis of shape and field differences between the Python SDK (Tinker) and Elixir SDK (Tinkex). The investigation reveals **systematic architectural differences** in how the two SDKs handle:

1. **Nested Type Structures**: Python preserves rich object graphs; Elixir often flattens
2. **DateTime Handling**: Python uses native `datetime` objects; Elixir uses strings or `DateTime` with fallback
3. **Metadata Preservation**: Python maintains structured metadata; Elixir extracts scalar values
4. **Optional Field Semantics**: Both handle optionals, but Elixir is more defensive in parsing

### Key Findings

- **73 Python type modules** in `tinker/src/tinker/types` (71 if you exclude the `__init__.py` stubs), including the newer `get_sampler_response.py` and `future_retrieve_response.py`
- **72 Elixir type modules** in `lib/tinkex/types` (telemetry + `future_responses.ex`, custom loss/regularizer specs, type_aliases)
- **2 data-loss gaps**: `GetServerCapabilitiesResponse` flattens `SupportedModel`, and `CheckpointArchiveUrlResponse` drops the `expires` timestamp
- **Shape/type-safety gaps**: DateTime fields shipped as strings (6 types), untyped `loss_fn_outputs` and cursor maps, `FutureRetrieveResponse` modeled as status wrappers instead of the Python union, `TelemetryBatch` lacks platform/sdk/session fields, and several responses/requests omit Python’s `type` literals
- **Parity holds** for sampling and tensor wire formats (e.g., `SampleRequest` tri-state handling, `TensorData` schema) with ecosystem-specific helper differences only

---

## Part 1: Python Types Deep Dive

### 1.1 Type Inventory

The Python SDK defines **71 data classes/aliases** in `tinker/src/tinker/types` (73 modules if you include the `__init__.py` stubs). The main groupings are:

#### Core Request/Response Types
- `create_session_request.py` / `create_session_response.py`
- `create_model_request.py` / `create_model_response.py`
- `create_sampling_session_request.py` / `create_sampling_session_response.py`
- `sample_request.py` / `sample_response.py`
- `forward_request.py` / `forward_backward_request.py`
- `optim_step_request.py` / `optim_step_response.py`
- `get_info_request.py` / `get_info_response.py`
- `get_server_capabilities_response.py`
- `get_sampler_response.py`
- `health_response.py`
- `session_heartbeat_request.py` / `session_heartbeat_response.py`

#### Training & Model Types
- `training_run.py`
- `training_runs_response.py`
- `checkpoint.py`
- `checkpoints_list_response.py`
- `checkpoint_archive_url_response.py`
- `lora_config.py`
- `datum.py`
- `model_input.py`
- `model_input_chunk.py`
- `tensor_data.py`
- `loss_fn_inputs.py`
- `loss_fn_output.py`

#### Telemetry Types (10 files)
- `telemetry_event.py` (union)
- `telemetry_batch.py`
- `telemetry_send_request.py`
- `telemetry_response.py`
- `generic_event.py`
- `session_start_event.py`
- `session_end_event.py`
- `unhandled_exception_event.py`
- `event_type.py`
- `severity.py`

#### Weight Management
- `save_weights_request.py` / `save_weights_response.py`
- `load_weights_request.py` / `load_weights_response.py`
- `save_weights_for_sampler_request.py` / `save_weights_for_sampler_response.py`
- `weights_info_response.py`

#### Sampling & Generation
- `sampling_params.py`
- `sampled_sequence.py`
- `stop_reason.py`
- `encoded_text_chunk.py`
- `image_chunk.py`
- `image_asset_pointer_chunk.py`

#### Session Management & Pagination
- `get_session_response.py`
- `list_sessions_response.py`
- `cursor.py`

#### Futures & Error Handling
- `request_failed_response.py`
- `try_again_response.py`
- `request_error_category.py`
- `future_retrieve_request.py` / `future_retrieve_response.py`
- `request_id.py`
- `shared/untyped_api_future.py`

#### Utility Types
- `model_id.py`
- `tensor_dtype.py`
- `loss_fn_type.py`
- `forward_backward_input.py`
- `forward_backward_output.py`
- `unload_model_request.py` / `unload_model_response.py`

---

### 1.2 Python Type Field Analysis

#### 1.2.1 GetServerCapabilitiesResponse

**File:** `get_server_capabilities_response.py`

```python
class SupportedModel(BaseModel):
    model_name: Optional[str] = None

class GetServerCapabilitiesResponse(BaseModel):
    supported_models: List[SupportedModel]
```

**Fields:**
- `supported_models`: List of SupportedModel objects
  - Each SupportedModel has:
    - `model_name`: Optional string

**Nested Structure:** YES - Contains list of structured objects

---

#### 1.2.2 TelemetryBatch

**File:** `telemetry_batch.py`

```python
class TelemetryBatch(BaseModel):
    events: List[TelemetryEvent]
    platform: str        # Host platform name
    sdk_version: str     # SDK version string
    session_id: str
```

**Fields:**
- `events`: List[TelemetryEvent] - Union of 4 event types
- `platform`: str (required)
- `sdk_version`: str (required)
- `session_id`: str (required)

**Nested Structure:** YES - Contains polymorphic event list

---

#### 1.2.3 TelemetrySendRequest

**File:** `telemetry_send_request.py`

```python
class TelemetrySendRequest(StrictBase):
    events: List[TelemetryEvent]
    platform: str        # Host platform name
    sdk_version: str     # SDK version string
    session_id: str
```

**Fields:** IDENTICAL to TelemetryBatch (different base class)

**Note:** Uses StrictBase (strict validation) vs BaseModel

---

#### 1.2.4 TrainingRun

**File:** `training_run.py`

```python
class TrainingRun(BaseModel):
    training_run_id: str
    base_model: str
    model_owner: str
    is_lora: bool
    corrupted: bool = False
    lora_rank: int | None = None
    last_request_time: datetime          # ← Python datetime object
    last_checkpoint: Checkpoint | None = None
    last_sampler_checkpoint: Checkpoint | None = None
    user_metadata: dict[str, str] | None = None
```

**Fields:**
- All fields present
- `last_request_time`: **datetime object** (not string)
- Nested `Checkpoint` objects for both checkpoint fields
- `user_metadata`: Typed as `dict[str, str]` (specific constraint)

**Nested Structure:** YES - Contains Checkpoint objects

---

#### 1.2.5 Checkpoint

**File:** `checkpoint.py`

```python
class Checkpoint(BaseModel):
    checkpoint_id: str
    checkpoint_type: CheckpointType  # Literal["training", "sampler"]
    time: datetime                   # ← Python datetime object
    tinker_path: str
    size_bytes: int | None = None
    public: bool = False
```

**Fields:**
- 6 fields total
- `time`: **datetime object** (not string)
- `checkpoint_type`: Literal type (typed string)

**Also Defined:**
```python
class ParsedCheckpointTinkerPath(BaseModel):
    tinker_path: str
    training_run_id: str
    checkpoint_type: CheckpointType
    checkpoint_id: str

    @classmethod
    def from_tinker_path(cls, tinker_path: str) -> "ParsedCheckpointTinkerPath"
```

**Note:** ParsedCheckpointTinkerPath NOT present in Elixir

---

#### 1.2.6 TelemetryEvent (Union Type)

**File:** `telemetry_event.py`

```python
TelemetryEvent: TypeAlias = Union[
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent,
    GenericEvent
]
```

**Structure:** Tagged union of 4 event types

---

#### 1.2.7 GenericEvent

**File:** `generic_event.py`

```python
class GenericEvent(BaseModel):
    event: EventType              # Enum/Literal
    event_id: str
    event_name: str
    event_session_index: int
    severity: Severity
    timestamp: datetime           # ← Python datetime object
    event_data: Dict[str, object] = {}
```

**Fields:**
- 7 fields total
- `timestamp`: **datetime object**
- `event_data`: Generic dict (arbitrary JSON)

---

#### 1.2.8 SessionStartEvent

**File:** `session_start_event.py`

```python
class SessionStartEvent(BaseModel):
    event: EventType
    event_id: str
    event_session_index: int
    severity: Severity
    timestamp: datetime           # ← Python datetime object
```

**Fields:** 5 fields, minimal event

---

#### 1.2.9 SessionEndEvent

**File:** `session_end_event.py`

```python
class SessionEndEvent(BaseModel):
    duration: str                 # ISO 8601 duration string
    event: EventType
    event_id: str
    event_session_index: int
    severity: Severity
    timestamp: datetime           # ← Python datetime object
```

**Fields:** 6 fields (adds `duration`)

---

#### 1.2.10 UnhandledExceptionEvent

**File:** `unhandled_exception_event.py`

```python
class UnhandledExceptionEvent(BaseModel):
    error_message: str
    error_type: str
    event: EventType
    event_id: str
    event_session_index: int
    severity: Severity
    timestamp: datetime           # ← Python datetime object
    traceback: Optional[str] = None
```

**Fields:** 8 fields (adds error info + traceback)

---

#### 1.2.11 CreateSessionResponse

**File:** `create_session_response.py`

```python
class CreateSessionResponse(BaseModel):
    type: Literal["create_session"] = "create_session"
    info_message: str | None = None
    warning_message: str | None = None
    error_message: str | None = None
    session_id: str
```

**Fields:** 5 fields (1 literal + 3 optional messages + session_id)

---

#### 1.2.12 SamplingParams

**File:** `sampling_params.py`

```python
class SamplingParams(BaseModel):
    max_tokens: Optional[int] = None
    seed: Optional[int] = None
    stop: Union[str, Sequence[str], Sequence[int], None] = None
    temperature: float = 1
    top_k: int = -1
    top_p: float = 1
```

**Fields:** 6 fields
- `stop`: Polymorphic (string OR list of strings OR list of ints)

---

#### 1.2.13 TensorData

**File:** `tensor_data.py`

```python
class TensorData(StrictBase):
    data: Union[List[int], List[float]]
    dtype: TensorDtype
    shape: Optional[List[int]] = None

    @classmethod
    def from_numpy(cls, array: npt.NDArray[Any]) -> "TensorData"

    @classmethod
    def from_torch(cls, tensor: "torch.Tensor") -> "TensorData"

    def to_numpy(self) -> npt.NDArray[Any]

    def to_torch(self) -> "torch.Tensor"

    def tolist(self) -> List[Any]
```

**Fields:** 3 data fields + 5 conversion methods

**Note:** Rich interop with NumPy and PyTorch

---

#### 1.2.14 ModelInput

**File:** `model_input.py`

```python
class ModelInput(StrictBase):
    chunks: List[ModelInputChunk]

    @classmethod
    def from_ints(cls, tokens: List[int]) -> "ModelInput"

    def to_ints(self) -> List[int]

    @property
    def length(self) -> int

    @classmethod
    def empty(cls) -> "ModelInput"

    def append(self, chunk: ModelInputChunk) -> "ModelInput"

    def append_int(self, token: int) -> "ModelInput"
```

**Fields:** 1 field + 6 methods

**Note:** Functional API with immutable append

---

#### 1.2.15 Datum

**File:** `datum.py`

```python
class Datum(StrictBase):
    loss_fn_inputs: LossFnInputs  # Dict[str, TensorData]
    model_input: ModelInput

    @model_validator(mode="before")
    @classmethod
    def convert_tensors(cls, data: Any) -> Any:
        # Auto-converts torch.Tensor and numpy arrays
```

**Fields:** 2 fields + tensor auto-conversion validator

**Special:** Pre-validation tensor conversion from PyTorch/NumPy

---

#### 1.2.16 ForwardBackwardOutput

**File:** `forward_backward_output.py`

```python
class ForwardBackwardOutput(BaseModel):
    loss_fn_output_type: str
    loss_fn_outputs: List[LossFnOutput]  # List[Dict[str, TensorData]]
    metrics: Dict[str, float]
```

**Fields:** 3 fields
- `loss_fn_outputs`: List of dicts (each dict is field_name -> TensorData)
- `metrics`: Flat dict of metric names to values

---

#### 1.2.17 SampledSequence

**File:** `sampled_sequence.py`

```python
class SampledSequence(BaseModel):
    stop_reason: StopReason
    tokens: List[int]
    logprobs: Optional[List[float]] = None
```

**Fields:** 3 fields (stop reason + tokens + optional logprobs)

---

#### 1.2.18 LoraConfig

**File:** `lora_config.py`

```python
class LoraConfig(StrictBase):
    rank: int
    seed: Optional[int] = None
    train_unembed: bool = True
    train_mlp: bool = True
    train_attn: bool = True
```

**Fields:** 5 fields (1 required int + 1 optional int + 3 bools)

---

#### 1.2.19 GetInfoResponse

**File:** `get_info_response.py`

```python
class ModelData(BaseModel):
    arch: Optional[str] = None
    model_name: Optional[str] = None
    tokenizer_id: Optional[str] = None

class GetInfoResponse(BaseModel):
    type: Optional[Literal["get_info"]] = None
    model_data: ModelData
    model_id: ModelID
    is_lora: Optional[bool] = None
    lora_rank: Optional[int] = None
    model_name: Optional[str] = None
```

**Fields:**
- GetInfoResponse: 6 fields
- ModelData: 3 fields (nested)

**Nested Structure:** YES - Contains ModelData object

---

#### 1.2.20 CheckpointsListResponse

**File:** `checkpoints_list_response.py`

```python
class CheckpointsListResponse(BaseModel):
    checkpoints: list[Checkpoint]
    cursor: Cursor | None = None
```

**Fields:** 2 fields
- `checkpoints`: List of Checkpoint objects
- `cursor`: Optional pagination cursor

**Nested Structure:** YES - List of Checkpoints + Cursor

---

#### 1.2.21 TrainingRunsResponse

**File:** `training_runs_response.py`

```python
class TrainingRunsResponse(BaseModel):
    training_runs: list[TrainingRun]
    cursor: Cursor
```

**Fields:** 2 fields (cursor always present, not optional)

**Nested Structure:** YES - List of TrainingRuns + Cursor

---

#### 1.2.22 Cursor

**File:** `cursor.py`

```python
class Cursor(BaseModel):
    offset: int
    limit: int
    total_count: int
```

**Fields:** 3 int fields for pagination

---

#### 1.2.23 CreateModelRequest

**File:** `create_model_request.py`

```python
class CreateModelRequest(StrictBase):
    session_id: str
    model_seq_id: int
    base_model: str
    user_metadata: Optional[dict[str, Any]] = None
    lora_config: Optional[LoraConfig] = None
    type: Literal["create_model"] = "create_model"
```

**Fields:** 6 fields
- `user_metadata`: Generic dict (any values)

---

#### 1.2.24 SampleRequest

**File:** `sample_request.py`

```python
class SampleRequest(StrictBase):
    num_samples: int = 1
    prompt: ModelInput
    sampling_params: SamplingParams
    base_model: Optional[str] = None
    model_path: Optional[str] = None
    sampling_session_id: Optional[str] = None
    seq_id: Optional[int] = None
    prompt_logprobs: Optional[bool] = None  # ← Tri-state!
    topk_prompt_logprobs: int = 0
    type: Literal["sample"] = "sample"
```

**Fields:** 10 fields
- `prompt_logprobs`: **Tri-state** (None/False/True)

**Note:** Critical tri-state field for optional feature

---

## Part 2: Elixir Types Deep Dive

### 2.1 Type Inventory

The Elixir SDK mirrors most Python types with some differences. There are **72 modules** under `lib/tinkex/types` (including telemetry).

#### Main Types Directory
- Core request/response types, sampling/model inputs, checkpoints, weights management, pagination helpers, and optimizer types all live here with `.ex` extensions.
- `future_responses.ex` implements the future retrieve union as status-tagged structs (`pending`/`completed`/`failed`) plus `TryAgainResponse`.

#### Telemetry Subdirectory (9 files)
Organized under `lib/tinkex/types/telemetry/`:
- `event_type.ex`
- `severity.ex`
- `telemetry_event.ex`
- `telemetry_batch.ex`
- `telemetry_send_request.ex`
- `generic_event.ex`
- `session_start_event.ex`
- `session_end_event.ex`
- `unhandled_exception_event.ex`

#### Additional Elixir-Specific Types
- `adam_params.ex`
- `queue_state.ex`
- `future_responses.ex`
- `regularizer_output.ex` / `custom_loss_output.ex` / `regularizer_spec.ex`
- `type_aliases.ex` (Elixir-only helper aliases)

---

### 2.2 Elixir Type Field Analysis

#### 2.2.1 GetServerCapabilitiesResponse

**File:** `get_server_capabilities_response.ex`

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @type t :: %__MODULE__{
    supported_models: [String.t()]  # ← Flattened to list of strings!
  }

  def from_json(map) do
    models = map["supported_models"] || map[:supported_models] || []

    names = models
    |> Enum.map(fn
      %{"model_name" => name} -> name
      %{model_name: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)

    %__MODULE__{supported_models: names}
  end
end
```

**Fields:**
- `supported_models`: `[String.t()]` (list of strings)

**DIFFERENCE:** Python has `List[SupportedModel]` (objects), Elixir has `[String.t()]` (strings)

**Data Loss:** YES - Loses structured SupportedModel objects, extracts only model_name

---

#### 2.2.2 TelemetryBatch

**File:** `telemetry_batch.ex`

```elixir
defmodule Tinkex.Types.Telemetry.TelemetryBatch do
  @type t :: %__MODULE__{
    events: [TelemetryEvent.t()],
    metadata: map()  # ← Generic metadata, not structured fields!
  }

  defstruct events: [], metadata: %{}
```

**Fields:**
- `events`: List of TelemetryEvent
- `metadata`: Generic map (not structured fields)

**DIFFERENCE:** Python has explicit `platform`, `sdk_version`, `session_id` fields; Elixir bundles into `metadata` map

**Data Loss:** NO - Data preserved, but shape differs

**Object Graph:** Different structure (flattened)

---

#### 2.2.3 TelemetrySendRequest

**File:** `telemetry_send_request.ex`

```elixir
defmodule Tinkex.Types.Telemetry.TelemetrySendRequest do
  @type t :: %__MODULE__{
    session_id: String.t(),
    platform: String.t(),
    sdk_version: String.t(),
    events: [TelemetryEvent.t()] | TelemetryBatch.t()  # ← Union type!
  }

  @enforce_keys [:session_id, :platform, :sdk_version, :events]
  defstruct [:session_id, :platform, :sdk_version, :events]
```

**Fields:**
- All 4 fields present
- `events`: Can be EITHER list or TelemetryBatch (union)

**DIFFERENCE:** Python has `List[TelemetryEvent]` only; Elixir allows batch or list

**Enhancement:** Elixir is more flexible

---

#### 2.2.4 TrainingRun

**File:** `training_run.ex`

```elixir
defmodule Tinkex.Types.TrainingRun do
  @type t :: %__MODULE__{
    training_run_id: String.t(),
    base_model: String.t(),
    model_owner: String.t(),
    is_lora: boolean(),
    lora_rank: integer() | nil,
    corrupted: boolean(),
    last_request_time: DateTime.t() | String.t(),  # ← DateTime OR String!
    last_checkpoint: Checkpoint.t() | nil,
    last_sampler_checkpoint: Checkpoint.t() | nil,
    user_metadata: map() | nil
  }

  defp parse_datetime(nil), do: nil
  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> value  # ← Fallback to string on parse failure!
    end
  end
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(other), do: other
```

**Fields:**
- All 9 fields present
- `last_request_time`: DateTime OR string (defensive parsing)
- `user_metadata`: Generic `map()` (Python has `dict[str, str]`)

**DIFFERENCE:**
1. Elixir attempts DateTime parse but falls back to string
2. Python enforces `dict[str, str]`, Elixir allows any map

**Potential Data Loss:** If timestamp is non-ISO8601 or metadata has non-string values, Python would reject but Elixir accepts

---

#### 2.2.5 Checkpoint

**File:** `checkpoint.ex`

```elixir
defmodule Tinkex.Types.Checkpoint do
  @type t :: %__MODULE__{
    checkpoint_id: String.t(),
    checkpoint_type: String.t(),  # ← String, not literal type
    tinker_path: String.t(),
    size_bytes: integer() | nil,
    public: boolean(),
    time: String.t()  # ← String, not DateTime!
  }

  defstruct [:checkpoint_id, :checkpoint_type, :tinker_path,
             :size_bytes, :public, :time]
```

**Fields:**
- All 6 fields present
- `time`: **String** (not DateTime)
- `checkpoint_type`: Plain string (not literal)

**DIFFERENCE:** Python has `datetime` object; Elixir keeps as string

**No ParsedCheckpointTinkerPath:** Missing utility type

---

#### 2.2.6 TelemetryEvent (Union Type)

**File:** `telemetry_event.ex`

```elixir
@type t ::
  GenericEvent.t()
  | SessionStartEvent.t()
  | SessionEndEvent.t()
  | UnhandledExceptionEvent.t()

def from_map(%{"event" => event_type} = map) do
  case EventType.parse(event_type) do
    :generic_event -> GenericEvent.from_map(map)
    :session_start -> SessionStartEvent.from_map(map)
    :session_end -> SessionEndEvent.from_map(map)
    :unhandled_exception -> UnhandledExceptionEvent.from_map(map)
    nil -> nil
  end
end
```

**Same 4 event types**, runtime dispatch based on event field

---

#### 2.2.7 GenericEvent

**File:** `generic_event.ex`

```elixir
@type t :: %__MODULE__{
  event: :generic_event,
  event_id: String.t(),
  event_session_index: non_neg_integer(),
  severity: Severity.t(),
  timestamp: String.t(),  # ← String, not DateTime!
  event_name: String.t(),
  event_data: map()
}
```

**Fields:**
- All 7 fields present
- `timestamp`: **String** (not DateTime)

**DIFFERENCE:** Python `datetime`, Elixir `String.t()`

---

#### 2.2.8 SessionStartEvent

**File:** `session_start_event.ex`

```elixir
@type t :: %__MODULE__{
  event: :session_start,
  event_id: String.t(),
  event_session_index: non_neg_integer(),
  severity: Severity.t(),
  timestamp: String.t()  # ← String
}
```

**DIFFERENCE:** timestamp is string

---

#### 2.2.9 SessionEndEvent

**File:** `session_end_event.ex`

```elixir
@type t :: %__MODULE__{
  event: :session_end,
  event_id: String.t(),
  event_session_index: non_neg_integer(),
  severity: Severity.t(),
  timestamp: String.t(),  # ← String
  duration: String.t() | nil
}
```

**DIFFERENCE:** timestamp is string, duration is optional (Python required)

---

#### 2.2.10 UnhandledExceptionEvent

**File:** `unhandled_exception_event.ex`

```elixir
@type t :: %__MODULE__{
  event: :unhandled_exception,
  event_id: String.t(),
  event_session_index: non_neg_integer(),
  severity: Severity.t(),
  timestamp: String.t(),  # ← String
  error_type: String.t(),
  error_message: String.t(),
  traceback: String.t() | nil
}
```

**All fields match**, timestamp is string

---

#### 2.2.11 CreateSessionResponse

**File:** `create_session_response.ex`

```elixir
@enforce_keys [:session_id]
defstruct [:session_id, :info_message, :warning_message, :error_message]

@type t :: %__MODULE__{
  session_id: String.t(),
  info_message: String.t() | nil,
  warning_message: String.t() | nil,
  error_message: String.t() | nil
}
```

**Fields:** 4 fields (missing `type` literal field)

**DIFFERENCE:** Python has `type: Literal["create_session"]`, Elixir omits

**Minor:** Type field likely not used in practice

---

#### 2.2.12 SamplingParams

**File:** `sampling_params.ex`

```elixir
@derive {Jason.Encoder, only: [:max_tokens, :seed, :stop,
                                :temperature, :top_k, :top_p]}
defstruct [
  :max_tokens,
  :seed,
  :stop,
  temperature: 1.0,
  top_k: -1,
  top_p: 1.0
]

@type t :: %__MODULE__{
  max_tokens: non_neg_integer() | nil,
  seed: integer() | nil,
  stop: String.t() | [String.t()] | [integer()] | nil,
  temperature: float(),
  top_k: integer(),
  top_p: float()
}
```

**Perfect match** - All fields, types, defaults identical

---

#### 2.2.13 TensorData

**File:** `tensor_data.ex`

```elixir
defstruct [:data, :dtype, :shape]

@type t :: %__MODULE__{
  data: [number()],
  dtype: TensorDtype.t(),
  shape: [non_neg_integer()] | nil
}

def from_nx(%Nx.Tensor{} = tensor) do
  {casted_tensor, dtype} = normalize_tensor(tensor)
  shape_tuple = Nx.shape(casted_tensor)

  %__MODULE__{
    data: Nx.to_flat_list(casted_tensor),
    dtype: dtype,
    shape: maybe_list_shape(shape_tuple)
  }
end

def to_nx(%__MODULE__{data: data, dtype: dtype, shape: shape}) do
  data
  |> Nx.tensor(type: TensorDtype.to_nx_type(dtype))
  |> Nx.reshape(List.to_tuple(shape))
end
```

**Fields:** Same 3 fields
**Conversion:** Nx (Elixir) instead of PyTorch/NumPy

**DIFFERENCE:** Integration layer differs (Nx vs PyTorch/NumPy) but wire format identical

---

#### 2.2.14 ModelInput

**File:** `model_input.ex`

```elixir
@derive {Jason.Encoder, only: [:chunks]}
defstruct chunks: []

@type chunk ::
  EncodedTextChunk.t()
  | Tinkex.Types.ImageChunk.t()
  | Tinkex.Types.ImageAssetPointerChunk.t()

@type t :: %__MODULE__{
  chunks: [chunk()]
}

def from_ints(tokens) when is_list(tokens) do
  %__MODULE__{
    chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
  }
end

def to_ints(%__MODULE__{chunks: chunks}) do
  Enum.flat_map(chunks, fn
    %EncodedTextChunk{tokens: tokens} -> tokens
    _ -> raise ArgumentError, "Cannot convert non-text chunk to ints"
  end)
end

def from_text(text, opts \\ []) do
  # Tokenization via Tinkex.Tokenizer
end
```

**Fields:** 1 field (chunks)
**Methods:** Similar API surface

**Enhancement:** Elixir has `from_text/2` helper (Python doesn't)

---

#### 2.2.15 Datum

**File:** `datum.ex`

```elixir
@enforce_keys [:model_input]
@derive {Jason.Encoder, only: [:model_input, :loss_fn_inputs]}
defstruct [:model_input, loss_fn_inputs: %{}]

@type t :: %__MODULE__{
  model_input: ModelInput.t(),
  loss_fn_inputs: %{String.t() => TensorData.t()}
}

def new(attrs) do
  %__MODULE__{
    model_input: attrs[:model_input],
    loss_fn_inputs: convert_loss_fn_inputs(attrs[:loss_fn_inputs] || %{})
  }
end

defp maybe_convert_tensor(%Nx.Tensor{} = tensor) do
  TensorData.from_nx(tensor)
end
```

**Fields:** Same 2 fields
**Auto-conversion:** Nx.Tensor → TensorData (vs PyTorch/NumPy in Python)

**Parity:** Equivalent functionality, different ecosystem

---

#### 2.2.16 ForwardBackwardOutput

**File:** `forward_backward_output.ex`

```elixir
@enforce_keys [:loss_fn_output_type]
defstruct [:loss_fn_output_type, loss_fn_outputs: [], metrics: %{}]

@type t :: %__MODULE__{
  loss_fn_output_type: String.t(),
  loss_fn_outputs: [map()],  # ← Not typed as TensorData
  metrics: %{String.t() => float()}
}

def from_json(json) do
  %__MODULE__{
    loss_fn_output_type: json["loss_fn_output_type"],
    loss_fn_outputs: json["loss_fn_outputs"] || [],
    metrics: json["metrics"] || %{}
  }
end
```

**Fields:** 3 fields
- `loss_fn_outputs`: Typed as `[map()]` (not structured)

**DIFFERENCE:** Python types as `List[LossFnOutput]` (where LossFnOutput = Dict[str, TensorData]), Elixir as generic `[map()]`

**Minor:** No data loss, just less type safety

---

#### 2.2.17 SampledSequence

**File:** `sampled_sequence.ex`

```elixir
@enforce_keys [:tokens]
defstruct [:tokens, :logprobs, :stop_reason]

@type t :: %__MODULE__{
  tokens: [integer()],
  logprobs: [float()] | nil,
  stop_reason: StopReason.t() | nil
}
```

**Perfect match** - All fields identical

---

#### 2.2.18 LoraConfig

**File:** `lora_config.ex`

```elixir
@derive {Jason.Encoder, only: [:rank, :seed, :train_mlp,
                                :train_attn, :train_unembed]}
defstruct rank: 32,  # ← Default value!
          seed: nil,
          train_mlp: true,
          train_attn: true,
          train_unembed: true

@type t :: %__MODULE__{
  rank: pos_integer(),
  seed: integer() | nil,
  train_mlp: boolean(),
  train_attn: boolean(),
  train_unembed: boolean()
}
```

**Fields:** 5 fields

**DIFFERENCE:** Elixir provides default `rank: 32`, Python requires explicit value

**Enhancement:** Elixir more ergonomic

---

#### 2.2.19 GetInfoResponse

**File:** `get_info_response.ex`

```elixir
@enforce_keys [:model_id, :model_data]
defstruct [:model_id, :model_data, :is_lora, :lora_rank,
           :model_name, :type]

@type t :: %__MODULE__{
  model_id: String.t(),
  model_data: ModelData.t(),
  is_lora: boolean() | nil,
  lora_rank: non_neg_integer() | nil,
  model_name: String.t() | nil,
  type: String.t() | nil
}
```

**Fields:** 6 fields (perfect match)

**ModelData:**
```elixir
defmodule Tinkex.Types.ModelData do
  defstruct [:arch, :model_name, :tokenizer_id]

  @type t :: %__MODULE__{
    arch: String.t() | nil,
    model_name: String.t() | nil,
    tokenizer_id: String.t() | nil
  }
end
```

**Perfect parity**

---

#### 2.2.20 CheckpointsListResponse

**File:** `checkpoints_list_response.ex`

```elixir
@type t :: %__MODULE__{
  checkpoints: [Checkpoint.t()],
  cursor: map() | nil  # ← Generic map, not Cursor.t()
}

defstruct [:checkpoints, :cursor]
```

**Fields:** 2 fields

**DIFFERENCE:** Python types cursor as `Cursor | None`, Elixir as `map() | nil`

**Minor:** Less type safety, no data loss

---

#### 2.2.21 TrainingRunsResponse

**File:** `training_runs_response.ex`

```elixir
@enforce_keys [:training_runs]
defstruct [:training_runs, :cursor]

@type t :: %__MODULE__{
  training_runs: [TrainingRun.t()],
  cursor: Cursor.t() | nil  # ← Optional in Elixir
}
```

**Fields:** 2 fields

**DIFFERENCE:** Python has `cursor: Cursor` (required), Elixir has `Cursor.t() | nil` (optional)

**Note:** Elixir more defensive (handles missing cursor)

---

#### 2.2.22 Cursor

**File:** `cursor.ex`

```elixir
@enforce_keys [:offset, :limit, :total_count]
defstruct [:offset, :limit, :total_count]

@type t :: %__MODULE__{
  offset: non_neg_integer(),
  limit: non_neg_integer(),
  total_count: non_neg_integer()
}

def from_map(nil), do: nil  # ← Defensive nil handling
```

**Perfect match** + defensive nil handling

---

#### 2.2.23 CreateModelRequest

**File:** `create_model_request.ex`

```elixir
@enforce_keys [:session_id, :model_seq_id, :base_model]
@derive {Jason.Encoder, only: [:session_id, :model_seq_id,
                                :base_model, :user_metadata,
                                :lora_config, :type]}
defstruct [
  :session_id,
  :model_seq_id,
  :base_model,
  :user_metadata,
  lora_config: %LoraConfig{},  # ← Default instance!
  type: "create_model"
]
```

**Fields:** 6 fields

**DIFFERENCE:**
1. Elixir provides default `lora_config: %LoraConfig{}`
2. Python has Optional, Elixir provides concrete default

**Enhancement:** Elixir more ergonomic

---

#### 2.2.24 SampleRequest

**File:** `sample_request.ex`

```elixir
@enforce_keys [:prompt, :sampling_params]
defstruct [
  :sampling_session_id,
  :seq_id,
  :base_model,
  :model_path,
  :prompt,
  :sampling_params,
  num_samples: 1,
  prompt_logprobs: nil,  # ← Tri-state!
  topk_prompt_logprobs: 0,
  type: "sample"
]

defimpl Jason.Encoder, for: Tinkex.Types.SampleRequest do
  def encode(request, opts) do
    # ...
    # prompt_logprobs is tri-state: true, false, or nil (omitted)
    map = if is_boolean(request.prompt_logprobs),
      do: Map.put(map, :prompt_logprobs, request.prompt_logprobs),
      else: map
    # ...
  end
end
```

**Fields:** 10 fields (perfect match)

**Critical:** Tri-state `prompt_logprobs` handled correctly

**Perfect parity** including custom encoder

---

#### 2.2.25 CheckpointArchiveUrlResponse

**File:** `checkpoint_archive_url_response.ex`

```elixir
defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @type t :: %__MODULE__{
    url: String.t()
  }
end
```

**Difference:** Python includes an `expires: datetime` field; Elixir drops it entirely, so signed-URL expirations are not exposed.

**Severity:** HIGH (P0)

---

## Part 3: Granular Type-by-Type Comparison

### 3.1 Near Parity (No Shape Differences on the Wire)

These types serialize with the same fields across SDKs (minor helper/validation differences only):

1. **SamplingParams** - identical fields and defaults
2. **SampleRequest** - tri-state `prompt_logprobs` preserved in both
3. **SampleResponse** - matching `type` literal and top-k/prompt logprob handling
4. **Cursor** - same three pagination ints (Elixir adds nil-safe `from_map/1`)
5. **ModelData** and **GetInfoResponse** - nested shape matches Python
6. **SampledSequence** - stop reason + tokens + optional logprobs (Elixir allows `stop_reason` nil)

### 3.2 DateTime vs String Differences

**Pattern:** Python uses `datetime` objects, Elixir uses `String.t()`

Affected types:
1. **TrainingRun.last_request_time** - datetime vs DateTime.t() | String.t()
2. **Checkpoint.time** - datetime vs String.t()
3. **GenericEvent.timestamp** - datetime vs String.t()
4. **SessionStartEvent.timestamp** - datetime vs String.t()
5. **SessionEndEvent.timestamp** - datetime vs String.t()
6. **UnhandledExceptionEvent.timestamp** - datetime vs String.t()

**Impact:**
- Python: Type-safe, validated datetime objects
- Elixir: String representation (ISO8601), some defensive parsing in TrainingRun

**Data Loss:** None (ISO8601 strings preserve full precision)

**Recommendation:** Standardize on either:
- Option A: Keep strings (wire format native)
- Option B: Parse all to DateTime (type safety)

---

### 3.2.1 Dropped Fields / Missing Type Literals

1. **CheckpointArchiveUrlResponse**  
   - Python: `url` + `expires: datetime`  
   - Elixir: only `url` — the signed-URL expiry is dropped (data loss, P0).

2. **Response/Request `type` literals**  
   - Python includes `type` literals on `CreateModelResponse`, `CreateSamplingSessionResponse`, `CreateSessionResponse`, and `OptimStepRequest`.  
   - Elixir omits these fields (or the request literal), so shape-sensitive downstream code cannot rely on them.

3. **TryAgainResponse extension**  
   - Elixir adds `retry_after_ms` and normalizes `queue_state` into atoms; Python only has `type/request_id/queue_state`. The extra field is benign but should be documented as an Elixir-only extension.

---

### 3.3 Nested Structure Flattening

#### 3.3.1 GetServerCapabilitiesResponse

**Python:**
```python
class SupportedModel(BaseModel):
    model_name: Optional[str] = None

class GetServerCapabilitiesResponse(BaseModel):
    supported_models: List[SupportedModel]
```

**Elixir:**
```elixir
@type t :: %__MODULE__{
  supported_models: [String.t()]
}
```

**Difference:**
- Python: List of SupportedModel objects
- Elixir: List of strings (extracted model_name)

**Data Loss:** YES
- If SupportedModel gains additional fields in future, Elixir will drop them
- Current implementation only preserves `model_name`

**Severity:** HIGH (P0)

**Fix Required:** Create SupportedModel struct in Elixir

---

#### 3.3.2 TelemetryBatch

**Python:**
```python
class TelemetryBatch(BaseModel):
    events: List[TelemetryEvent]
    platform: str
    sdk_version: str
    session_id: str
```

**Elixir:**
```elixir
@type t :: %__MODULE__{
  events: [TelemetryEvent.t()],
  metadata: map()
}
```

**Difference:**
- Python: 4 named fields
- Elixir: 2 fields (events + generic metadata map)

**Data Loss:** YES - platform/sdk_version/session_id are not represented on the Elixir struct, so those values are dropped unless carried separately alongside the batch

**Object Graph:** Different (flattened)

**Severity:** MEDIUM

**Recommendation:** Consider matching Python structure for clarity

---

#### 3.3.3 TelemetrySendRequest

**Python:**
```python
class TelemetrySendRequest(StrictBase):
    events: List[TelemetryEvent]
    platform: str
    sdk_version: str
    session_id: str
```

**Elixir:**
```elixir
@type t :: %__MODULE__{
  session_id: String.t(),
  platform: String.t(),
  sdk_version: String.t(),
  events: [TelemetryEvent.t()] | TelemetryBatch.t()
}
```

**Difference:**
- Python: events is List[TelemetryEvent]
- Elixir: events is List[TelemetryEvent] OR TelemetryBatch

**Enhancement:** Elixir more flexible (accepts batch)

**Severity:** NONE (enhancement)

---

### 3.4 Type Safety Differences

#### 3.4.1 ForwardBackwardOutput.loss_fn_outputs

**Python:**
```python
loss_fn_outputs: List[LossFnOutput]  # where LossFnOutput = Dict[str, TensorData]
```

**Elixir:**
```elixir
loss_fn_outputs: [map()]
```

**Difference:** Elixir uses generic map, Python types as Dict[str, TensorData]

**Data Loss:** NO

**Type Safety:** Python safer

**Severity:** LOW

---

#### 3.4.2 CheckpointsListResponse.cursor

**Python:**
```python
cursor: Cursor | None
```

**Elixir:**
```elixir
cursor: map() | nil
```

**Difference:** Elixir uses generic map, Python uses Cursor type

**Data Loss:** NO

**Type Safety:** Python safer

**Severity:** LOW

---

#### 3.4.3 FutureRetrieveResponse union

**Python:** `FutureRetrieveResponse` is a tagged union of typed responses (TryAgainResponse, ForwardBackwardOutput, OptimStepResponse, Save/Load/Unload responses, etc.).

**Elixir:** `future_responses.ex` models futures as status wrappers (`pending`/`completed`/`failed`) and wraps the final payload in `result` (or returns `TryAgainResponse`). Typed responses are not decoded, so callers lose the concrete shape unless they unpack `result` manually.

**Data Loss:** None on payload, but type information and the top-level shape differ.

**Severity:** MEDIUM

---

#### 3.4.4 ForwardBackwardInput.loss_fn_config

**Python:** `loss_fn_config: Optional[Dict[str, float]]`

**Elixir:** `loss_fn_config: map() | nil` (any values)

**Data Loss:** None; **Type Safety:** Python enforces numeric config values, Elixir accepts any map.

**Severity:** LOW

---

### 3.5 Optional vs Required Differences

#### 3.5.1 TrainingRunsResponse.cursor

**Python:**
```python
cursor: Cursor  # Required
```

**Elixir:**
```elixir
cursor: Cursor.t() | nil  # Optional
```

**Difference:** Python requires cursor, Elixir optional

**Defensive:** Elixir more defensive (handles missing)

**Severity:** LOW (Elixir superset)

---

#### 3.5.2 SessionEndEvent.duration

**Python:**
```python
duration: str  # Required (ISO 8601 duration)
```

**Elixir:**
```elixir
duration: String.t() | nil  # Optional
```

**Difference:** Python requires, Elixir optional

**Severity:** LOW

---

### 3.6 Default Value Differences

#### 3.6.1 LoraConfig.rank

**Python:**
```python
rank: int  # Required, no default
```

**Elixir:**
```elixir
rank: 32  # Default value
```

**Enhancement:** Elixir provides sensible default

**Severity:** NONE (ergonomic improvement)

---

#### 3.6.2 CreateModelRequest.lora_config

**Python:**
```python
lora_config: Optional[LoraConfig] = None
```

**Elixir:**
```elixir
lora_config: %LoraConfig{}  # Default instance
```

**Difference:** Elixir creates default instance, Python None

**Impact:** Different semantics (always present vs optional)

**Severity:** LOW (may affect wire format)

---

### 3.7 Missing Types in Elixir

#### 3.7.1 ParsedCheckpointTinkerPath

**Python Only:**
```python
class ParsedCheckpointTinkerPath(BaseModel):
    tinker_path: str
    training_run_id: str
    checkpoint_type: CheckpointType
    checkpoint_id: str

    @classmethod
    def from_tinker_path(cls, tinker_path: str)
```

**Elixir:** Not implemented

**Impact:** Utility for parsing tinker:// paths missing

**Severity:** LOW (utility function, not wire type)

---

### 3.8 Additional Types in Elixir

#### 3.8.1 AdamParams

**Elixir Only:**
```elixir
defmodule Tinkex.Types.AdamParams do
  # Optimizer parameters
end
```

**Python:** Not present

**Note:** Likely Elixir-specific extension

---

#### 3.8.2 QueueState

**Elixir Only:**
```elixir
defmodule Tinkex.Types.QueueState do
  # Request queue state
end
```

**Python:** Not present

**Note:** Likely Elixir-specific extension

---

### 3.9 Metadata Type Differences

#### 3.9.1 TrainingRun.user_metadata

**Python:**
```python
user_metadata: dict[str, str] | None  # String-to-string only
```

**Elixir:**
```elixir
user_metadata: map() | nil  # Any map
```

**Difference:** Python enforces str->str, Elixir allows any

**Impact:** Elixir more permissive (could accept invalid data)

**Severity:** LOW

---

#### 3.9.2 CreateModelRequest.user_metadata

**Python:**
```python
user_metadata: Optional[dict[str, Any]]  # Any values
```

**Elixir:**
```elixir
user_metadata: map() | nil  # Any map
```

**Perfect match** (both allow any values)

---

## Part 4: TDD Implementation Plan

### 4.1 Priority Ordering

#### P0 - Critical (Data Loss)

1. **GetServerCapabilitiesResponse** - Loses SupportedModel structure
   - Impact: Future fields will be dropped
   - Fix: Create SupportedModel struct

#### P1 - High (Type Safety)

2. **ForwardBackwardOutput.loss_fn_outputs** - Generic map vs typed
   - Impact: No type checking on TensorData
   - Fix: Add proper type spec

3. **CheckpointsListResponse.cursor** - Generic map vs Cursor type
   - Impact: No type checking on Cursor fields
   - Fix: Use Cursor.t() type

#### P2 - Medium (Consistency)

4. **DateTime handling** - Inconsistent across types
   - Impact: Some parse to DateTime, others keep string
   - Fix: Standardize approach

5. **TelemetryBatch structure** - Flattened metadata
   - Impact: Different object graph
   - Fix: Match Python field structure

6. **TrainingRun.last_request_time** - Defensive string fallback
   - Impact: Type becomes String.t() | DateTime.t()
   - Fix: Either always parse or always string

#### P3 - Low (Ergonomics)

7. **TrainingRunsResponse.cursor** - Optional vs required
   - Impact: More defensive (good)
   - Fix: Document difference

8. **SessionEndEvent.duration** - Optional vs required
   - Impact: More defensive (good)
   - Fix: Document difference

9. **CreateModelRequest.lora_config** - Default instance vs None
   - Impact: Different wire format
   - Fix: Match Python (None default)

10. **Missing ParsedCheckpointTinkerPath**
    - Impact: Missing utility
    - Fix: Implement if needed

---

### 4.2 Test Plan for Each Type

#### 4.2.1 GetServerCapabilitiesResponse

**Unit Tests:**

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponseTest do
  use ExUnit.Case

  describe "from_json/1" do
    test "parses list of SupportedModel structs" do
      json = %{
        "supported_models" => [
          %{"model_name" => "llama-3.1-8b"},
          %{"model_name" => "mistral-7b"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      assert [%SupportedModel{model_name: "llama-3.1-8b"},
              %SupportedModel{model_name: "mistral-7b"}] = response.supported_models
    end

    test "preserves future SupportedModel fields" do
      json = %{
        "supported_models" => [
          %{
            "model_name" => "llama-3.1-8b",
            "future_field" => "future_value",  # New field
            "capabilities" => ["training", "sampling"]  # New field
          }
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)
      model = hd(response.supported_models)

      # Should preserve all fields
      assert model.model_name == "llama-3.1-8b"
      assert model.future_field == "future_value"
      assert model.capabilities == ["training", "sampling"]
    end
  end
end
```

**Property-Based Test:**

```elixir
property "round-trip preserves all fields" do
  check all models <- list_of(supported_model_generator(), min_length: 1) do
    json = %{"supported_models" => Enum.map(models, &to_json/1)}

    parsed = GetServerCapabilitiesResponse.from_json(json)
    re_encoded = to_json(parsed)

    assert re_encoded == json
  end
end
```

---

#### 4.2.2 TelemetryBatch

**Unit Tests:**

```elixir
defmodule Tinkex.Types.Telemetry.TelemetryBatchTest do
  use ExUnit.Case

  describe "from_json/1" do
    test "parses structured fields instead of metadata map" do
      json = %{
        "events" => [
          %{"event" => "session_start", "event_id" => "1", ...}
        ],
        "platform" => "elixir",
        "sdk_version" => "0.1.0",
        "session_id" => "sess_123"
      }

      batch = TelemetryBatch.from_json(json)

      assert batch.platform == "elixir"
      assert batch.sdk_version == "0.1.0"
      assert batch.session_id == "sess_123"
      assert length(batch.events) == 1
    end

    test "to_json/1 produces correct wire format" do
      batch = %TelemetryBatch{
        events: [...],
        platform: "elixir",
        sdk_version: "0.1.0",
        session_id: "sess_123"
      }

      json = TelemetryBatch.to_json(batch)

      assert json["platform"] == "elixir"
      assert json["sdk_version"] == "0.1.0"
      assert json["session_id"] == "sess_123"
    end
  end
end
```

---

#### 4.2.3 DateTime Standardization

**Unit Tests:**

```elixir
defmodule Tinkex.Types.DateTimeParsingTest do
  use ExUnit.Case

  @moduletag :datetime_parsing

  describe "TrainingRun.last_request_time" do
    test "always parses to DateTime.t()" do
      json = %{
        "training_run_id" => "run_123",
        "last_request_time" => "2025-11-27T12:00:00Z",
        ...
      }

      run = TrainingRun.from_map(json)

      assert %DateTime{} = run.last_request_time
      assert run.last_request_time.year == 2025
    end

    test "raises on invalid ISO8601" do
      json = %{
        "training_run_id" => "run_123",
        "last_request_time" => "invalid",
        ...
      }

      assert_raise ArgumentError, fn ->
        TrainingRun.from_map(json)
      end
    end
  end

  describe "Checkpoint.time" do
    test "always parses to DateTime.t()" do
      json = %{
        "checkpoint_id" => "ckpt_123",
        "time" => "2025-11-27T12:00:00Z",
        ...
      }

      checkpoint = Checkpoint.from_map(json)

      assert %DateTime{} = checkpoint.time
    end
  end

  describe "GenericEvent.timestamp" do
    test "always parses to DateTime.t()" do
      json = %{
        "event" => "generic_event",
        "timestamp" => "2025-11-27T12:00:00Z",
        ...
      }

      event = GenericEvent.from_map(json)

      assert %DateTime{} = event.timestamp
    end
  end
end
```

**Property-Based Test:**

```elixir
property "all datetime fields parse valid ISO8601" do
  check all datetime_str <- iso8601_string_generator() do
    # Test across all types with datetime fields
    types_with_datetime = [
      {TrainingRun, "last_request_time"},
      {Checkpoint, "time"},
      {GenericEvent, "timestamp"},
      {SessionStartEvent, "timestamp"},
      {SessionEndEvent, "timestamp"},
      {UnhandledExceptionEvent, "timestamp"}
    ]

    for {module, field} <- types_with_datetime do
      json = Map.put(minimal_json(module), field, datetime_str)
      parsed = module.from_map(json)

      assert %DateTime{} = Map.get(parsed, String.to_atom(field))
    end
  end
end
```

---

#### 4.2.4 ForwardBackwardOutput Type Safety

**Unit Tests:**

```elixir
defmodule Tinkex.Types.ForwardBackwardOutputTest do
  use ExUnit.Case

  describe "loss_fn_outputs type safety" do
    test "parses to list of LossFnOutput (Dict[str, TensorData])" do
      json = %{
        "loss_fn_output_type" => "custom",
        "loss_fn_outputs" => [
          %{
            "field1" => %{"data" => [1.0, 2.0], "dtype" => "float32"},
            "field2" => %{"data" => [3, 4], "dtype" => "int64"}
          }
        ],
        "metrics" => %{"loss" => 0.5}
      }

      output = ForwardBackwardOutput.from_json(json)

      assert [loss_fn_output] = output.loss_fn_outputs
      assert %TensorData{} = loss_fn_output["field1"]
      assert %TensorData{} = loss_fn_output["field2"]
    end

    test "validates all values are TensorData" do
      json = %{
        "loss_fn_output_type" => "custom",
        "loss_fn_outputs" => [
          %{"field1" => "not a tensor"}  # Invalid
        ]
      }

      assert_raise ArgumentError, fn ->
        ForwardBackwardOutput.from_json(json)
      end
    end
  end
end
```

---

#### 4.2.5 Round-Trip Tests (All Types)

**Property-Based Test Template:**

```elixir
defmodule Tinkex.Types.RoundTripTest do
  use ExUnit.Case
  use ExUnitProperties

  @types [
    Tinkex.Types.GetServerCapabilitiesResponse,
    Tinkex.Types.TelemetryBatch,
    Tinkex.Types.TrainingRun,
    Tinkex.Types.Checkpoint,
    Tinkex.Types.CreateSessionResponse,
    Tinkex.Types.SamplingParams,
    # ... all types
  ]

  for type <- @types do
    @type type

    property "#{inspect(type)} round-trip preserves data" do
      check all json <- json_generator(@type) do
        parsed = @type.from_json(json)
        re_encoded = @type.to_json(parsed)
        re_parsed = @type.from_json(re_encoded)

        # Should be equal after round-trip
        assert parsed == re_parsed
      end
    end
  end
end
```

---

### 4.3 Migration Strategy

#### Phase 1: Critical Fixes (Week 1)

1. **GetServerCapabilitiesResponse** (P0)
   - Create `SupportedModel` struct
   - Update parsing logic
   - Add tests
   - Update docs

2. **CheckpointArchiveUrlResponse** (P0)
   - Add `expires` field (DateTime.t()) and keep backwards compatibility with existing callers
   - Add decode/encode coverage to ensure the expiry timestamp is preserved

**Steps:**
```elixir
# 1. Define SupportedModel
defmodule Tinkex.Types.SupportedModel do
  @enforce_keys [:model_name]
  defstruct [:model_name]

  @type t :: %__MODULE__{
    model_name: String.t()
  }

  def from_json(json) when is_map(json) do
    %__MODULE__{model_name: json["model_name"]}
  end

  def from_json(name) when is_binary(name) do
    %__MODULE__{model_name: name}
  end
end

# 2. Update GetServerCapabilitiesResponse
defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  alias Tinkex.Types.SupportedModel

  @type t :: %__MODULE__{
    supported_models: [SupportedModel.t()]
  }

  def from_json(map) do
    models = map["supported_models"] || []

    %__MODULE__{
      supported_models: Enum.map(models, &SupportedModel.from_json/1)
    }
  end
end
```

---

#### Phase 2: Type Safety (Week 2)

1. **ForwardBackwardOutput.loss_fn_outputs**
   - Define `LossFnOutput` type
   - Add parsing to TensorData
   - Add validation

2. **CheckpointsListResponse.cursor**
   - Change type from `map()` to `Cursor.t()`
   - Update parsing

**Steps:**
```elixir
# 1. Define LossFnOutput type alias
defmodule Tinkex.Types.LossFnOutput do
  @type t :: %{String.t() => Tinkex.Types.TensorData.t()}
end

# 2. Update ForwardBackwardOutput
@type t :: %__MODULE__{
  loss_fn_output_type: String.t(),
  loss_fn_outputs: [Tinkex.Types.LossFnOutput.t()],
  metrics: %{String.t() => float()}
}

def from_json(json) do
  %__MODULE__{
    loss_fn_output_type: json["loss_fn_output_type"],
    loss_fn_outputs: parse_loss_fn_outputs(json["loss_fn_outputs"] || []),
    metrics: json["metrics"] || %{}
  }
end

defp parse_loss_fn_outputs(outputs) when is_list(outputs) do
  Enum.map(outputs, fn output_map ->
    Map.new(output_map, fn {k, v} ->
      {k, parse_tensor_data(v)}
    end)
  end)
end

defp parse_tensor_data(%{"data" => _, "dtype" => _} = json) do
  TensorData.from_json(json)
end
```

---

#### Phase 3: Consistency (Week 3)

1. **DateTime standardization**
   - Decide on approach (always DateTime or always String)
   - If DateTime: Add parse_datetime helper
   - Update all types
   - Add comprehensive tests

**Recommended Approach:**

```elixir
# lib/tinkex/types/datetime_parser.ex
defmodule Tinkex.Types.DateTimeParser do
  @moduledoc """
  Centralized DateTime parsing for all Tinkex types.
  """

  @doc """
  Parse ISO8601 string to DateTime, raising on failure.
  """
  @spec parse!(String.t()) :: DateTime.t()
  def parse!(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, reason} ->
        raise ArgumentError,
          "Invalid ISO8601 datetime: #{str} (#{inspect(reason)})"
    end
  end

  def parse!(%DateTime{} = dt), do: dt

  @doc """
  Parse ISO8601 string to DateTime, returning nil on failure.
  """
  @spec parse(String.t() | nil) :: DateTime.t() | nil
  def parse(nil), do: nil
  def parse(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end
  def parse(%DateTime{} = dt), do: dt
end

# Update all types to use centralized parser
defmodule Tinkex.Types.TrainingRun do
  alias Tinkex.Types.DateTimeParser

  @type t :: %__MODULE__{
    last_request_time: DateTime.t(),  # Always DateTime!
    ...
  }

  def from_map(map) do
    %__MODULE__{
      last_request_time: DateTimeParser.parse!(fetch(map, "last_request_time")),
      ...
    }
  end
end
```

2. **TelemetryBatch structure**
   - Add explicit platform, sdk_version, session_id fields
   - Remove metadata map
   - Update from_json/to_json

3. **FutureRetrieveResponse decoding**
   - Preserve the Python union shape or decode into typed payloads inside the status wrapper so callers do not have to pattern-match raw maps

4. **Restore `type` literals where the API emits them**
   - `CreateModelResponse`, `CreateSamplingSessionResponse`, `CreateSessionResponse`, `OptimStepRequest`

---

#### Phase 4: Completeness (Week 4)

1. **Missing types**
   - Implement ParsedCheckpointTinkerPath
   - Document Elixir-specific types (AdamParams, QueueState)

2. **Documentation**
   - Update CHANGELOG
   - Update API docs
   - Add migration guide

---

### 4.4 Backward Compatibility

**Strategy:** Dual parsers during transition

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @doc """
  Parse from JSON with backward compatibility.

  Supports both:
  - Old format: List of strings
  - New format: List of SupportedModel maps
  """
  def from_json(map, opts \\ []) do
    models = map["supported_models"] || []

    parsed_models = if Keyword.get(opts, :legacy, false) do
      # Legacy: extract strings
      Enum.map(models, fn
        %{"model_name" => name} -> name
        name when is_binary(name) -> name
      end)
    else
      # New: parse to structs
      Enum.map(models, &SupportedModel.from_json/1)
    end

    %__MODULE__{supported_models: parsed_models}
  end
end
```

**Deprecation Timeline:**
- Week 1-2: Introduce new types, keep legacy parser
- Week 3-4: Add deprecation warnings
- Week 5+: Remove legacy support (major version bump)

---

### 4.5 CI/CD Integration

**Add to test suite:**

```yaml
# .github/workflows/test.yml
- name: Run type parity tests
  run: mix test --only type_parity

- name: Run property-based tests
  run: mix test --only property

- name: Run round-trip tests
  run: mix test --only round_trip
```

**Test tags:**
```elixir
@tag :type_parity
test "GetServerCapabilitiesResponse matches Python shape" do
  # ...
end

@tag :property
property "round-trip preserves data" do
  # ...
end

@tag :round_trip
test "JSON encode/decode cycle" do
  # ...
end
```

---

## Part 5: Summary Tables

### 5.1 Type Difference Summary

| Type | Python Fields | Elixir Fields | Status | Data Loss | Priority |
|------|---------------|---------------|--------|-----------|----------|
| CheckpointArchiveUrlResponse | url + expires: datetime | url only | DIFF | YES | P0 |
| GetServerCapabilitiesResponse | List[SupportedModel] | [String.t()] | DIFF | YES | P0 |
| TelemetryBatch | events + platform/sdk_version/session_id | events + metadata map (no platform/sdk/session fields) | DIFF | YES (metadata fields dropped) | P2 |
| FutureRetrieveResponse | Union of typed responses | Status wrappers + raw `result` map | DIFF | NO | P1 |
| TrainingRun | last_request_time: datetime | DateTime \| String | DIFF | NO | P2 |
| Checkpoint | time: datetime | time: String | DIFF | NO | P2 |
| GenericEvent | timestamp: datetime | timestamp: String | DIFF | NO | P2 |
| SessionStartEvent | timestamp: datetime | timestamp: String | DIFF | NO | P2 |
| SessionEndEvent | timestamp: datetime | timestamp: String (+duration optional) | DIFF | NO | P2 |
| UnhandledExceptionEvent | timestamp: datetime | timestamp: String | DIFF | NO | P2 |
| ForwardBackwardOutput | loss_fn_outputs: List[Dict[str, TensorData]] | [map()] | DIFF | NO | P1 |
| CheckpointsListResponse | cursor: Cursor \| None | cursor: map() \| nil | DIFF | NO | P1 |
| TrainingRunsResponse | cursor: Cursor | cursor: Cursor \| nil | DIFF | NO | P3 |
| ForwardBackwardInput | loss_fn_config: Dict[str, float] \| None | map() \| nil | DIFF | NO | P3 |
| CreateModelRequest | lora_config: Optional | lora_config: default struct | DIFF | NO | P3 |
| LoraConfig | rank required | rank defaults to 32 | DIFF | NO | P3 |
| CreateModelResponse | model_id + type literal | model_id only | DIFF | YES (type literal missing) | P2 |
| CreateSamplingSessionResponse | sampling_session_id + type literal | sampling_session_id only | DIFF | YES (type literal missing) | P2 |
| CreateSessionResponse | type literal + message fields | message fields only | DIFF | YES (type literal missing) | P3 |
| OptimStepRequest | adam_params + model_id + seq_id + type literal | adam_params + model_id + seq_id | DIFF | YES (type literal missing) | P2 |
| SamplingParams | - | - | MATCH | NO | - |
| SampleRequest | - | - | MATCH | NO | - |

### 5.2 DateTime Field Inventory

| Type | Field | Python Type | Elixir Type | Recommended |
|------|-------|-------------|-------------|-------------|
| TrainingRun | last_request_time | datetime | DateTime \| String | DateTime.t() |
| Checkpoint | time | datetime | String.t() | DateTime.t() |
| GenericEvent | timestamp | datetime | String.t() | DateTime.t() |
| SessionStartEvent | timestamp | datetime | String.t() | DateTime.t() |
| SessionEndEvent | timestamp | datetime | String.t() | DateTime.t() |
| UnhandledExceptionEvent | timestamp | datetime | String.t() | DateTime.t() |

**Total:** 6 types with datetime fields, all should parse to DateTime.t()

### 5.3 Nested Structure Inventory

| Type | Python Nesting | Elixir Nesting | Match |
|------|----------------|----------------|-------|
| GetServerCapabilitiesResponse | List[SupportedModel] | List[String] | NO |
| GetInfoResponse | contains ModelData | contains ModelData | YES |
| TrainingRun | contains Checkpoint | contains Checkpoint | YES |
| CheckpointsListResponse | List[Checkpoint] + Cursor | List[Checkpoint] + map | PARTIAL |
| TrainingRunsResponse | List[TrainingRun] + Cursor | List[TrainingRun] + Cursor | YES |
| TelemetryBatch | 4 fields | 2 fields + metadata | NO |
| ModelInput | List[ModelInputChunk] | List[chunk union] | YES |
| Datum | ModelInput + LossFnInputs | ModelInput + map | YES |
| ForwardBackwardOutput | List[LossFnOutput] | List[map()] | PARTIAL |

**Nested Types Needing Attention:**
1. GetServerCapabilitiesResponse (SupportedModel missing)
2. TelemetryBatch (flattened structure)
3. ForwardBackwardOutput (untyped maps)
4. CheckpointsListResponse (cursor untyped)

---

## Conclusion

### Key Findings

1. **73 Python modules analyzed**, **72 Elixir modules**
2. **2 critical data-loss gaps**: `CheckpointArchiveUrlResponse` drops `expires`; `GetServerCapabilitiesResponse` flattens `SupportedModel`
3. **6 types** ship datetime fields as strings in Elixir
4. **Type-safety/shape gaps**: future retrieve status wrapper vs typed union, untyped `loss_fn_outputs/cursor/loss_fn_config`, telemetry batch metadata fields missing, several responses/requests omit Python `type` literals
5. **Sampling/tensor wire formats** are already aligned (tri-state `prompt_logprobs`, `TensorData`, `ModelInput` chunk union)

### Recommendations

**Immediate Actions:**
1. Add `expires` to `CheckpointArchiveUrlResponse` and keep it as `DateTime.t()` (P0)
2. Create `SupportedModel` struct and preserve the list shape in `GetServerCapabilitiesResponse` (P0)
3. Tighten type safety: parse datetime fields consistently, type `loss_fn_outputs`/`cursor`/`loss_fn_config`, and restore missing `type` literals where the API emits them (P1)

**Medium-term:**
4. Align `TelemetryBatch` shape (platform/sdk_version/session_id) and consider decoding typed `FutureRetrieveResponse` payloads
5. Document Elixir-only extensions (`retry_after_ms`, defaults on `lora_config`/`lora_rank`)
6. Add comprehensive round-trip/type-parity tests

**Long-term:**
7. Consider code generation from shared schema
8. Establish type parity CI checks
9. Version alignment strategy

### Success Metrics

 - [ ] Zero P0 data-loss types (currently 2; minor field drops remain for literals/telemetry batch)
- [ ] Consistent datetime handling (currently 6 inconsistent)
- [ ] 100% round-trip test coverage
- [ ] Type parity documentation complete
- [ ] Migration guide published

---

**End of Report**

Generated: 2025-11-27
Total Analysis Time: ~3 hours
Types Analyzed: 145 (73 Python + 72 Elixir)
Critical Issues: 2
Medium Issues: 13
Minor Issues: 5
