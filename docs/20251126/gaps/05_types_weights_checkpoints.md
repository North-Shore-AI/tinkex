# Gap Analysis: Types - Weights & Checkpoints Domain

**Analysis Date:** 2025-11-26
**Domain:** Types - Weights & Checkpoints
**Analyst:** Claude Code
**Python Source:** `tinker/src/tinker/types/` (Weights & Checkpoint types)
**Elixir Destination:** `tinkex/lib/tinkex/types/`

---

## Executive Summary

### Overall Completeness: 65%

**Status Overview:**
- **Critical Gaps:** 4
- **High Priority Gaps:** 3
- **Medium Priority Gaps:** 2
- **Low Priority Gaps:** 1
- **Total Gaps:** 10

### Key Findings

1. **Missing Response Types (Critical):** `SaveWeightsResponse`, `SaveWeightsForSamplerResponse`, and `LoadWeightsResponse` are completely missing from Elixir implementation
2. **Missing Path Parser (Critical):** `ParsedCheckpointTinkerPath` class with path parsing logic is not ported
3. **Missing Internal Type (High):** `SaveWeightsForSamplerResponseInternal` is not ported
4. **Incomplete Checkpoint Type (High):** Missing `time` field type conversion from datetime to string
5. **Missing Cursor Type (Medium):** Cursor pagination type is not ported
6. **Incomplete Archive Response (Medium):** Missing `expires` field in `CheckpointArchiveUrlResponse`
7. **Limited Tensor Conversion (Low):** Missing PyTorch and NumPy conversion utilities

### Impact Assessment

The missing response types represent a **critical gap** that will prevent proper handling of save/load weight operations. The missing `ParsedCheckpointTinkerPath` class means checkpoint path parsing and validation logic needs to be implemented separately in Elixir.

---

## 1. Type-by-Type Comparison

### 1.1 Checkpoint Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `Checkpoint` | 6 fields | `Checkpoint` | 5/6 match | ⚠️ Partial - datetime handling |
| `ParsedCheckpointTinkerPath` | 4 fields + parser | ❌ Missing | 0/4 | ❌ Critical - Not ported |
| `CheckpointType` | 2 literals | ❌ Missing | 0/2 | ⚠️ Medium - Used as strings |
| `CheckpointsListResponse` | 2 fields | `CheckpointsListResponse` | 1/2 match | ⚠️ Partial - cursor type |
| `CheckpointArchiveUrlResponse` | 2 fields | `CheckpointArchiveUrlResponse` | 1/2 match | ⚠️ Partial - missing expires |

### 1.2 Weight Save/Load Request Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `SaveWeightsRequest` | 4 fields | `SaveWeightsRequest` | 4/4 | ✅ Complete |
| `SaveWeightsForSamplerRequest` | 5 fields | `SaveWeightsForSamplerRequest` | 5/5 | ✅ Complete |
| `LoadWeightsRequest` | ❌ Missing in Python | `LoadWeightsRequest` | N/A | ℹ️ Elixir addition |

### 1.3 Weight Save/Load Response Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `SaveWeightsResponse` | 2 fields | ❌ Missing | 0/2 | ❌ Critical - Not ported |
| `SaveWeightsForSamplerResponse` | 2 fields | ❌ Missing | 0/2 | ❌ Critical - Not ported |
| `SaveWeightsForSamplerResponseInternal` | 3 fields | ❌ Missing | 0/3 | ⚠️ High - Not ported |
| `LoadWeightsResponse` | 2 fields | ❌ Missing | 0/2 | ❌ Critical - Not ported |

### 1.4 Metadata Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `WeightsInfoResponse` | 3 fields | `WeightsInfoResponse` | 3/3 | ✅ Complete |
| `Cursor` | 3 fields | ❌ Missing | 0/3 | ⚠️ Medium - Not ported |

### 1.5 Tensor Types

| Python Type | Fields | Elixir Type | Fields Match | Gap Status |
|-------------|--------|-------------|--------------|------------|
| `TensorData` | 3 fields + 5 methods | `TensorData` | 3/3 fields | ⚠️ Partial - different conversions |
| `TensorDtype` | 2 literals | `TensorDtype` | 2/2 | ✅ Complete |

---

## 2. Detailed Gap Analysis

### GAP-CKPT-001: Missing SaveWeightsResponse Type

**Severity:** ❌ **CRITICAL**

**Python Implementation:**
```python
# tinker/types/save_weights_response.py
class SaveWeightsResponse(BaseModel):
    path: str
    """A tinker URI for model weights at a specific step"""

    type: Optional[Literal["save_weights"]] = None
```

**Elixir Status:** ❌ **COMPLETELY MISSING**

