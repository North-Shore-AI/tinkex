# Gap Analysis: Types - Telemetry & Events

**Analysis Date:** 2025-11-26
**Domain:** Telemetry event types, severity levels, and async future types
**Analyst:** Claude Code (Sonnet 4.5)

---

## 1. Executive Summary

### Overall Assessment
- **Completeness:** ~60% (partial implementation with significant gaps)
- **Critical Gaps:** 9
- **High Priority Gaps:** 5
- **Medium Priority Gaps:** 3
- **Low Priority Gaps:** 2

### Key Findings

**Strengths:**
- ✅ Core telemetry infrastructure exists (`Tinkex.Telemetry.Reporter`)
- ✅ Session start/end events implemented
- ✅ Exception event handling implemented
- ✅ Generic event support exists
- ✅ Queue state types and handling complete
- ✅ Request error category implemented
- ✅ TryAgain response implemented
- ✅ Future retrieve/polling infrastructure complete

**Critical Gaps:**
- ❌ No dedicated typed structs for telemetry events (uses maps instead)
- ❌ No `EventType` enum module
- ❌ No `Severity` enum module
- ❌ No `TelemetryEvent` union type
- ❌ No `TelemetryBatch` struct
- ❌ No `TelemetrySendRequest` struct
- ❌ No `TelemetryResponse` struct
- ❌ No `UntypedAPIFuture` struct
- ❌ Missing `FutureRetrieveRequest` struct

### Architecture Difference

**Python Approach:**
- Strongly typed Pydantic models for all telemetry structures
- Explicit union types for event polymorphism
- Separate request/response types
- Type-safe event type and severity enums

**Elixir Current Approach:**
- Uses plain maps for event encoding
- Event types encoded as strings ("SESSION_START", "GENERIC_EVENT", etc.)
- Severity levels as uppercase strings ("INFO", "ERROR", etc.)
- No compile-time type safety for event structures
- Focus on runtime flexibility over compile-time guarantees

---

## 2. Type-by-Type Comparison

### Telemetry Event Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `SessionStartEvent` | 6 fields (event, event_id, event_session_index, severity, timestamp) | Map (inline) | ❌ No struct | **CRITICAL** |
| `SessionEndEvent` | 7 fields (+ duration) | Map (inline) | ❌ No struct | **CRITICAL** |
| `UnhandledExceptionEvent` | 9 fields (error_message, error_type, traceback, etc.) | Map (inline) | ❌ No struct | **CRITICAL** |
| `GenericEvent` | 8 fields (event_name, event_data, etc.) | Map (inline) | ❌ No struct | **CRITICAL** |
| `TelemetryEvent` (union) | Union of 4 event types | N/A | ❌ No union | **CRITICAL** |

### Telemetry Request/Response Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `TelemetryBatch` | 4 (events, platform, sdk_version, session_id) | Map (inline) | ❌ No struct | **HIGH** |
| `TelemetrySendRequest` | 4 (same as batch) | Map (inline) | ❌ No struct | **HIGH** |
| `TelemetryResponse` | 1 (status: "accepted") | N/A | ❌ Missing | **MEDIUM** |

### Enum Types

| Python Type | Values | Elixir Type | Values Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `EventType` | 4 literals | String constants | ✅ Functional | **HIGH** (no module) |
| `Severity` | 5 literals | String constants | ✅ Functional | **HIGH** (no module) |

### Error and Queue Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `RequestErrorCategory` | 3 enum values | `Tinkex.Types.RequestErrorCategory` | ✅ Complete | ✅ **NONE** |
| `RequestFailedResponse` | 2 (error, category) | Map (inline) | ❌ No struct | **MEDIUM** |
| `TryAgainResponse` | 3 (type, request_id, queue_state) | `Tinkex.Types.TryAgainResponse` | ✅ Complete | ✅ **NONE** |
| N/A (implicit) | N/A | `Tinkex.Types.QueueState` | ✅ Complete | ✅ **NONE** |

### Future Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `UntypedAPIFuture` | 2 (request_id, model_id?) | Map (inline) | ❌ No struct | **MEDIUM** |
| `FutureRetrieveRequest` | 1 (request_id) | Map (inline) | ❌ No struct | **LOW** |
| `FutureRetrieveResponse` | Union of 9 types | `Tinkex.Types.FutureRetrieveResponse` | ✅ Complete | ✅ **NONE** |

---

## 3. Detailed Gap Analysis

### GAP-TELEM-001: Missing EventType Enum Module
**Severity:** CRITICAL
**Category:** Type Safety

**Python Implementation:**
```python
# tinker/types/event_type.py
from typing_extensions import Literal, TypeAlias

EventType: TypeAlias = Literal[
    "SESSION_START",
    "SESSION_END",
    "UNHANDLED_EXCEPTION",
    "GENERIC_EVENT"
]
```

**Elixir Status:**
- No dedicated `Tinkex.Types.EventType` module
- Event types hardcoded as strings in `Reporter.ex`:
  - `"SESSION_START"` (line 468)
  - `"SESSION_END"` (line 483)
  - `"UNHANDLED_EXCEPTION"` (line 564)
  - `"GENERIC_EVENT"` (line 447)

**What's Missing:**
1. No compile-time enumeration of valid event types
2. No parser function for wire format
3. No type spec for event type atom/string
4. No validation of event type values

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.EventType do
  @moduledoc """
  Telemetry event type enumeration.

  Mirrors Python tinker.types.event_type.EventType.
  Wire format uses uppercase strings.
  """

  @type t :: :session_start | :session_end | :unhandled_exception | :generic_event

  @spec parse(String.t() | nil) :: t()
  def parse("SESSION_START"), do: :session_start
  def parse("SESSION_END"), do: :session_end
  def parse("UNHANDLED_EXCEPTION"), do: :unhandled_exception
  def parse("GENERIC_EVENT"), do: :generic_event
  def parse(_), do: :generic_event  # Default

  @spec to_string(t()) :: String.t()
  def to_string(:session_start), do: "SESSION_START"
  def to_string(:session_end), do: "SESSION_END"
  def to_string(:unhandled_exception), do: "UNHANDLED_EXCEPTION"
  def to_string(:generic_event), do: "GENERIC_EVENT"