**What's Missing:**
- Complete type definition for save weights response
- Path field for tinker URI
- Type discriminator field

**Impact:**
- Cannot properly handle responses from save_weights operations
- Blocks proper implementation of checkpoint saving workflow
- Breaks type safety for weight persistence operations

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.SaveWeightsResponse do
  @moduledoc """
  Response from a save_weights request.

  Contains the tinker URI path where the weights were saved.
  """

  @type t :: %__MODULE__{
          path: String.t(),
          type: String.t() | nil
        }

  defstruct [:path, :type]

  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      path: json["path"] || json[:path],
      type: json["type"] || json[:type]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.SaveWeightsResponse do
  def encode(resp, opts) do
    map = %{path: resp.path}
    map = if resp.type, do: Map.put(map, :type, resp.type), else: map
    Jason.Encode.map(map, opts)
  end
end
```

**Dependencies:**
- None (standalone type)

**Test Requirements:**
- JSON encoding/decoding
- Field validation
- Type discriminator handling

---

### GAP-CKPT-002: Missing SaveWeightsForSamplerResponse Types

**Severity:** ❌ **CRITICAL**

**Python Implementation:**
```python
# tinker/types/save_weights_for_sampler_response.py
class SaveWeightsForSamplerResponseInternal(BaseModel):
    path: str | None = None
    """A tinker URI for model weights for sampling at a specific step"""
    sampling_session_id: str | None = None
    """The generated sampling session ID"""
    type: Optional[Literal["save_weights_for_sampler"]] = None

class SaveWeightsForSamplerResponse(BaseModel):
    path: str
    """A tinker URI for model weights for sampling at a specific step"""
    type: Optional[Literal["save_weights_for_sampler"]] = None
```

**Elixir Status:** ❌ **COMPLETELY MISSING**

**What's Missing:**
- **Two distinct response types:**
  1. Internal version with optional fields and sampling_session_id
  2. Public version with required path
- Sampling session ID tracking
- Type discriminator fields

**Impact:**
- Cannot handle sampler weight save operations
- Blocks sampling session management
- Missing critical data for distributed sampling workflows

**Implementation Notes:**
```elixir
# Internal version (used in some backend responses)
defmodule Tinkex.Types.SaveWeightsForSamplerResponseInternal do
  @moduledoc """
  Internal response format for save_weights_for_sampler.

  This version has optional fields and includes the sampling_session_id.
  Used in some backend communication scenarios.
  """

  @type t :: %__MODULE__{
          path: String.t() | nil,
          sampling_session_id: String.t() | nil,
          type: String.t() | nil
        }

  defstruct [:path, :sampling_session_id, :type]

  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      path: json["path"] || json[:path],
      sampling_session_id: json["sampling_session_id"] || json[:sampling_session_id],
      type: json["type"] || json[:type]
    }
  end
end

# Public version (standard API response)
defmodule Tinkex.Types.SaveWeightsForSamplerResponse do
  @moduledoc """
  Response from a save_weights_for_sampler request.

  Contains the tinker URI path where the sampler weights were saved.
  """

  @enforce_keys [:path]
  @type t :: %__MODULE__{
          path: String.t(),
          type: String.t() | nil
        }

  defstruct [:path, :type]

  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      path: json["path"] || json[:path],
      type: json["type"] || json[:type]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.SaveWeightsForSamplerResponse do
  def encode(resp, opts) do
    map = %{path: resp.path}
    map = if resp.type, do: Map.put(map, :type, resp.type), else: map
    Jason.Encode.map(map, opts)
  end
end
```

**Dependencies:**
- None (standalone types)

**Test Requirements:**
- Both internal and public response handling
- Optional vs required field validation
- Sampling session ID tracking
- JSON encoding/decoding for both types

---

### GAP-CKPT-003: Missing LoadWeightsResponse Type

**Severity:** ❌ **CRITICAL**

**Python Implementation:**
```python
# tinker/types/load_weights_response.py
class LoadWeightsResponse(BaseModel):
    path: Optional[str] = None
    """A tinker URI for model weights at a specific step"""

    type: Optional[Literal["load_weights"]] = None
```

**Elixir Status:** ❌ **COMPLETELY MISSING**

**What's Missing:**
- Complete type definition for load weights response
- Optional path field
- Type discriminator field

**Impact:**
- Cannot properly handle responses from load_weights operations
- Blocks checkpoint restoration workflow
- Missing confirmation data for weight loading operations

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.LoadWeightsResponse do
  @moduledoc """
  Response from a load_weights request.

  Contains the tinker URI path from which weights were loaded.
  Both fields are optional as this is primarily a status response.
  """

  @type t :: %__MODULE__{
          path: String.t() | nil,
          type: String.t() | nil
        }

  defstruct [:path, :type]

  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      path: json["path"] || json[:path],
      type: json["type"] || json[:type]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.LoadWeightsResponse do
  def encode(resp, opts) do
    map = %{}
    map = if resp.path, do: Map.put(map, :path, resp.path), else: map
    map = if resp.type, do: Map.put(map, :type, resp.type), else: map
    Jason.Encode.map(map, opts)
  end
end
```