end
```

---

### GAP-TELEM-002: Missing Severity Enum Module
**Severity:** CRITICAL
**Category:** Type Safety

**Python Implementation:**
```python
# tinker/types/severity.py
from typing_extensions import Literal, TypeAlias

Severity: TypeAlias = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
```

**Elixir Status:**
- No dedicated `Tinkex.Types.Severity` module
- Severity levels hardcoded throughout `Reporter.ex`
- Type spec exists: `@type severity :: :debug | :info | :warning | :error | :critical | String.t()` (line 42)
- Conversion function exists but not in dedicated module (lines 613-617)

**What's Missing:**
1. Dedicated module for severity enumeration
2. Parser function for wire format
3. Centralized validation
4. Documentation of severity semantics

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.Severity do
  @moduledoc """
  Log severity level enumeration.

  Mirrors Python tinker.types.severity.Severity.
  Wire format uses uppercase strings: "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
  """

  @type t :: :debug | :info | :warning | :error | :critical

  @spec parse(String.t() | atom() | nil) :: t()
  def parse(value) when is_atom(value) and value in [:debug, :info, :warning, :error, :critical] do
    value
  end

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "error" -> :error
      "critical" -> :critical
      _ -> :info  # Default
    end
  end

  def parse(_), do: :info

  @spec to_string(t()) :: String.t()
  def to_string(:debug), do: "DEBUG"
  def to_string(:info), do: "INFO"
  def to_string(:warning), do: "WARNING"
  def to_string(:error), do: "ERROR"
  def to_string(:critical), do: "CRITICAL"

  @spec level(t()) :: non_neg_integer()
  def level(:debug), do: 0
  def level(:info), do: 1
  def level(:warning), do: 2
  def level(:error), do: 3
  def level(:critical), do: 4
end
```

---

### GAP-TELEM-003: Missing SessionStartEvent Struct
**Severity:** CRITICAL
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/session_start_event.py
class SessionStartEvent(BaseModel):
    event: EventType                # "SESSION_START"
    event_id: str
    event_session_index: int
    severity: Severity              # "INFO"
    timestamp: datetime
```

**Elixir Status:**
- Built inline in `Reporter.build_session_start_event/1` (lines 464-476)
- Returns plain map: `%{event: "SESSION_START", event_id: ..., ...}`
- No struct definition
- No validation of field types

**What's Missing:**
1. Typed struct with enforced keys
2. Field validation
3. Builder/constructor function
4. JSON encoding/decoding

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.SessionStartEvent do
  @moduledoc """
  Session start telemetry event.

  Emitted when a telemetry reporter initializes for a new session.
  """

  alias Tinkex.Types.{EventType, Severity}

  @enforce_keys [:event, :event_id, :event_session_index, :severity, :timestamp]
  defstruct [:event, :event_id, :event_session_index, :severity, :timestamp]

  @type t :: %__MODULE__{
    event: EventType.t(),
    event_id: String.t(),
    event_session_index: non_neg_integer(),
    severity: Severity.t(),
    timestamp: DateTime.t()
  }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      event: :session_start,
      event_id: Keyword.fetch!(opts, :event_id),
      event_session_index: Keyword.fetch!(opts, :event_session_index),
      severity: Keyword.get(opts, :severity, :info),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "event" => EventType.to_string(event.event),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => DateTime.to_iso8601(event.timestamp)
    }
  end
end
```

---

### GAP-TELEM-004: Missing SessionEndEvent Struct
**Severity:** CRITICAL
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/session_end_event.py
class SessionEndEvent(BaseModel):
    duration: str                   # ISO 8601 duration string
    event: EventType                # "SESSION_END"
    event_id: str
    event_session_index: int
    severity: Severity              # "INFO"
    timestamp: datetime
```

**Elixir Status:**
- Built inline in `Reporter.build_session_end_event/1` (lines 478-492)
- Returns plain map with duration calculation
- Duration formatted as `"HH:MM:SS.uuuuuu"` (lines 647-661)
- No struct definition

**What's Missing:**
1. Typed struct
2. ISO 8601 duration format validation
3. Builder function separate from Reporter

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.SessionEndEvent do
  @moduledoc """
  Session end telemetry event.

  Emitted when a telemetry reporter gracefully shuts down.
  Duration is an ISO 8601 duration string (e.g., "PT1H23M45.678901S").
  """

  alias Tinkex.Types.{EventType, Severity}

  @enforce_keys [:event, :event_id, :event_session_index, :severity, :timestamp, :duration]
  defstruct [:event, :event_id, :event_session_index, :severity, :timestamp, :duration]

  @type t :: %__MODULE__{
    event: EventType.t(),
    event_id: String.t(),
    event_session_index: non_neg_integer(),
    severity: Severity.t(),
    timestamp: DateTime.t(),
    duration: String.t()  # ISO 8601 duration
  }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      event: :session_end,
      event_id: Keyword.fetch!(opts, :event_id),
      event_session_index: Keyword.fetch!(opts, :event_session_index),
      severity: Keyword.get(opts, :severity, :info),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      duration: Keyword.fetch!(opts, :duration)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "event" => EventType.to_string(event.event),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "duration" => event.duration
    }
  end
end
```

**Note:** Current Elixir duration format differs from ISO 8601. Python likely expects format like `"PT1H23M45.678901S"` but Elixir produces `"1:23:45.678901"`. Need to verify/fix.

---

### GAP-TELEM-005: Missing UnhandledExceptionEvent Struct
**Severity:** CRITICAL
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/unhandled_exception_event.py
class UnhandledExceptionEvent(BaseModel):
    error_message: str
    error_type: str
    event: EventType                    # "UNHANDLED_EXCEPTION"
    event_id: str
    event_session_index: int
    severity: Severity
    timestamp: datetime
    traceback: Optional[str] = None     # Optional Python traceback
```

**Elixir Status:**
- Built inline in `Reporter.build_unhandled_exception/3` (lines 559-575)
- Returns plain map with all required fields
- Traceback formatting exists (lines 670-704)
- No struct definition

**What's Missing:**
1. Typed struct
2. Optional traceback handling (already implemented inline)
3. Separation from Reporter internals

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.UnhandledExceptionEvent do
  @moduledoc """
  Unhandled exception telemetry event.

  Captures unexpected exceptions during session execution.
  """

  alias Tinkex.Types.{EventType, Severity}

  @enforce_keys [:event, :event_id, :event_session_index, :severity, :timestamp,
                 :error_type, :error_message]
  defstruct [:event, :event_id, :event_session_index, :severity, :timestamp,
             :error_type, :error_message, :traceback]

  @type t :: %__MODULE__{
    event: EventType.t(),
    event_id: String.t(),
    event_session_index: non_neg_integer(),
    severity: Severity.t(),
    timestamp: DateTime.t(),
    error_type: String.t(),
    error_message: String.t(),
    traceback: String.t() | nil
  }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      event: :unhandled_exception,
      event_id: Keyword.fetch!(opts, :event_id),
      event_session_index: Keyword.fetch!(opts, :event_session_index),
      severity: Keyword.get(opts, :severity, :error),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      error_type: Keyword.fetch!(opts, :error_type),
      error_message: Keyword.fetch!(opts, :error_message),
      traceback: Keyword.get(opts, :traceback)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    base = %{
      "event" => EventType.to_string(event.event),
      "event_id" => event.event_id,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "error_type" => event.error_type,
      "error_message" => event.error_message
    }

    case event.traceback do
      nil -> base
      traceback -> Map.put(base, "traceback", traceback)
    end
  end
end
```

---

### GAP-TELEM-006: Missing GenericEvent Struct
**Severity:** CRITICAL
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/generic_event.py
class GenericEvent(BaseModel):
    event: EventType                     # "GENERIC_EVENT"
    event_id: str
    event_name: str                      # Low-cardinality event name
    event_session_index: int
    severity: Severity
    timestamp: datetime
    event_data: Dict[str, object] = {}   # Arbitrary JSON payload
```

**Elixir Status:**
- Built inline in `Reporter.build_generic_event/4` (lines 443-457)
- Returns plain map with sanitized event_data
- Sanitization implemented (lines 622-634)
- No struct definition

**What's Missing:**
1. Typed struct
2. Event name validation (low cardinality enforcement)
3. Data sanitization documentation

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.GenericEvent do
  @moduledoc """
  Generic telemetry event with arbitrary structured data.

  Used for application-specific events. `event_name` should be low-cardinality
  (e.g., "http.request", "cache.hit") to enable effective aggregation.
  `event_data` can contain any JSON-serializable payload.
  """

  alias Tinkex.Types.{EventType, Severity}

  @enforce_keys [:event, :event_id, :event_name, :event_session_index,
                 :severity, :timestamp]
  defstruct [:event, :event_id, :event_name, :event_session_index,
             :severity, :timestamp, event_data: %{}]

  @type t :: %__MODULE__{
    event: EventType.t(),
    event_id: String.t(),
    event_name: String.t(),
    event_session_index: non_neg_integer(),
    severity: Severity.t(),
    timestamp: DateTime.t(),
    event_data: map()
  }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      event: :generic_event,
      event_id: Keyword.fetch!(opts, :event_id),
      event_name: Keyword.fetch!(opts, :event_name),
      event_session_index: Keyword.fetch!(opts, :event_session_index),
      severity: Keyword.get(opts, :severity, :info),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      event_data: Keyword.get(opts, :event_data, %{})
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "event" => EventType.to_string(event.event),
      "event_id" => event.event_id,
      "event_name" => event.event_name,
      "event_session_index" => event.event_session_index,
      "severity" => Severity.to_string(event.severity),
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "event_data" => event.event_data
    }
  end
end
```

---

### GAP-TELEM-007: Missing TelemetryEvent Union Type
**Severity:** CRITICAL
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/telemetry_event.py
from typing import Union
from typing_extensions import TypeAlias

TelemetryEvent: TypeAlias = Union[
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent,
    GenericEvent
]
```

**Elixir Status:**
- No union type definition
- Events built as maps and added to queue
- No polymorphic type enforcement

**What's Missing:**
1. Union type specification
2. Type guard functions
3. Polymorphic encoding/decoding

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.TelemetryEvent do
  @moduledoc """
  Union type for all telemetry events.

  Mirrors Python tinker.types.telemetry_event.TelemetryEvent.
  """

  alias Tinkex.Types.{
    SessionStartEvent,
    SessionEndEvent,
    UnhandledExceptionEvent,
    GenericEvent
  }

  @type t ::
    SessionStartEvent.t()
    | SessionEndEvent.t()
    | UnhandledExceptionEvent.t()
    | GenericEvent.t()

  @spec to_map(t()) :: map()
  def to_map(%SessionStartEvent{} = event), do: SessionStartEvent.to_map(event)
  def to_map(%SessionEndEvent{} = event), do: SessionEndEvent.to_map(event)
  def to_map(%UnhandledExceptionEvent{} = event), do: UnhandledExceptionEvent.to_map(event)
  def to_map(%GenericEvent{} = event), do: GenericEvent.to_map(event)

  @spec from_map(map()) :: t()
  def from_map(%{"event" => "SESSION_START"} = map) do
    # Parse and construct SessionStartEvent
    # Implementation depends on struct definition
  end

  def from_map(%{"event" => "SESSION_END"} = map) do
    # Parse and construct SessionEndEvent
  end

  def from_map(%{"event" => "UNHANDLED_EXCEPTION"} = map) do
    # Parse and construct UnhandledExceptionEvent
  end

  def from_map(%{"event" => "GENERIC_EVENT"} = map) do
    # Parse and construct GenericEvent
  end

  def from_map(_), do: raise(ArgumentError, "Invalid telemetry event")
end
```