**Dependencies:**
- None (standalone type)

**Test Requirements:**
- JSON encoding/decoding
- Optional field handling
- Type discriminator handling

---

### GAP-CKPT-004: Missing ParsedCheckpointTinkerPath Type and Parser

**Severity:** ❌ **CRITICAL**

**Python Implementation:**
```python
# tinker/types/checkpoint.py (lines 31-60)
class ParsedCheckpointTinkerPath(BaseModel):
    tinker_path: str
    """The tinker path to the checkpoint"""

    training_run_id: str
    """The training run ID"""

    checkpoint_type: CheckpointType
    """The type of checkpoint (training or sampler)"""

    checkpoint_id: str
    """The checkpoint ID"""

    @classmethod
    def from_tinker_path(cls, tinker_path: str) -> "ParsedCheckpointTinkerPath":
        """Parse a tinker path to an instance of ParsedCheckpointTinkerPath"""
        if not tinker_path.startswith("tinker://"):
            raise ValueError(f"Invalid tinker path: {tinker_path}")
        parts = tinker_path[9:].split("/")
        if len(parts) != 3:
            raise ValueError(f"Invalid tinker path: {tinker_path}")
        if parts[1] not in ["weights", "sampler_weights"]:
            raise ValueError(f"Invalid tinker path: {tinker_path}")
        checkpoint_type = "training" if parts[1] == "weights" else "sampler"
        return cls(
            tinker_path=tinker_path,
            training_run_id=parts[0],
            checkpoint_type=checkpoint_type,
            checkpoint_id="/".join(parts[1:]),
        )
```

**Elixir Status:** ❌ **COMPLETELY MISSING**

**What's Missing:**
- Complete type definition for parsed checkpoint paths
- Critical path parsing and validation logic
- CheckpointType literal type (used as strings in current implementation)
- Path format validation

**Impact:**
- No standardized way to parse tinker:// URIs
- Manual path parsing scattered across codebase
- Missing validation for checkpoint path format
- Cannot extract training run ID and checkpoint type from paths

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.CheckpointType do
  @moduledoc """
  Checkpoint type literal.

  Valid values: "training" | "sampler"
  """

  @type t :: :training | :sampler

  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse("training"), do: {:ok, :training}
  def parse("sampler"), do: {:ok, :sampler}
  def parse(other), do: {:error, "Invalid checkpoint type: #{other}"}

  @spec to_string(t()) :: String.t()
  def to_string(:training), do: "training"
  def to_string(:sampler), do: "sampler"
end