---

### GAP-TELEM-008: Missing TelemetryBatch Struct
**Severity:** HIGH
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/telemetry_batch.py
class TelemetryBatch(BaseModel):
    events: List[TelemetryEvent]
    platform: str                    # Host platform name
    sdk_version: str                 # SDK version string
    session_id: str
```

**Elixir Status:**
- Built inline in `Reporter.build_request/2` (lines 434-441)
- Returns plain map
- No struct definition

**What's Missing:**
1. Typed struct
2. Event list validation
3. Platform/version validation

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.TelemetryBatch do
  @moduledoc """
  Batch of telemetry events sent to the backend.

  Mirrors Python tinker.types.telemetry_batch.TelemetryBatch.
  """

  alias Tinkex.Types.TelemetryEvent

  @enforce_keys [:events, :platform, :sdk_version, :session_id]
  defstruct [:events, :platform, :sdk_version, :session_id]

  @type t :: %__MODULE__{
    events: [TelemetryEvent.t()],
    platform: String.t(),
    sdk_version: String.t(),
    session_id: String.t()
  }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      events: Keyword.fetch!(opts, :events),
      platform: Keyword.fetch!(opts, :platform),
      sdk_version: Keyword.fetch!(opts, :sdk_version),
      session_id: Keyword.fetch!(opts, :session_id)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = batch) do
    %{
      "events" => Enum.map(batch.events, &TelemetryEvent.to_map/1),
      "platform" => batch.platform,
      "sdk_version" => batch.sdk_version,
      "session_id" => batch.session_id
    }
  end
end
```

---

### GAP-TELEM-009: Missing TelemetrySendRequest Struct
**Severity:** HIGH
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/telemetry_send_request.py
class TelemetrySendRequest(StrictBase):
    events: List[TelemetryEvent]
    platform: str                    # Host platform name
    sdk_version: str                 # SDK version string
    session_id: str
```

**Elixir Status:**
- Same as TelemetryBatch (built inline)
- No distinction between batch and request
- Python uses `StrictBase` vs `BaseModel` (more strict validation)

**What's Missing:**
1. Separate request type (or alias)
2. Strict validation semantics

**Implementation Notes:**
```elixir
# Option 1: Type alias if semantically identical
defmodule Tinkex.Types.TelemetrySendRequest do
  @moduledoc """
  Request payload for telemetry send operation.

  Identical to TelemetryBatch but used for API request context.
  Mirrors Python tinker.types.telemetry_send_request.TelemetrySendRequest.
  """

  alias Tinkex.Types.TelemetryBatch

  @type t :: TelemetryBatch.t()

  defdelegate new(opts), to: TelemetryBatch
  defdelegate to_map(request), to: TelemetryBatch
end

# Option 2: Separate struct if validation differs
# (Use if strict validation is needed beyond TelemetryBatch)
```

---

### GAP-TELEM-010: Missing TelemetryResponse Struct
**Severity:** MEDIUM
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/telemetry_response.py
class TelemetryResponse(BaseModel):
    status: Literal["accepted"]
```

**Elixir Status:**
- Response not parsed/validated in `Tinkex.API.Telemetry`
- `send_sync/2` returns `{:ok, map()}` without type enforcement
- `send/2` ignores response entirely

**What's Missing:**
1. Response struct
2. Status validation
3. Response parsing

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.TelemetryResponse do
  @moduledoc """
  Response from telemetry send operation.

  Mirrors Python tinker.types.telemetry_response.TelemetryResponse.
  Currently only supports "accepted" status.
  """

  @enforce_keys [:status]
  defstruct [:status]

  @type t :: %__MODULE__{
    status: String.t()  # Always "accepted"
  }

  @spec from_map(map()) :: t()
  def from_map(%{"status" => "accepted"}) do
    %__MODULE__{status: "accepted"}
  end

  def from_map(%{status: "accepted"}) do
    %__MODULE__{status: "accepted"}
  end

  def from_map(other) do
    raise ArgumentError,
      "Invalid telemetry response, expected status='accepted', got: #{inspect(other)}"
  end

  @spec accepted?(t()) :: boolean()
  def accepted?(%__MODULE__{status: "accepted"}), do: true
  def accepted?(_), do: false
end
```

**Usage Note:** May not be critical since telemetry is fire-and-forget, but good for testing/validation.

---

### GAP-TELEM-011: Missing UntypedAPIFuture Struct
**Severity:** MEDIUM
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/shared/untyped_api_future.py
class UntypedAPIFuture(BaseModel):
    request_id: RequestID
    model_id: Optional[ModelID] = None
```

**Elixir Status:**
- Not explicitly represented as a struct
- `Tinkex.Future.poll/2` accepts request_id or map with request_id
- No dedicated future handle type
- Returns `Task.t()` instead

**What's Missing:**
1. Dedicated future handle struct
2. Optional model_id tracking
3. Type safety for future handles

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.UntypedAPIFuture do
  @moduledoc """
  Untyped API future handle.

  Represents a pending asynchronous operation tracked by request_id.
  Mirrors Python tinker.types.shared.untyped_api_future.UntypedAPIFuture.
  """

  @enforce_keys [:request_id]
  defstruct [:request_id, :model_id]

  @type t :: %__MODULE__{
    request_id: String.t(),
    model_id: String.t() | nil
  }

  @spec new(String.t(), String.t() | nil) :: t()
  def new(request_id, model_id \\ nil) do
    %__MODULE__{
      request_id: request_id,
      model_id: model_id
    }
  end

  @spec from_map(map()) :: t()
  def from_map(%{"request_id" => request_id} = map) do
    %__MODULE__{
      request_id: request_id,
      model_id: Map.get(map, "model_id")
    }
  end

  def from_map(%{request_id: request_id} = map) do
    %__MODULE__{
      request_id: request_id,
      model_id: Map.get(map, :model_id)
    }
  end

  def from_map(other) do
    raise ArgumentError,
      "Invalid future map, expected request_id key, got: #{inspect(other)}"
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = future) do
    base = %{"request_id" => future.request_id}

    case future.model_id do
      nil -> base
      model_id -> Map.put(base, "model_id", model_id)
    end
  end
end
```

**Design Question:** Should `Tinkex.Future.poll/2` return `{:ok, UntypedAPIFuture.t()}` or continue returning `Task.t()`? Task-based approach is more idiomatic Elixir.

---

### GAP-TELEM-012: Missing FutureRetrieveRequest Struct
**Severity:** LOW
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/future_retrieve_request.py
class FutureRetrieveRequest(StrictBase):
    request_id: RequestID   # The ID of the request to retrieve
```

**Elixir Status:**
- Built inline as `%{request_id: request_id}` in `Future.poll_loop/2`
- No dedicated struct

**What's Missing:**
1. Request struct (very simple)
2. Type validation

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.FutureRetrieveRequest do
  @moduledoc """
  Request to retrieve the status/result of a pending future.

  Mirrors Python tinker.types.future_retrieve_request.FutureRetrieveRequest.
  """

  @enforce_keys [:request_id]
  defstruct [:request_id]

  @type t :: %__MODULE__{
    request_id: String.t()
  }

  @spec new(String.t()) :: t()
  def new(request_id) when is_binary(request_id) do
    %__MODULE__{request_id: request_id}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{request_id: request_id}) do
    %{"request_id" => request_id}
  end
end
```

**Priority Note:** LOW because inline map is sufficient for such a simple single-field request.

---

### GAP-TELEM-013: Missing RequestFailedResponse Struct
**Severity:** MEDIUM
**Category:** Type Structure

**Python Implementation:**
```python
# tinker/types/request_failed_response.py
class RequestFailedResponse(BaseModel):
    error: str
    category: RequestErrorCategory
```

**Elixir Status:**
- Handled inline in `Future.handle_response/3` as `FutureFailedResponse`
- No dedicated struct matching Python's name
- `FutureFailedResponse` has different structure (status + error map)

**What's Missing:**
1. Dedicated struct matching Python API
2. Direct category field (currently nested in error map)

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.RequestFailedResponse do
  @moduledoc """
  Response indicating a request failed with categorized error.

  Mirrors Python tinker.types.request_failed_response.RequestFailedResponse.
  This is distinct from FutureFailedResponse which wraps this structure.
  """

  alias Tinkex.Types.RequestErrorCategory

  @enforce_keys [:error, :category]
  defstruct [:error, :category]

  @type t :: %__MODULE__{
    error: String.t(),
    category: RequestErrorCategory.t()
  }

  @spec from_map(map()) :: t()
  def from_map(%{"error" => error, "category" => category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end

  def from_map(%{error: error, category: category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end

  def from_map(other) do
    raise ArgumentError,
      "Invalid RequestFailedResponse, expected error and category fields, got: #{inspect(other)}"
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{error: error, category: category}) do
    %{
      "error" => error,
      "category" => RequestErrorCategory.to_string(category)
    }
  end
end
```

---

### GAP-TELEM-014: Event Type String Constants
**Severity:** HIGH
**Category:** Code Quality

**Current State:**
Event type strings are hardcoded throughout `Tinkex.Telemetry.Reporter`:
- Line 447: `event: "GENERIC_EVENT"`
- Line 468: `event: "SESSION_START"`
- Line 483: `event: "SESSION_END"`
- Line 564: `event: "UNHANDLED_EXCEPTION"`

**Recommendation:**
After implementing `Tinkex.Types.EventType` (GAP-TELEM-001), refactor all hardcoded strings to use `EventType.to_string/1`:

```elixir
# Before
event: "SESSION_START"

# After
event: EventType.to_string(:session_start)
```

This provides:
1. Compile-time validation
2. Single source of truth
3. Easy refactoring if event names change
4. Dialyzer support

---

### GAP-TELEM-015: Severity Level String Constants
**Severity:** HIGH
**Category:** Code Quality

**Current State:**
Severity levels hardcoded as strings:
- Line 471: `severity: "INFO"`
- Line 486: `severity: "INFO"`
- Lines 613-617: Manual string conversion

**Recommendation:**
After implementing `Tinkex.Types.Severity` (GAP-TELEM-002), refactor to use centralized conversion:

```elixir
# Before
severity: "INFO"

# After
severity: Severity.to_string(:info)
```

---

### GAP-TELEM-016: ISO 8601 Duration Format Discrepancy
**Severity:** MEDIUM
**Category:** Wire Protocol