defmodule Tinkex.Types.ParsedCheckpointTinkerPath do
  @moduledoc """
  Parsed representation of a tinker checkpoint path.

  Tinker paths have the format:
    tinker://<training_run_id>/<weights|sampler_weights>/<checkpoint_id>

  Examples:
    - tinker://run-123/weights/checkpoint-001
    - tinker://run-456/sampler_weights/step-5000
  """

  alias Tinkex.Types.CheckpointType

  @enforce_keys [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]
  @type t :: %__MODULE__{
          tinker_path: String.t(),
          training_run_id: String.t(),
          checkpoint_type: CheckpointType.t(),
          checkpoint_id: String.t()
        }

  defstruct [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]

  @doc """
  Parse a tinker path into its components.

  ## Examples

      iex> ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-123/weights/checkpoint-001")
      {:ok, %ParsedCheckpointTinkerPath{
        tinker_path: "tinker://run-123/weights/checkpoint-001",
        training_run_id: "run-123",
        checkpoint_type: :training,
        checkpoint_id: "weights/checkpoint-001"
      }}

      iex> ParsedCheckpointTinkerPath.from_tinker_path("invalid")
      {:error, "Invalid tinker path: invalid"}
  """
  @spec from_tinker_path(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_tinker_path(tinker_path) do
    with :ok <- validate_prefix(tinker_path),
         {:ok, parts} <- parse_parts(tinker_path),
         {:ok, checkpoint_type} <- validate_checkpoint_type(parts) do
      {:ok,
       %__MODULE__{
         tinker_path: tinker_path,
         training_run_id: Enum.at(parts, 0),
         checkpoint_type: checkpoint_type,
         checkpoint_id: Enum.slice(parts, 1..2) |> Enum.join("/")
       }}
    end
  end

  @doc """
  Parse a tinker path, raising on error.
  """
  @spec from_tinker_path!(String.t()) :: t()
  def from_tinker_path!(tinker_path) do
    case from_tinker_path(tinker_path) do
      {:ok, parsed} -> parsed
      {:error, msg} -> raise ArgumentError, msg
    end
  end

  defp validate_prefix(path) do
    if String.starts_with?(path, "tinker://") do
      :ok
    else
      {:error, "Invalid tinker path: #{path}"}
    end
  end

  defp parse_parts(path) do
    parts = path |> String.slice(9..-1) |> String.split("/")

    if length(parts) == 3 do
      {:ok, parts}
    else
      {:error, "Invalid tinker path: #{path}"}
    end
  end

  defp validate_checkpoint_type(parts) do
    case Enum.at(parts, 1) do
      "weights" -> {:ok, :training}
      "sampler_weights" -> {:ok, :sampler}
      other -> {:error, "Invalid checkpoint type in path: #{other}"}
    end
  end
end
```

**Dependencies:**
- CheckpointType type definition

**Test Requirements:**
- Valid path parsing
- Invalid path rejection (no tinker:// prefix)
- Invalid path rejection (wrong number of parts)
- Invalid path rejection (wrong checkpoint type)
- Training checkpoint parsing
- Sampler checkpoint parsing
- Error message validation

---

### GAP-CKPT-005: Missing Cursor Type

**Severity:** ⚠️ **MEDIUM**

**Python Implementation:**
```python
# tinker/types/cursor.py
class Cursor(BaseModel):
    offset: int
    """The offset used for pagination"""

    limit: int
    """The maximum number of items requested"""

    total_count: int
    """The total number of items available"""
```

**Elixir Status:** ❌ **COMPLETELY MISSING**

**Current Workaround:** Using raw `map()` type in `CheckpointsListResponse`

**What's Missing:**
- Structured Cursor type with typed fields
- Pagination metadata tracking
- Type safety for cursor operations

**Impact:**
- Less type safety for paginated responses
- Cannot validate cursor structure
- Missing documentation for pagination fields

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.Cursor do
  @moduledoc """
  Pagination cursor information.

  Used in list responses to provide pagination metadata.
  """

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          limit: non_neg_integer(),
          total_count: non_neg_integer()
        }

  defstruct [:offset, :limit, :total_count]

  @doc """
  Create a Cursor from a JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      offset: json["offset"] || json[:offset] || 0,
      limit: json["limit"] || json[:limit] || 0,
      total_count: json["total_count"] || json[:total_count] || 0
    }
  end

  @doc """
  Check if there are more items available.
  """
  @spec has_more?(t()) :: boolean()
  def has_more?(%__MODULE__{offset: offset, limit: limit, total_count: total}) do
    offset + limit < total
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.Cursor do
  def encode(cursor, opts) do
    %{
      offset: cursor.offset,
      limit: cursor.limit,
      total_count: cursor.total_count
    }
    |> Jason.Encode.map(opts)
  end
end
```

**Dependencies:**
- None (standalone type)

**Follow-up Changes:**
- Update `CheckpointsListResponse.cursor` field type from `map() | nil` to `Cursor.t() | nil`
- Update deserialization to use `Cursor.from_json/1`

**Test Requirements:**
- JSON encoding/decoding
- has_more? logic
- Field validation

---

### GAP-CKPT-006: Incomplete CheckpointArchiveUrlResponse

**Severity:** ⚠️ **MEDIUM**

**Python Implementation:**
```python
# tinker/types/checkpoint_archive_url_response.py
class CheckpointArchiveUrlResponse(BaseModel):
    url: str
    """Signed URL to download the checkpoint archive"""

    expires: datetime.datetime
    """Unix timestamp when the signed URL expires, if available"""
```

**Elixir Status:** ⚠️ **PARTIAL** - Missing `expires` field

**Current Implementation:**
```elixir
defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @type t :: %__MODULE__{
          url: String.t()
        }
  defstruct [:url]
end
```

**What's Missing:**
- `expires` field for URL expiration timestamp
- Datetime handling/parsing
- Expiration validation logic

**Impact:**
- Cannot determine when download URLs expire
- Missing critical information for caching/retry logic
- Users cannot validate URL freshness

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @moduledoc """
  Response containing a download URL for a checkpoint archive.

  The URL is signed and has an expiration time.
  """

  @type t :: %__MODULE__{
          url: String.t(),
          expires: DateTime.t() | nil
        }

  defstruct [:url, :expires]

  @doc """
  Convert a map (from JSON) to a CheckpointArchiveUrlResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    expires = parse_expires(map["expires"] || map[:expires])

    %__MODULE__{
      url: map["url"] || map[:url],
      expires: expires
    }
  end

  @doc """
  Check if the URL has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires: nil}), do: false
  def expired?(%__MODULE__{expires: expires}) do
    DateTime.compare(DateTime.utc_now(), expires) == :gt
  end

  defp parse_expires(nil), do: nil
  defp parse_expires(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end
  defp parse_expires(%DateTime{} = dt), do: dt
  defp parse_expires(_), do: nil
end
```

**Dependencies:**
- Elixir DateTime module

**Test Requirements:**
- expires field parsing (ISO8601 format)
- expired? logic
- nil expires handling
- JSON encoding/decoding with expires

---

### GAP-CKPT-007: Incomplete Checkpoint Time Field

**Severity:** ⚠️ **HIGH**

**Python Implementation:**
```python
# tinker/types/checkpoint.py
class Checkpoint(BaseModel):
    checkpoint_id: str
    checkpoint_type: CheckpointType
    time: datetime
    """The time when the checkpoint was created"""
    tinker_path: str
    size_bytes: int | None = None
    public: bool = False
```

**Elixir Status:** ⚠️ **PARTIAL** - Uses raw string instead of DateTime

**Current Implementation:**
```elixir
defmodule Tinkex.Types.Checkpoint do
  @type t :: %__MODULE__{
          # ... other fields ...
          time: String.t()  # Should be DateTime.t()
        }
end
```

**What's Missing:**
- Proper DateTime type for time field
- Datetime parsing from JSON
- ISO8601 formatting for output

**Impact:**
- Cannot perform datetime operations on checkpoint times
- Less type safety
- Sorting/filtering checkpoints by time is harder

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.Checkpoint do
  @moduledoc """
  Checkpoint metadata.

  Represents a saved model checkpoint with its metadata.
  """

  alias Tinkex.Types.CheckpointType

  @type t :: %__MODULE__{
          checkpoint_id: String.t(),
          checkpoint_type: String.t(),  # or CheckpointType.t() if ported
          tinker_path: String.t(),
          size_bytes: non_neg_integer() | nil,
          public: boolean(),
          time: DateTime.t()  # Changed from String.t()
        }

  defstruct [:checkpoint_id, :checkpoint_type, :tinker_path, :size_bytes, :public, :time]

  @doc """
  Convert a map (from JSON) to a Checkpoint struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    time = parse_time(map["time"] || map[:time])

    %__MODULE__{
      checkpoint_id: map["checkpoint_id"] || map[:checkpoint_id],
      checkpoint_type: map["checkpoint_type"] || map[:checkpoint_type],
      tinker_path: map["tinker_path"] || map[:tinker_path],
      size_bytes: map["size_bytes"] || map[:size_bytes],
      public: map["public"] || map[:public] || false,
      time: time
    }
  end

  defp parse_time(nil), do: nil
  defp parse_time(time_string) when is_binary(time_string) do
    case DateTime.from_iso8601(time_string) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end
  defp parse_time(%DateTime{} = dt), do: dt
end

defimpl Jason.Encoder, for: Tinkex.Types.Checkpoint do
  def encode(checkpoint, opts) do
    time_str = if checkpoint.time, do: DateTime.to_iso8601(checkpoint.time), else: nil

    %{
      checkpoint_id: checkpoint.checkpoint_id,
      checkpoint_type: checkpoint.checkpoint_type,
      tinker_path: checkpoint.tinker_path,
      size_bytes: checkpoint.size_bytes,
      public: checkpoint.public,
      time: time_str
    }
    |> Jason.Encode.map(opts)
  end
end
```

**Dependencies:**
- Elixir DateTime module

**Test Requirements:**
- DateTime parsing from ISO8601
- DateTime encoding to ISO8601
- Sorting checkpoints by time
- nil time handling

---

### GAP-CKPT-008: Limited TensorData Conversion Methods

**Severity:** 🔵 **LOW**

**Python Implementation:**
```python
# tinker/types/tensor_data.py
class TensorData(StrictBase):
    # ... fields ...

    @classmethod
    def from_numpy(cls, array: npt.NDArray[Any]) -> "TensorData":
        # NumPy → TensorData conversion

    @classmethod
    def from_torch(cls, tensor: "torch.Tensor") -> "TensorData":
        # PyTorch → TensorData conversion

    def to_numpy(self) -> npt.NDArray[Any]:
        # TensorData → NumPy conversion

    def to_torch(self) -> "torch.Tensor":
        # TensorData → PyTorch conversion

    def tolist(self) -> List[Any]:
        # TensorData → nested list
```

**Elixir Status:** ⚠️ **PARTIAL** - Only Nx conversions

**Current Implementation:**
```elixir
defmodule Tinkex.Types.TensorData do
  @spec from_nx(Nx.Tensor.t()) :: t()
  def from_nx(%Nx.Tensor{} = tensor) do
    # Nx → TensorData conversion
  end

  @spec to_nx(t()) :: Nx.Tensor.t()
  def to_nx(%__MODULE__{} = data) do
    # TensorData → Nx conversion
  end
end
```

**What's Missing:**
- NumPy conversion methods (not applicable for Elixir)
- PyTorch conversion methods (not applicable for Elixir)
- `tolist()` method for nested list conversion

**Impact:**
- **MINIMAL** - Elixir ecosystem uses Nx instead of NumPy/PyTorch
- Missing `to_list/1` for nested list representation might be useful

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.TensorData do
  # ... existing code ...

  @doc """
  Convert TensorData to a nested list structure.

  Mirrors Python's tolist() method.
  """
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{} = tensor_data) do
    tensor_data
    |> to_nx()
    |> Nx.to_list()
  end