**Python Format (Expected):**
ISO 8601 duration: `"PT1H23M45.678901S"` (Period Time format)

**Elixir Current Format:**
Custom format: `"1:23:45.678901"` (HH:MM:SS.microseconds)

**Location:** `Reporter.duration_string/2` (lines 647-661)

**What's Missing:**
1. ISO 8601 duration formatting
2. Period-Time (PT) format compliance

**Implementation Notes:**
```elixir
defp duration_string_iso8601(start_us, end_us) do
  diff = max(end_us - start_us, 0)
  total_seconds = div(diff, 1_000_000)
  micro = rem(diff, 1_000_000)
  hours = div(total_seconds, 3600)
  minutes = div(rem(total_seconds, 3600), 60)
  seconds = rem(total_seconds, 60)

  # Build ISO 8601 duration: PT1H23M45.678901S
  parts = []
  parts = if hours > 0, do: parts ++ ["#{hours}H"], else: parts
  parts = if minutes > 0, do: parts ++ ["#{minutes}M"], else: parts

  # Seconds always included even if 0
  seconds_str = if micro > 0 do
    micro_str = String.pad_leading(Integer.to_string(micro), 6, "0")
    "#{seconds}.#{micro_str}S"
  else
    "#{seconds}S"
  end

  "PT" <> Enum.join(parts, "") <> seconds_str
end
```

**Priority:** MEDIUM - affects wire protocol compatibility with Python backend/clients.

---

### GAP-TELEM-017: Telemetry Type Documentation
**Severity:** LOW
**Category:** Documentation

**What's Missing:**
1. Comprehensive module documentation for telemetry types
2. Examples of event construction
3. Wire format specifications
4. Integration guide for custom telemetry

**Recommendation:**
Add documentation guide similar to Python's approach:
```markdown
# Telemetry Events Guide

## Event Types

### SessionStartEvent
Emitted when telemetry reporter initializes.

**Fields:**
- `event`: Always "SESSION_START"
- `event_id`: Unique event identifier (UUID)
- `event_session_index`: Sequential index within session (0-based)
- `severity`: Always "INFO"
- `timestamp`: ISO 8601 timestamp

**Example:**
```json
{
  "event": "SESSION_START",
  "event_id": "a1b2c3d4...",
  "event_session_index": 0,
  "severity": "INFO",
  "timestamp": "2025-11-26T10:30:00.123456Z"
}
```

[Similar for other event types...]
```

---

## 4. Event Types Enumeration

### Complete Mapping

| Python Literal | Elixir Atom (Proposed) | Wire Format | Description |
|----------------|------------------------|-------------|-------------|
| `"SESSION_START"` | `:session_start` | `"SESSION_START"` | Session initialization event |
| `"SESSION_END"` | `:session_end` | `"SESSION_END"` | Session termination event |
| `"UNHANDLED_EXCEPTION"` | `:unhandled_exception` | `"UNHANDLED_EXCEPTION"` | Unexpected exception occurred |
| `"GENERIC_EVENT"` | `:generic_event` | `"GENERIC_EVENT"` | Application-specific event |

### Current Elixir Implementation

**Hardcoded Strings in `Tinkex.Telemetry.Reporter`:**
- Line 447: `"GENERIC_EVENT"`
- Line 468: `"SESSION_START"`
- Line 483: `"SESSION_END"`
- Line 564: `"UNHANDLED_EXCEPTION"`

**No centralized enumeration module.**

### Recommended Type Spec

```elixir
@type event_type :: :session_start | :session_end | :unhandled_exception | :generic_event
```

---

## 5. Severity Levels Enumeration

### Complete Mapping

| Python Literal | Elixir Atom (Proposed) | Wire Format | Numeric Level | Description |
|----------------|------------------------|-------------|---------------|-------------|
| `"DEBUG"` | `:debug` | `"DEBUG"` | 0 | Detailed diagnostic information |
| `"INFO"` | `:info` | `"INFO"` | 1 | Informational messages |
| `"WARNING"` | `:warning` | `"WARNING"` | 2 | Warning messages |
| `"ERROR"` | `:error` | `"ERROR"` | 3 | Error conditions |
| `"CRITICAL"` | `:critical` | `"CRITICAL"` | 4 | Critical failures |

### Current Elixir Implementation

**Type Spec Exists:**
```elixir
# lib/tinkex/telemetry/reporter.ex:42
@type severity :: :debug | :info | :warning | :error | :critical | String.t()
```

**Conversion Function:**
```elixir
# Lines 613-617
defp severity_string(severity) when is_atom(severity),
  do: severity |> Atom.to_string() |> String.upcase()

defp severity_string(severity) when is_binary(severity), do: severity |> String.upcase()
defp severity_string(_), do: "INFO"
```

**No dedicated module, no parser, no numeric levels.**

---

## 6. Future/Async Type Analysis

### UntypedAPIFuture

**Python Purpose:**
- Represents a pending async operation
- Contains `request_id` for polling
- Optional `model_id` for model-specific operations

**Elixir Current Approach:**
- Uses `Task.t()` for async operations
- `Tinkex.Future.poll/2` returns `Task.t({:ok, map()} | {:error, Error.t()})`
- Request ID passed as plain string or map

**Gap Analysis:**
- ❌ No dedicated future handle struct
- ❌ No model_id tracking in future handles
- ✅ Task-based async model is idiomatic
- ✅ Polling infrastructure complete

**Design Decision Required:**
Should Elixir maintain separate `UntypedAPIFuture` struct or continue with Task-based approach?

**Recommendation:** Add struct but treat it as optional wrapper. Keep Task-based primary API:

```elixir
# Primary API (current, keep)
future_task = Tinkex.Future.poll(request_id, config: config)
{:ok, result} = Tinkex.Future.await(future_task)

# Optional typed wrapper (new)
future_handle = UntypedAPIFuture.new(request_id, model_id)
future_task = Tinkex.Future.poll(future_handle, config: config)
```

### FutureRetrieveRequest

**Python:** Single-field struct with `request_id`

**Elixir:** Inline map `%{request_id: request_id}`

**Gap:** Low priority - inline map is sufficient for single field.

### FutureRetrieveResponse

**Status:** ✅ **COMPLETE**

Elixir implementation covers all Python response types:
- `TryAgainResponse` ✅
- `FuturePendingResponse` ✅
- `FutureCompletedResponse` ✅
- `FutureFailedResponse` ✅
- Union parsing via `from_json/1` ✅

---

## 7. Recommendations

### Priority 1: Critical Gaps (Immediate)

1. **Create `Tinkex.Types.EventType` module** (GAP-TELEM-001)
   - Centralize event type enumeration
   - Add parser and to_string functions
   - Refactor hardcoded strings in Reporter

2. **Create `Tinkex.Types.Severity` module** (GAP-TELEM-002)
   - Centralize severity enumeration
   - Add numeric levels
   - Refactor severity_string function

3. **Fix ISO 8601 Duration Format** (GAP-TELEM-016)
   - Implement proper PT format
   - Update duration_string function
   - Add tests for format compliance

### Priority 2: High Priority (Short Term)

4. **Create Event Struct Modules** (GAP-TELEM-003 through GAP-TELEM-006)
   - `SessionStartEvent`
   - `SessionEndEvent`
   - `UnhandledExceptionEvent`
   - `GenericEvent`
   - Implement to_map functions
   - Add validation

5. **Create `TelemetryEvent` Union** (GAP-TELEM-007)
   - Define union type
   - Add polymorphic encoding
   - Update Reporter to use structs

6. **Create Batch/Request Structs** (GAP-TELEM-008, GAP-TELEM-009)
   - `TelemetryBatch`
   - `TelemetrySendRequest`
   - Update API integration

### Priority 3: Medium Priority (Mid Term)

7. **Create Response Structs** (GAP-TELEM-010, GAP-TELEM-013)
   - `TelemetryResponse`
   - `RequestFailedResponse`
   - Add validation in API layer

8. **Create Future Handle Types** (GAP-TELEM-011, GAP-TELEM-012)
   - `UntypedAPIFuture`
   - `FutureRetrieveRequest`
   - Evaluate integration with current Task-based API

### Priority 4: Low Priority (Long Term)

9. **Comprehensive Documentation** (GAP-TELEM-017)
   - Add module docs with examples
   - Wire format specifications
   - Integration guides

10. **Type Safety Improvements**
    - Add Dialyzer specs for all functions
    - Property-based testing for serialization
    - Schema validation tests

### Migration Strategy

**Phase 1: Foundation (Week 1)**
- Create EventType and Severity modules
- Fix duration format
- Add tests

**Phase 2: Event Structs (Week 2)**
- Create all event struct modules
- Implement to_map/from_map
- Update Reporter to use structs internally

**Phase 3: Request/Response Types (Week 3)**
- Create batch and request structs
- Update API integration
- Add response validation

**Phase 4: Future Types (Week 4)**
- Evaluate future handle design
- Implement if beneficial
- Update documentation

**Phase 5: Testing & Documentation (Week 5)**
- Comprehensive test coverage
- Integration tests
- Documentation and examples

### Testing Requirements

For each new type module:

1. **Unit Tests**
   - Constructor validation
   - Field type validation
   - to_map serialization
   - from_map parsing
   - Edge cases (nil, invalid types)

2. **Property Tests**
   - Round-trip serialization (struct -> map -> struct)
   - Wire format compatibility
   - Enum value exhaustiveness

3. **Integration Tests**
   - End-to-end telemetry flow
   - Reporter integration
   - API integration

### Wire Protocol Compatibility

**Critical for Backend Compatibility:**
1. Event type strings must match exactly: `"SESSION_START"` etc.
2. Severity strings must match exactly: `"DEBUG"`, `"INFO"`, etc.
3. Duration format must be ISO 8601: `"PT1H23M45.678901S"`
4. Timestamp format already correct: ISO 8601 datetime

**Testing Strategy:**
- Add JSON schema validation tests
- Compare serialized output with Python examples
- Round-trip tests with Python-generated payloads

---

## 8. Implementation Checklist

### EventType Module
- [ ] Create `lib/tinkex/types/event_type.ex`
- [ ] Define @type t
- [ ] Implement parse/1
- [ ] Implement to_string/1
- [ ] Add @spec for all functions
- [ ] Write unit tests
- [ ] Write property tests
- [ ] Update Reporter to use module

### Severity Module
- [ ] Create `lib/tinkex/types/severity.ex`
- [ ] Define @type t
- [ ] Implement parse/1
- [ ] Implement to_string/1
- [ ] Implement level/1 (numeric)
- [ ] Add @spec for all functions
- [ ] Write unit tests
- [ ] Write property tests
- [ ] Update Reporter to use module

### Event Struct Modules
- [ ] Create `lib/tinkex/types/session_start_event.ex`
- [ ] Create `lib/tinkex/types/session_end_event.ex`
- [ ] Create `lib/tinkex/types/unhandled_exception_event.ex`
- [ ] Create `lib/tinkex/types/generic_event.ex`
- [ ] Create `lib/tinkex/types/telemetry_event.ex` (union)
- [ ] Implement new/1 for each
- [ ] Implement to_map/1 for each
- [ ] Implement from_map/1 for each
- [ ] Add @spec for all functions
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Update Reporter to construct structs