end
```

**Dependencies:**
- None (uses existing Nx conversion)

**Test Requirements:**
- Verify nested list structure matches shape
- Test with various shapes (1D, 2D, 3D)

---

### GAP-CKPT-009: Missing CheckpointType Literal Type

**Severity:** ⚠️ **MEDIUM**

**Python Implementation:**
```python
# tinker/types/checkpoint.py
from typing import Literal

CheckpointType = Literal["training", "sampler"]
```

**Elixir Status:** ❌ **MISSING** - Using raw strings

**What's Missing:**
- Type alias for checkpoint types
- Validation of checkpoint type values
- Type safety for checkpoint type fields

**Impact:**
- Less type safety (any string can be used)
- No validation of checkpoint type values
- Missing documentation for valid values

**Implementation Notes:**
See GAP-CKPT-004 for full implementation - the CheckpointType module should be created alongside ParsedCheckpointTinkerPath.

---

### GAP-CKPT-010: Missing Type Discriminator Constants

**Severity:** 🔵 **LOW**

**Python Implementation:**
```python
# All request/response types use Literal for type field
type: Literal["save_weights"] = "save_weights"
type: Literal["save_weights_for_sampler"] = "save_weights_for_sampler"
type: Literal["load_weights"] = "load_weights"
```

**Elixir Status:** ⚠️ **PARTIAL** - Hardcoded strings

**What's Missing:**
- Module constants for type discriminator values
- Centralized type string definitions

**Impact:**
- Risk of typos in type strings
- Harder to maintain consistency
- No single source of truth for type values

**Implementation Notes:**
```elixir
defmodule Tinkex.Types.RequestTypes do
  @moduledoc """
  Type discriminator constants for WebSocket requests.
  """

  @save_weights "save_weights"
  @save_weights_for_sampler "save_weights_for_sampler"
  @load_weights "load_weights"

  def save_weights, do: @save_weights
  def save_weights_for_sampler, do: @save_weights_for_sampler
  def load_weights, do: @load_weights

  @doc """
  Validate a request type string.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(type) when type in [@save_weights, @save_weights_for_sampler, @load_weights], do: true
  def valid?(_), do: false
end
```

**Dependencies:**
- None

**Test Requirements:**
- Constant values match Python literals
- valid? function works correctly

---

## 3. Checkpoint Path Parsing Deep Dive

### 3.1 Path Format Specification

**Format:** `tinker://<training_run_id>/<checkpoint_type>/<checkpoint_id>`

**Components:**
1. **Protocol:** Always `tinker://`
2. **Training Run ID:** Unique identifier for the training run (e.g., `run-123`)
3. **Checkpoint Type:** Either `weights` (training) or `sampler_weights` (sampler)
4. **Checkpoint ID:** Combined path of type and identifier (e.g., `weights/checkpoint-001`)

**Examples:**
```
tinker://run-123/weights/checkpoint-001
       └─────┬────┘ └──┬──┘ └────────┬────────┘
     training_run_id type    checkpoint_id
                            (combined: "weights/checkpoint-001")

tinker://run-456/sampler_weights/step-5000
       └─────┬────┘ └──────┬───────┘ └───┬───┘
     training_run_id      type      checkpoint_id
                                   (combined: "sampler_weights/step-5000")
```

### 3.2 Validation Rules

1. **Prefix Validation:** Must start with `"tinker://"`
2. **Part Count:** Must have exactly 3 parts after removing prefix
3. **Type Validation:** Second part must be `"weights"` or `"sampler_weights"`
4. **Type Mapping:**
   - `"weights"` → `"training"` checkpoint type
   - `"sampler_weights"` → `"sampler"` checkpoint type

### 3.3 Error Cases

| Invalid Path | Reason | Error Message |
|-------------|--------|---------------|
| `http://run-123/weights/001` | Wrong protocol | "Invalid tinker path: http://run-123/weights/001" |
| `tinker://run-123/weights` | Too few parts | "Invalid tinker path: tinker://run-123/weights" |
| `tinker://run-123/invalid/001` | Invalid type | "Invalid tinker path: tinker://run-123/invalid/001" |
| `tinker://a/b/c/d` | Too many parts | "Invalid tinker path: tinker://a/b/c/d" |

### 3.4 Current Implementation Gap

The Elixir codebase has **no centralized path parsing**. The `CheckpointDownload` module does basic string manipulation:

```elixir
# Current ad-hoc parsing in checkpoint_download.ex
checkpoint_id =
  checkpoint_path
  |> String.replace("tinker://", "")
  |> String.replace("/", "_")
```

This is **insufficient** because:
- No validation of path format
- No extraction of training run ID
- No checkpoint type determination
- No error handling for malformed paths

---

## 4. Tensor Data Type Mapping

### 4.1 Supported Types

Both Python and Elixir support exactly **2 tensor dtypes**:

| Type | Python Literal | Elixir Atom | Nx Type | NumPy Type | PyTorch Type |
|------|---------------|-------------|---------|------------|--------------|
| 32-bit float | `"float32"` | `:float32` | `{:f, 32}` | `np.float32` | `torch.float32` |
| 64-bit integer | `"int64"` | `:int64` | `{:s, 64}` | `np.int64` | `torch.int64` |

### 4.2 Type Conversion Logic

**Python Strategy:**
- Automatic coercion to supported types
- Floating point → `float32`
- Integer → `int64`

**Elixir Strategy (Matches Python):**
- Aggressive casting to match Python SDK behavior
- `{:f, 64}` (float64) → `:float32` (downcast)
- `{:s, 32}` (int32) → `:int64` (upcast)
- `{:u, _}` (unsigned) → `:int64` (upcast)

### 4.3 Wire Format

**JSON Representation:**
```json
{
  "data": [1.0, 2.0, 3.0, 4.0],
  "dtype": "float32",
  "shape": [2, 2]
}
```

**Type Field:** String literal (`"float32"` or `"int64"`)

### 4.4 Conversion Comparison

| Operation | Python | Elixir |
|-----------|--------|--------|
| **From Native** | `from_numpy()`, `from_torch()` | `from_nx()` |
| **To Native** | `to_numpy()`, `to_torch()` | `to_nx()` |
| **To List** | `tolist()` | Missing (see GAP-CKPT-008) |
| **Type Coercion** | In conversion functions | In `normalize_tensor/1` |
| **Validation** | Raises ValueError | Raises ArgumentError |

### 4.5 Unsupported Types

Both implementations **reject** these types:
- BFloat16 (`bf16`)
- Float16 (`f16`)
- Any integer size other than 64-bit in output
- Any float size other than 32-bit in output

---

## 5. Recommendations

### 5.1 Priority 1 (Critical) - Immediate Action Required

1. **Implement Missing Response Types (GAP-CKPT-001, 002, 003)**
   - `SaveWeightsResponse`
   - `SaveWeightsForSamplerResponse` + Internal version
   - `LoadWeightsResponse`
   - **Estimate:** 4-6 hours
   - **Impact:** Unblocks weight save/load operations

2. **Implement ParsedCheckpointTinkerPath (GAP-CKPT-004)**
   - Create CheckpointType module
   - Create ParsedCheckpointTinkerPath module with parser
   - Add comprehensive tests
   - **Estimate:** 6-8 hours
   - **Impact:** Provides standardized path parsing and validation

### 5.2 Priority 2 (High) - Next Sprint

3. **Fix Checkpoint DateTime Handling (GAP-CKPT-007)**
   - Update Checkpoint type to use DateTime.t()
   - Implement parsing and encoding
   - Add tests
   - **Estimate:** 2-3 hours
   - **Impact:** Enables proper checkpoint time operations

4. **Implement Cursor Type (GAP-CKPT-005)**
   - Create Cursor module
   - Update CheckpointsListResponse to use typed cursor
   - Add tests
   - **Estimate:** 2-3 hours
   - **Impact:** Better type safety for pagination

### 5.3 Priority 3 (Medium) - Future Improvement

5. **Fix CheckpointArchiveUrlResponse (GAP-CKPT-006)**
   - Add expires field
   - Implement expiration checking
   - Add tests
   - **Estimate:** 2-3 hours
   - **Impact:** Better URL lifecycle management

6. **Create Type Discriminator Constants (GAP-CKPT-010)**
   - Create RequestTypes module
   - Update existing types to use constants
   - **Estimate:** 1-2 hours
   - **Impact:** Reduces risk of typos

### 5.4 Priority 4 (Low) - Optional Enhancement

7. **Add TensorData.to_list/1 (GAP-CKPT-008)**
   - Implement nested list conversion
   - Add tests
   - **Estimate:** 1 hour
   - **Impact:** Convenience method for data inspection

### 5.5 Refactoring CheckpointDownload

Once ParsedCheckpointTinkerPath is implemented, refactor `CheckpointDownload` module:

```elixir
# Before
checkpoint_id =
  checkpoint_path
  |> String.replace("tinker://", "")
  |> String.replace("/", "_")

# After
{:ok, parsed} = ParsedCheckpointTinkerPath.from_tinker_path(checkpoint_path)
checkpoint_id = "#{parsed.training_run_id}_#{String.replace(parsed.checkpoint_id, "/", "_")}"
```

**Benefits:**
- Validation of checkpoint path format
- Access to structured components
- Better error messages

---

## 6. Testing Strategy

### 6.1 Unit Tests Required

For each new type:
1. **JSON Encoding/Decoding**
   - Round-trip tests
   - Handling of nil/optional fields
   - Both string and atom keys

2. **Field Validation**
   - Required field enforcement
   - Type validation
   - Default values

3. **Edge Cases**
   - Empty/nil values
   - Invalid formats
   - Boundary conditions

### 6.2 Integration Tests Required

1. **ParsedCheckpointTinkerPath**
   - Valid path parsing
   - Invalid path rejection
   - All checkpoint types
   - Error message validation

2. **Response Types**
   - WebSocket response deserialization
   - REST API response deserialization
   - Type discriminator handling

3. **Checkpoint Operations**
   - Full save/load workflow
   - Path parsing in real operations
   - DateTime handling in API calls

### 6.3 Property-Based Tests

Consider property tests for:
1. **Path Parsing** - Valid paths always parse successfully
2. **DateTime Roundtrip** - Encode/decode preserves timestamp
3. **Tensor Conversion** - Nx → TensorData → Nx preserves data

---

## 7. Implementation Checklist

### Phase 1: Critical Gaps (Week 1)
- [ ] Create `SaveWeightsResponse` module
- [ ] Create `SaveWeightsForSamplerResponse` module
- [ ] Create `SaveWeightsForSamplerResponseInternal` module
- [ ] Create `LoadWeightsResponse` module
- [ ] Add tests for all response types
- [ ] Create `CheckpointType` module
- [ ] Create `ParsedCheckpointTinkerPath` module
- [ ] Add comprehensive path parsing tests
- [ ] Update documentation

### Phase 2: High Priority (Week 2)
- [ ] Update `Checkpoint` to use `DateTime.t()`
- [ ] Add DateTime parsing/encoding
- [ ] Add Checkpoint datetime tests
- [ ] Create `Cursor` module
- [ ] Update `CheckpointsListResponse` to use `Cursor.t()`
- [ ] Add cursor tests
- [ ] Update documentation

### Phase 3: Medium Priority (Week 3)
- [ ] Add `expires` field to `CheckpointArchiveUrlResponse`
- [ ] Add expiration checking logic
- [ ] Add tests for expiration
- [ ] Create `RequestTypes` constants module
- [ ] Update existing types to use constants
- [ ] Update documentation

### Phase 4: Enhancements (Week 4)
- [ ] Add `TensorData.to_list/1`
- [ ] Add tests
- [ ] Refactor `CheckpointDownload` to use `ParsedCheckpointTinkerPath`
- [ ] Full integration testing
- [ ] Update documentation

---

## 8. Summary

The Weights & Checkpoints domain shows **65% completeness** with significant gaps in response types and checkpoint path parsing. The most critical issues are:

1. **Missing response types** that block weight save/load operations
2. **No standardized path parsing** leading to scattered validation logic
3. **Incomplete datetime handling** reducing type safety
4. **Missing pagination type** reducing type safety for list operations

These gaps represent **approximately 30-40 hours** of development work spread across 4 priority levels. The implementation should follow the phased approach to unblock critical functionality first while maintaining backward compatibility during the transition.

The tensor type mapping is **complete and correct**, matching Python's aggressive type coercion strategy. The existing Nx integration is well-implemented and appropriate for the Elixir ecosystem.

---

**End of Gap Analysis**