### Batch/Request Modules
- [ ] Create `lib/tinkex/types/telemetry_batch.ex`
- [ ] Create `lib/tinkex/types/telemetry_send_request.ex`
- [ ] Create `lib/tinkex/types/telemetry_response.ex`
- [ ] Implement new/1 for each
- [ ] Implement to_map/1 for each
- [ ] Implement from_map/1 for each
- [ ] Add validation logic
- [ ] Write unit tests
- [ ] Update API.Telemetry to use structs

### Future Handle Modules
- [ ] Create `lib/tinkex/types/untyped_api_future.ex`
- [ ] Create `lib/tinkex/types/future_retrieve_request.ex`
- [ ] Create `lib/tinkex/types/request_failed_response.ex`
- [ ] Implement new/1 for each
- [ ] Implement to_map/1 for each
- [ ] Implement from_map/1 for each
- [ ] Write unit tests
- [ ] Evaluate integration with Future module

### Duration Format Fix
- [ ] Implement ISO 8601 duration formatter
- [ ] Update Reporter.duration_string/2
- [ ] Add format validation tests
- [ ] Test wire protocol compatibility

### Documentation
- [ ] Add module documentation for all types
- [ ] Add function documentation with examples
- [ ] Create telemetry integration guide
- [ ] Add wire format specifications
- [ ] Update main README with telemetry section

### Testing
- [ ] Unit tests for all type modules (>95% coverage)
- [ ] Property tests for serialization
- [ ] Integration tests for Reporter
- [ ] Integration tests for API layer
- [ ] Wire format compatibility tests
- [ ] Round-trip tests with JSON

---

## 9. File Inventory

### Python Source Files (Complete)
1. ✅ `tinker/types/telemetry_event.py` - Union type
2. ✅ `tinker/types/telemetry_batch.py` - Batch struct
3. ✅ `tinker/types/telemetry_response.py` - Response struct
4. ✅ `tinker/types/telemetry_send_request.py` - Request struct
5. ✅ `tinker/types/event_type.py` - Event type enum
6. ✅ `tinker/types/generic_event.py` - Generic event struct
7. ✅ `tinker/types/severity.py` - Severity enum
8. ✅ `tinker/types/unhandled_exception_event.py` - Exception event struct
9. ✅ `tinker/types/session_start_event.py` - Session start struct
10. ✅ `tinker/types/session_end_event.py` - Session end struct
11. ✅ `tinker/types/request_failed_response.py` - Failed response struct
12. ✅ `tinker/types/request_error_category.py` - Error category enum
13. ✅ `tinker/types/try_again_response.py` - Try again response struct
14. ✅ `tinker/types/future_retrieve_request.py` - Future request struct
15. ✅ `tinker/types/future_retrieve_response.py` - Future response union
16. ✅ `tinker/types/shared/untyped_api_future.py` - Future handle struct
17. ✅ `tinker/types/request_id.py` - Type alias
18. ✅ `tinker/types/model_id.py` - Type alias

### Elixir Existing Files
1. ✅ `lib/tinkex/types/request_error_category.ex` - Complete
2. ✅ `lib/tinkex/types/try_again_response.ex` - Complete
3. ✅ `lib/tinkex/types/future_responses.ex` - Complete
4. ✅ `lib/tinkex/types/queue_state.ex` - Complete (Elixir addition)
5. ✅ `lib/tinkex/telemetry.ex` - Helper functions
6. ✅ `lib/tinkex/telemetry/reporter.ex` - Core implementation (uses maps)
7. ✅ `lib/tinkex/telemetry/capture.ex` - Exception capture macros
8. ✅ `lib/tinkex/telemetry/provider.ex` - Provider behaviour
9. ✅ `lib/tinkex/api/telemetry.ex` - API endpoints
10. ✅ `lib/tinkex/future.ex` - Future polling implementation
11. ✅ `lib/tinkex/queue_state_observer.ex` - Observer behaviour (Elixir addition)

### Elixir Missing Files (To Create)
1. ❌ `lib/tinkex/types/event_type.ex`
2. ❌ `lib/tinkex/types/severity.ex`
3. ❌ `lib/tinkex/types/session_start_event.ex`
4. ❌ `lib/tinkex/types/session_end_event.ex`
5. ❌ `lib/tinkex/types/unhandled_exception_event.ex`
6. ❌ `lib/tinkex/types/generic_event.ex`
7. ❌ `lib/tinkex/types/telemetry_event.ex`
8. ❌ `lib/tinkex/types/telemetry_batch.ex`
9. ❌ `lib/tinkex/types/telemetry_send_request.ex`
10. ❌ `lib/tinkex/types/telemetry_response.ex`
11. ❌ `lib/tinkex/types/untyped_api_future.ex`
12. ❌ `lib/tinkex/types/future_retrieve_request.ex`
13. ❌ `lib/tinkex/types/request_failed_response.ex`

---

## 10. Conclusion

The Elixir tinkex implementation has **solid telemetry infrastructure** but lacks the **structured type definitions** present in the Python tinker library. The core functionality is present (event emission, batching, reporting, async sending) but uses plain maps instead of typed structs.

**Key Insight:** This represents a philosophical difference:
- **Python:** Type safety via Pydantic models, compile-time validation
- **Elixir:** Runtime flexibility via maps, pattern matching

However, for **wire protocol compatibility** and **maintainability**, adding structured types is recommended. The implementation should:

1. **Preserve existing functionality** - Reporter works well
2. **Add type safety layer** - New struct modules
3. **Maintain backward compatibility** - Gradual migration
4. **Improve documentation** - Clear types aid understanding

**Estimated Effort:** 3-4 weeks for complete implementation with tests and documentation.

**Risk Assessment:** LOW - Changes are additive, existing code continues to work during migration.

---

**End of Gap Analysis**
