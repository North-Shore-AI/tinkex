# Type System Analysis

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202, 300-302, 400+. See response documents for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- `AdamParams`: Fixed defaults (beta2: 0.95, eps: 1e-12, learning_rate has default)
- `TensorDtype`: Only 2 types supported (int64, float32)
- `StopReason`: **NEW discrepancy** — current Python repo exposes `Literal["length", "stop"]` (no `"max_tokens"/"eos"`). Docs updated plus runtime verification note.
- Validation: Using pure functions instead of Ecto for lighter dependencies

**Key Corrections (Round 2 - Critiques 200-202):**
- `ForwardBackwardOutput`: No `loss` field (use `metrics["loss"]`)
- `LossFnType`: Added "importance_sampling", "ppo" values
- `SampleRequest`: Corrected required/optional fields (supports multiple modes)
- `TensorData`: Handle nil shape gracefully
- `Datum`: Added plain list conversion support

**Key Corrections (Round 3 - Critiques 300-302):**
- `RequestErrorCategory`: Parser is case-insensitive for robustness (wire format confirmed as lowercase via StrEnum.auto() behavior)
- Tensor casting: Explicit f64→f32, s32→s64 casting to match Python SDK aggressive type coercion
- `seq_id` optionality: Documented that field is optional in wire format but always set by client

**Key Corrections (Round 4 - Critique 400+):**
- **JSON encoding**: REMOVED global nil-stripping - Python SDK accepts `null` for Optional fields
- **NotGiven clarification**: `NotGiven` is used in client options, NOT request schemas
- **Error categories**: Wire format uses lowercase ("unknown"/"server"/"user") per StrEnum.auto() behavior

**Key Corrections (Round 5 - Final):**
- **Tokenizer scope**: Clarified that `tokenizers` NIF provides raw tokenization only; NO chat template support in v1.0
- **Image handling**: Clarified v1.0 supports JSON-based images (ImageChunk/ImageAssetPointerChunk); multipart deferred to v2.0

## Python Type Infrastructure

The Tinker SDK uses Pydantic extensively for type validation and serialization. All types inherit from either `BaseModel` or `StrictBase`.

### Base Model Hierarchy

```python
# _models.py
class StrictBase(BaseModel):
    """Base class with strict validation"""
    # Pydantic v2: model_config with strict=True
    # Pydantic v1: Config class with extra='forbid'
```

### Core Type Categories

## 1. Request Types

Request types represent data sent to the API:

### Training Requests

**ForwardBackwardRequest** ⚠️ UPDATED (Round 3)
```python
class ForwardBackwardRequest(BaseModel):
    forward_backward_input: ForwardBackwardInput
    model_id: ModelID
    seq_id: Optional[int] = None  # Optional in schema, but client ALWAYS sets it

# NOTE: While seq_id is Optional in the Python wire schema, the client
# implementation ALWAYS sets it. Server semantics assume monotonic sequence
# per model. Document this as: "Optional in wire format, always set by client."
```

**ForwardBackwardInput**
```python
class ForwardBackwardInput(BaseModel):
    data: List[Datum]  # Training examples
    loss_fn: LossFnType  # e.g., "cross_entropy"
    loss_fn_config: Dict[str, float] | None
```

**Datum** (Training Example)
```python
class Datum(StrictBase):
    model_input: ModelInput  # Tokenized input sequence
    loss_fn_inputs: LossFnInputs  # Dict[str, TensorData]

    # Automatic conversion: torch.Tensor → TensorData
    @model_validator(mode="before")
    def convert_tensors(cls, data): ...
```

**OptimStepRequest** ⚠️ UPDATED (Round 3)
```python
class OptimStepRequest(BaseModel):
    adam_params: AdamParams
    model_id: ModelID
    seq_id: Optional[int] = None  # Optional in schema, but client ALWAYS sets it
```

**AdamParams** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
class AdamParams(StrictBase):
    learning_rate: float = 0.0001  # Has default!
    beta1: float = 0.9
    beta2: float = 0.95            # NOT 0.999!
    eps: float = 1e-12             # Named 'eps', NOT 'epsilon'!
    # Note: No weight_decay field in actual SDK
```

### Sampling Requests

**SampleRequest** ⚠️ CORRECTED (Round 7)
```python
# ACTUAL Python SDK (verified from tinker/types/sample_request.py):
class SampleRequest(StrictBase):
    # Mode 1: Via sampling session (created upfront)
    sampling_session_id: Optional[str] = None
    seq_id: Optional[int] = None

    # Mode 2: Direct model specification (stateless)
    base_model: Optional[str] = None
    model_path: Optional[str] = None

    # Required fields
    prompt: ModelInput
    sampling_params: SamplingParams

    # Optional fields with defaults
    num_samples: int = 1
    prompt_logprobs: Optional[bool] = None  # ⚠️ NOT `bool = False`!
    topk_prompt_logprobs: int = 0

    # Validation: Must specify EITHER session OR model
```

**⚠️ CRITICAL:** `prompt_logprobs` is `Optional[bool] = None`, NOT `bool = False`.

This distinction matters:
- `None` → `{"prompt_logprobs": null}` or omitted
- `False` → `{"prompt_logprobs": false}` explicitly
- Python allows distinguishing "not set" from "explicitly false"

**Elixir mapping:**
```elixir
defmodule Tinkex.Types.SampleRequest do
  defstruct [
    :sampling_session_id,   # nil → null
    :seq_id,                # nil → null
    :base_model,            # nil → null
    :model_path,            # nil → null
    :prompt,                # required
    :sampling_params,       # required
    num_samples: 1,
    prompt_logprobs: nil,   # ⚠️ nil (NOT false) to match Python
    topk_prompt_logprobs: 0
  ]

  @type t :: %__MODULE__{
    sampling_session_id: String.t() | nil,
    seq_id: integer() | nil,
    base_model: String.t() | nil,
    model_path: String.t() | nil,
    prompt: ModelInput.t(),
    sampling_params: SamplingParams.t(),
    num_samples: pos_integer(),
    prompt_logprobs: boolean() | nil,  # Tri-state: nil | true | false
    topk_prompt_logprobs: non_neg_integer()
  }
end
```

**SamplingParams**
```python
class SamplingParams(BaseModel):
    max_tokens: Optional[int] = None
    seed: Optional[int] = None
    stop: Union[str, Sequence[str], Sequence[int], None] = None
    temperature: float = 1.0
    top_k: int = -1
    top_p: float = 1.0
```

### Model Management Requests

**CreateModelRequest**
```python
class CreateModelRequest(BaseModel):
    session_id: str
    model_seq_id: int
    base_model: str  # e.g., "Qwen/Qwen2.5-7B"
    lora_config: LoraConfig
    user_metadata: Dict[str, str] | None
```

**LoraConfig**
```python
class LoraConfig(BaseModel):
    rank: int = 32
    seed: Optional[int] = None
    train_mlp: bool = True
    train_attn: bool = True
    train_unembed: bool = True
```

## 2. Response Types

Response types represent data received from the API:

**ForwardBackwardOutput** ⚠️ CORRECTED (v0.4.1)
```python
# ACTUAL Python SDK v0.4.1 (verified from source):
class ForwardBackwardOutput(BaseModel):
    loss_fn_output_type: str  # Type discriminator for loss_fn_outputs
    loss_fn_outputs: List[LossFnOutput]  # Per-example outputs (typed)
    metrics: Dict[str, float]  # Aggregated metrics
    # NOTE: No 'loss' field! Loss is in metrics["loss"]
```

**SampleResponse**
```python
class SampleResponse(BaseModel):
    sequences: List[SampledSequence]
    prompt_logprobs: Optional[List[Optional[float]]] = None
```

**SampledSequence**
```python
class SampledSequence(BaseModel):
    tokens: List[int]
    logprobs: List[float]
    stop_reason: StopReason  # Literal["length", "stop"] in repo snapshot
```

**CreateModelResponse**
```python
class CreateModelResponse(BaseModel):
    model_id: ModelID
```

## 3. Data Structure Types

**ModelInput** (Token Sequence)
```python
class ModelInput(BaseModel):
    chunks: List[ModelInputChunk]  # Can mix token and image chunks

    @classmethod
    def from_ints(cls, tokens: List[int]) -> ModelInput:
        return cls(chunks=[EncodedTextChunk(tokens=tokens)])

    def to_ints(self) -> List[int]:
        # Flatten all token chunks
        ...

    @property
    def length(self) -> int:
        return sum(chunk.length for chunk in self.chunks)
```

**ModelInputChunk** (Abstract)
```python
# Union type for different chunk kinds
ModelInputChunk = Union[EncodedTextChunk, ImageChunk, ImageAssetPointerChunk, ...]

class EncodedTextChunk(BaseModel):
    tokens: List[int]

    @property
    def length(self) -> int:
        return len(self.tokens)

class ImageChunk(StrictBase):
    """Image data with base64 encoding in JSON"""
    data: bytes  # base64-encoded via Pydantic serializer
    format: Literal["png", "jpeg"]
    height: int
    width: int
    tokens: int  # Context length consumed
    type: Literal["image"] = "image"

class ImageAssetPointerChunk(StrictBase):
    """Reference to pre-uploaded image asset"""
    location: str  # Asset identifier/URL
    format: Literal["png", "jpeg"]
    height: int
    width: int
    tokens: int  # Context length consumed
    type: Literal["image_asset_pointer"] = "image_asset_pointer"
```

**⚠️ CRITICAL CORRECTION (Round 7):**

Previous docs showed WRONG field names (`image_data`, `image_format`, `asset_id`). **Actual Python SDK fields are:**
- `data` (NOT `image_data`) - bytes serialized as base64 string
- `format` (NOT `image_format`) - "png" | "jpeg"
- `location` (NOT `asset_id`) - for ImageAssetPointerChunk
- Required dimension fields: `height`, `width`, `tokens`
- Type discriminator: `type` field

**v1.0 Scope Clarification - Image Handling:**

The Python SDK's `_files.py` supports sophisticated `multipart/form-data` uploads, but the **public Tinker API** uses JSON-based image types with these exact field names.

**Elixir v1.0 Support:**
- ✅ JSON-based image types with CORRECT field names (`data`, `format`, `location`, `height`, `width`, `tokens`, `type`)
- ❌ Raw multipart file uploads (deferred to v2.0 unless API requires it)

**Elixir Implementation:**
```elixir
defmodule Tinkex.Types.ImageChunk do
  @derive Jason.Encoder
  defstruct [:data, :format, :height, :width, :tokens, :type]

  @type t :: %__MODULE__{
    data: String.t(),  # base64-encoded string
    format: :png | :jpeg,
    height: pos_integer(),
    width: pos_integer(),
    tokens: non_neg_integer(),
    type: :image
  }

  def new(image_binary, format, height, width, tokens) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      height: height,
      width: width,
      tokens: tokens,
      type: :image
    }
  end
end

defmodule Tinkex.Types.ImageAssetPointerChunk do
  @derive Jason.Encoder
  defstruct [:location, :format, :height, :width, :tokens, :type]

  @type t :: %__MODULE__{
    location: String.t(),
    format: :png | :jpeg,
    height: pos_integer(),
    width: pos_integer(),
    tokens: non_neg_integer(),
    type: :image_asset_pointer
  }
end
```

**Why This Matters:**
- Using wrong field names (`image_data` instead of `data`) will generate JSON the API rejects
- Missing required fields (`height`, `width`, `tokens`, `type`) will cause validation errors
- This is a **breaking correctness bug** if implemented as originally documented

**TensorData** (Numerical Arrays) ⚠️ CORRECTED
```python
class TensorData(BaseModel):
    data: List[float] | List[int]  # 1D array
    dtype: TensorDtype  # "int64" | "float32"
    shape: Optional[List[int]] = None  # ⚠️ OPTIONAL! Can be None

    @classmethod
    def from_torch(cls, tensor: torch.Tensor) -> TensorData:
        return cls(
            data=tensor.cpu().numpy().flatten().tolist(),
            dtype=_torch_to_tensor_dtype(tensor.dtype),
            shape=list(tensor.shape) if tensor.shape else None
        )

    @classmethod
    def from_numpy(cls, array: np.ndarray) -> TensorData:
        ...

    # When shape is None, treat as 1D array
```

## 4. Enum Types

**LossFnType** ⚠️ CORRECTED (v0.4.1)
```python
# ACTUAL Python SDK v0.4.1 (verified from source):
LossFnType: TypeAlias = Literal["cross_entropy", "importance_sampling", "ppo"]
# Only 3 values supported by SDK and backend
```

**StopReason** ⚠️ CORRECTED (v0.4.1)
```python
# tinker/types/stop_reason.py (repo snapshot used for this port):
StopReason: TypeAlias = Literal["length", "stop"]

# ⚠️ Action item:
# Older releases reportedly exposed "max_tokens" | "stop_sequence" | "eos".
# The current repo emits ONLY "length" and "stop". Confirm with live API
# before shipping to ensure we are not missing newer wire values.
```

**TensorDtype** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
TensorDtype: TypeAlias = Literal["int64", "float32"]
# Only 2 types supported, NOT 4!
# float64 and int32 are NOT supported by the backend
```

**RequestErrorCategory** ⚠️ CORRECTED (v0.4.1)

```python
# tinker/types/request_error_category.py
class RequestErrorCategory(StrEnum):
    Unknown = auto()
    Server = auto()
    User = auto()

# WIRE FORMAT:
# - Standard StrEnum.auto() returns the LOWERCASE member name in Python 3.11+
# - RequestErrorCategory.Unknown.value == "unknown"  (lowercase!)
# - RequestErrorCategory.Server.value == "server"    (lowercase!)
# - RequestErrorCategory.User.value == "user"        (lowercase!)
# - Pydantic serializes enums using .value, so JSON contains lowercase strings
# - JSON wire format: {"category": "unknown" | "server" | "user"}
```

**Elixir Parser (case-insensitive for robustness):**

```elixir
defmodule Tinkex.Types.RequestErrorCategory do
  @moduledoc """
  Request error category parser.

  The Python SDK uses StrEnum with auto(), which produces lowercase wire values:
  - JSON contains: "unknown" | "server" | "user" (all lowercase)
  - Parser is case-insensitive as a defensive measure against format changes
  """

  @type t :: :unknown | :server | :user

  @spec parse(String.t() | nil) :: t()
  def parse(value) when is_binary(value) do
    # Normalize to lowercase (wire format is already lowercase, but be defensive)
    case String.downcase(value) do
      "server" -> :server
      "user" -> :user
      "unknown" -> :unknown
      _ -> :unknown
    end
  end

  def parse(_), do: :unknown

  @doc "Check if error category is retryable"
  def retryable?(:server), do: true
  def retryable?(:unknown), do: true
  def retryable?(:user), do: false
end
```

**Why This Matters:**
- The wire format uses **lowercase** ("unknown", "server", "user") due to StrEnum.auto() behavior
- Case-insensitive parser provides robustness against potential format changes
- Using capitalized values in pattern matching would cause API response parsing to fail
- Elixir atoms (:unknown, :server, :user) correctly represent the lowercase wire values

## 5. Future Types

**UntypedAPIFuture** (Server-side promise)
```python
class UntypedAPIFuture(BaseModel):
    request_id: str  # UUID for polling
```

**FutureRetrieveRequest**
```python
class FutureRetrieveRequest(BaseModel):
    request_id: str
```

**FutureRetrieveResponse** ⚠️ CORRECTED (v0.4.1)
```python
class FuturePendingResponse(BaseModel):
    status: Literal["pending"]

class FutureCompletedResponse(BaseModel):
    status: Literal["completed"]
    result: Dict[str, Any]

class FutureFailedResponse(BaseModel):
    status: Literal["failed"]
    error: RequestFailedResponse

# New in repo snapshot: queue-state backpressure
class TryAgainResponse(BaseModel):
    type: Literal["try_again"]
    request_id: str
    queue_state: Literal["active", "paused_capacity", "paused_rate_limit"]
    retry_after_ms: int | None = None

FutureRetrieveResponse: TypeAlias = Union[
    FuturePendingResponse,
    FutureCompletedResponse,
    FutureFailedResponse,
    TryAgainResponse,
]
```

**Why This Matters:**
- The simplified `{status,result,error}` struct in earlier docs would have dropped `TryAgainResponse`.
- `_APIFuture._result_async` branches on each variant, so the Elixir port must mirror the union.
- `queue_state` is critical for matching Python's graceful backpressure behavior.

## Elixir Mapping Strategy

### 1. Use Typed Structs

```elixir
defmodule Tinkex.Types.SamplingParams do
  @moduledoc "Parameters for text generation"

  @type t :: %__MODULE__{
    max_tokens: non_neg_integer() | nil,
    seed: integer() | nil,
    stop: String.t() | [String.t()] | [integer()] | nil,
    temperature: float(),
    top_k: integer(),
    top_p: float()
  }

  @enforce_keys []
  defstruct [
    :max_tokens,
    :seed,
    :stop,
    temperature: 1.0,
    top_k: -1,
    top_p: 1.0
  ]
end
```

### 2. Validation with Pure Functions (Lighter than Ecto) ⚠️ UPDATED

```elixir
defmodule Tinkex.Types.AdamParams do
  @moduledoc "Adam optimizer parameters - CORRECTED to match Python SDK"

  defstruct [:learning_rate, :beta1, :beta2, :eps]

  @type t :: %__MODULE__{
    learning_rate: float(),
    beta1: float(),
    beta2: float(),
    eps: float()
  }

  @doc "Create AdamParams with defaults matching Python SDK"
  def new(attrs \\ %{}) do
    with {:ok, lr} <- validate_learning_rate(attrs[:learning_rate] || 0.0001),
         {:ok, b1} <- validate_beta(attrs[:beta1] || 0.9),
         {:ok, b2} <- validate_beta(attrs[:beta2] || 0.95),  # NOT 0.999!
         {:ok, eps} <- validate_epsilon(attrs[:eps] || 1.0e-12) do  # NOT 1e-8!
      {:ok, %__MODULE__{
        learning_rate: lr,
        beta1: b1,
        beta2: b2,
        eps: eps  # Field name is 'eps', NOT 'epsilon'!
      }}
    end
  end

  defp validate_learning_rate(lr) when is_float(lr) and lr > 0, do: {:ok, lr}
  defp validate_learning_rate(_), do: {:error, "learning_rate must be positive float"}

  defp validate_beta(b) when is_float(b) and b >= 0 and b < 1, do: {:ok, b}
  defp validate_beta(_), do: {:error, "beta must be in [0, 1)"}

  defp validate_epsilon(eps) when is_float(eps) and eps > 0, do: {:ok, eps}
  defp validate_epsilon(_), do: {:error, "epsilon must be positive float"}
end
```

**Note:** Using pure functions instead of Ecto.Changeset keeps dependencies lighter for an HTTP client SDK.

### 3. JSON Encoding/Decoding with Jason

```elixir
defmodule Tinkex.Types.ModelInput do
  @derive Jason.Encoder
  defstruct [:chunks]

  @type t :: %__MODULE__{
    chunks: [Tinkex.Types.ModelInputChunk.t()]
  }

  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%Tinkex.Types.EncodedTextChunk{tokens: tokens}]
    }
  end

  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %{tokens: tokens} -> tokens
      _ -> raise "Cannot convert non-token chunk to ints"
    end)
  end

  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, & &1.length))
  end
end
```

### 4. Protocol-based Polymorphism

```elixir
defprotocol Tinkex.Types.Chunk do
  @doc "Get the context length used by this chunk"
  def length(chunk)
end

defimpl Tinkex.Types.Chunk, for: Tinkex.Types.EncodedTextChunk do
  def length(%{tokens: tokens}), do: length(tokens)
end
```

## Key Porting Considerations

### 1. Tensor Conversion with Aggressive Casting ⚠️ UPDATED (Round 3)

**CRITICAL:** Python SDK aggressively casts dtypes to match backend support:
- `float64` → `float32` (downcast)
- `int32` → `int64` (upcast)
- `uint*` → `int64` (upcast unsigned)

**Problem:** Standard Elixir floats are 64-bit. Without explicit casting, user inputs will be rejected or encoded incorrectly.

**Solution:**

```elixir
defmodule Tinkex.Types.TensorData do
  defstruct [:data, :dtype, :shape]

  @type dtype :: :int64 | :float32
  @type t :: %__MODULE__{
    data: list(number()),
    dtype: dtype(),
    shape: list(non_neg_integer()) | nil
  }

  @doc "Create TensorData from Nx tensor with aggressive casting (matches Python SDK)"
  def from_nx(%Nx.Tensor{} = tensor) do
    # Cast to supported types (matches Python _convert_numpy_dtype_to_tensor)
    casted_dtype = case tensor.type do
      {:f, 64} -> {:f, 32}  # Downcast f64 -> f32 (CRITICAL!)
      {:f, 32} -> {:f, 32}
      {:s, 32} -> {:s, 64}  # Upcast s32 -> s64
      {:s, 64} -> {:s, 64}
      {:u, _} -> {:s, 64}   # Upcast unsigned -> s64
      other -> raise ArgumentError, "Unsupported dtype: #{inspect(other)}"
    end

    tensor = if casted_dtype != tensor.type do
      Nx.as_type(tensor, casted_dtype)
    else
      tensor
    end

    %__MODULE__{
      data: Nx.to_flat_list(tensor),
      dtype: nx_dtype_to_tensor_dtype(casted_dtype),
      shape: Tuple.to_list(tensor.shape)
    }
  end

  @doc "Convert to Nx tensor"
  def to_nx(%__MODULE__{shape: nil, data: data, dtype: dtype}) do
    # No reshape - return as 1D
    Nx.tensor(data, type: tensor_dtype_to_nx(dtype))
  end

  def to_nx(%__MODULE__{shape: shape, data: data, dtype: dtype}) when is_list(shape) do
    data
    |> Nx.tensor(type: tensor_dtype_to_nx(dtype))
    |> Nx.reshape(List.to_tuple(shape))
  end

  defp nx_dtype_to_tensor_dtype({:f, 32}), do: :float32
  defp nx_dtype_to_tensor_dtype({:s, 64}), do: :int64

  defp tensor_dtype_to_nx(:float32), do: {:f, 32}
  defp tensor_dtype_to_nx(:int64), do: {:s, 64}
end
```

**Why This Matters:**
- Elixir's default float is `f64` - without casting, every float tensor fails
- Python SDK's `_convert_numpy_dtype_to_tensor` does this automatically
- Backend only accepts `int64` and `float32`, nothing else

### 2. Union Types
- Python: Pydantic handles `Union[A, B]` with discriminated unions
- Elixir: Use tagged tuples or explicit type field
  ```elixir
  # Option 1: Tagged tuples
  {:text_chunk, %EncodedTextChunk{}}
  {:image_chunk, %ImageChunk{}}

  # Option 2: Type field
  %{type: :text, data: %EncodedTextChunk{}}
  ```

### 3. Validation Strategy
- Use pure functions for validation (lighter than Ecto)
- Simple structs can use pattern matching + guards
- Consider `norm` or `vex` libraries for additional validation

### 4. JSON Encoding Strategy ⚠️ CRITICAL - DO NOT GLOBALLY STRIP NILS

**THE RULE:** Mirror Python's behavior exactly - `nil` → `"null"` in JSON for request bodies.

**Where NotGiven is Actually Used (client options, NOT request models):**
```python
# Python SDK uses NotGiven for REQUEST OPTIONS (internal)
class FinalRequestOptions:
    headers: Headers | NotGiven = NOT_GIVEN
    max_retries: int | NotGiven = NOT_GIVEN
    timeout: float | NotGiven = NOT_GIVEN

# But REQUEST MODELS use Optional[...] = None (allows null)
class SampleRequest(BaseModel):
    sampling_session_id: Optional[str] = None  # → {"sampling_session_id": null} is valid!
    base_model: Optional[str] = None           # → {"base_model": null} is valid!
```

**What Python Actually Sends:**
- For request bodies (`SampleRequest`, `ForwardBackwardRequest`, etc.): `None` → `null` in JSON
- For internal options: `NotGiven` fields are omitted when building the request
- The API server **accepts `null`** for Optional fields in request bodies

**❌ WRONG - Global Nil Stripping:**
```elixir
# DO NOT DO THIS - breaks semantic difference between "not set" and "explicitly null"
defmodule Tinkex.JSON do
  def encode!(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)  # ❌ Global stripping
    |> Jason.encode!()
  end
end
```

**Why Global Stripping is Wrong:**
1. Python sends `{"field": null}`, Elixir would send `{}` → different semantics
2. Prevents distinguishing "not set" from "explicitly null" if API ever needs it
3. Not what the Python SDK actually does for request bodies

**✅ CORRECT - Approach 1: Natural nil → null (RECOMMENDED)**

Let Jason encode `nil` as `null` naturally:

```elixir
defmodule Tinkex.Types.SampleRequest do
  @derive {Jason.Encoder, only: [
    :sampling_session_id, :seq_id, :num_samples, :base_model, :model_path,
    :prompt, :sampling_params, :prompt_logprobs, :topk_prompt_logprobs
  ]}

  defstruct [
    :sampling_session_id,   # nil → null
    :seq_id,                # nil → null
    :base_model,            # nil → null
    :model_path,            # nil → null
    :prompt,                # required
    :sampling_params,       # required
    num_samples: 1,         # has default
    prompt_logprobs: nil,   # tri-state: nil | true | false
    topk_prompt_logprobs: 0 # has default
  ]
end

# Encoding
body = Jason.encode!(request)  # nil fields → "null" in JSON (matches Python's Optional defaults)
```

**Approach 2: Field-level omission (if needed later)**

If future fields require omitting `null` vs sending it:

```elixir
defmodule Tinkex.JSON do
  @moduledoc """
  JSON encoding with field-level control.

  Use when specific fields must be omitted rather than sent as null.
  """

  @doc "Encode struct, omitting fields listed in :omit_if_nil option"
  def encode!(struct, opts \\ []) do
    omit_if_nil = Keyword.get(opts, :omit_if_nil, [])

    map = Map.from_struct(struct)
    |> Enum.reject(fn {k, v} -> k in omit_if_nil and is_nil(v) end)
    |> Enum.into(%{})

    Jason.encode!(map)
  end
end

# Usage (only if specific field requires it)
Tinkex.JSON.encode!(request, omit_if_nil: [:optional_field])
```

**Field Control:** Use `@derive {Jason.Encoder, only: [...]}` to prevent internal fields from leaking:
  ```elixir
  defmodule Tinkex.Types.SampleRequest do
    @derive {Jason.Encoder, only: [
      :sampling_session_id, :seq_id, :num_samples, :base_model, :model_path,
      :prompt, :sampling_params, :prompt_logprobs, :topk_prompt_logprobs
    ]}

    defstruct [...]
  end
  ```

**Why This Matters:**
- Unconditionally stripping `nil` changes semantics (can't distinguish "not set" from "explicitly null")
- If server ever differentiates these cases, Elixir client would behave differently than Python
- Safer to match Python's behavior: let Optional fields be `null` in JSON

### 5. Error Category Parsing ⚠️ UPDATED (Round 3+4)

**Wire Format:** The JSON wire format uses lowercase `"unknown"/"server"/"user"` due to StrEnum.auto() behavior in Python 3.11+. The parser below uses case-insensitive matching as a defensive measure against potential format changes.

```elixir
defmodule Tinkex.Types.RequestErrorCategory do
  @moduledoc """
  Request error category (StrEnum in Python).
  Wire format: "unknown" | "server" | "user" (lowercase).
  Parser accepts any casing for defensive robustness.
  """

  @type t :: :unknown | :server | :user

  @doc "Parse from JSON string (case-insensitive) to atom (lowercase)"
  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "server" -> :server
      "user" -> :user
      "unknown" -> :unknown
      _ -> :unknown
    end
  end

  def parse(_), do: :unknown

  @doc "Check if error category is retryable"
  def retryable?(:server), do: true
  def retryable?(:unknown), do: true
  def retryable?(:user), do: false
end
```

**Usage in error handling (matches Python is_user_error logic):**
```elixir
defmodule Tinkex.Error do
  defstruct [:status, :message, :category, :data, :retry_after_ms]

  @type t :: %__MODULE__{
    status: integer() | nil,
    message: String.t(),
    category: Tinkex.Types.RequestErrorCategory.t() | nil,
    data: map() | nil,
    retry_after_ms: non_neg_integer() | nil
  }

  @doc """
  Check if error is a user error (matches Python is_user_error logic).

  Truth table:
  | Condition | User Error? | Retryable? |
  |-----------|-------------|------------|
  | category == :user | YES | NO |
  | status 4xx (except 408, 429) | YES | NO |
  | category == :server | NO | YES |
  | category == :unknown | NO | YES |
  | status 5xx | NO | YES |
  | status 408 | NO | YES |
  | status 429 | NO | YES (with backoff) |
  | Connection errors | NO | YES |
  """
  def user_error?(%__MODULE__{status: status, category: category}) do
    cond do
      # RequestFailedError with category User
      category == :user -> true

      # 4xx except 408 (timeout) and 429 (rate limit)
      status in 400..499 and status not in [408, 429] -> true

      # Everything else (5xx, server/unknown category, connection errors)
      true -> false
    end
  end

  @doc "Check if error is retryable"
  def retryable?(error) do
    not user_error?(error)
  end
end
```

### 6. Tokenizer Responsibilities and Chat Templates ⚠️ NEW (Round 5)

**CRITICAL CLARIFICATION:** The Elixir port uses the `tokenizers` NIF (Rust bindings to HuggingFace tokenizers) instead of the full `transformers` library to keep dependencies lean (~5MB vs 100+MB).

**What This Means for v1.0:**

The `tokenizers` library provides:
- ✅ Raw text → token IDs encoding
- ✅ Token IDs → text decoding
- ✅ Special tokens (BOS, EOS, PAD, etc.)
- ✅ Vocabulary and merges

It does **NOT** provide:
- ❌ Chat template application (`chat_template` from tokenizer_config.json)
- ❌ Instruction formatting for fine-tuned models
- ❌ Automatic prompt engineering

**Elixir v1.0 Design Decision:**

```elixir
defmodule Tinkex.Tokenizer do
  @moduledoc """
  Text tokenization using HuggingFace tokenizers (Rust NIF).

  IMPORTANT: This module provides RAW tokenization only.
  You are responsible for applying chat templates or instruction
  formatting BEFORE passing text to encode/2.

  For chat-based models (ChatML, Llama-3-Instruct, etc.), format
  your prompts according to the model's expected structure before
  tokenization.
  """

  @doc """
  Encode text to token IDs.

  NOTE: Does NOT apply chat templates. If you're using an instruction-tuned
  model, format your text according to the model's chat template BEFORE
  calling this function.

  ## Example

      # Raw tokenization (what we provide)
      tokens = Tinkex.Tokenizer.encode("Hello, world!", "gpt2")

      # For chat models, YOU format the prompt:
      formatted_prompt = \"\"\"
      <|im_start|>system
      You are a helpful assistant.<|im_end|>
      <|im_start|>user
      Hello!<|im_end|>
      <|im_start|>assistant
      \"\"\"
      tokens = Tinkex.Tokenizer.encode(formatted_prompt, "Qwen/Qwen2.5-7B-Instruct")
  """
  def encode(text, model_name) do
    # Implementation using tokenizers NIF
    ...
  end
end
```

**Alternative (Future v2.0):**

If chat template support becomes critical, we can:
1. Parse `tokenizer_config.json` to extract `chat_template` (Jinja2 template)
2. Implement Jinja2 renderer in Elixir or shell out to Python
3. Add `Tinkex.Chat.format/2` helper

For v1.0, **explicit documentation** that users must handle chat formatting is sufficient.

**Why This Matters:**
- Prevents surprise when users expect automatic chat template application
- Aligns expectations with actual HF `tokenizers` library capabilities
- Provides clear upgrade path for v2.0 if needed

### 7. Immutability
- Elixir structs are immutable by default (advantage!)
- Use `Map.put/3` or struct update syntax for "mutations"
  ```elixir
  %{model_input | chunks: new_chunks}
  ```

### 8. Default Values
- Elixir structs support default values in defstruct
- For complex defaults, use constructor functions:
  ```elixir
  def new(opts \\ []) do
    struct(__MODULE__, Keyword.merge(defaults(), opts))
  end
  ```

## Recommended Libraries

1. **Ecto**: Schema definition and changeset validation
2. **Jason**: Fast JSON encoding/decoding
3. **Nx**: Numerical computing (tensor operations)
4. **TypedStruct**: Macro for cleaner struct definitions with types

## Example: Complete Type Definition ⚠️ UPDATED

```elixir
defmodule Tinkex.Types.Datum do
  use TypedStruct

  typedstruct do
    field :model_input, Tinkex.Types.ModelInput.t(), enforce: true
    field :loss_fn_inputs, map(), enforce: true
  end

  @doc """
  Create a new datum with tensor auto-conversion.

  Converts:
  - Nx.Tensor → TensorData
  - TensorData → TensorData (passthrough)
  - Plain lists → TensorData (with dtype inference)
  """
  def new(attrs) do
    %__MODULE__{
      model_input: attrs[:model_input],
      loss_fn_inputs: convert_tensors(attrs[:loss_fn_inputs])
    }
  end

  defp convert_tensors(inputs) when is_map(inputs) do
    Map.new(inputs, fn {key, value} ->
      {key, maybe_convert_tensor(value, key)}
    end)
  end

  # Nx.Tensor → TensorData
  defp maybe_convert_tensor(%Nx.Tensor{} = tensor, _key) do
    Tinkex.Types.TensorData.from_nx(tensor)
  end

  # TensorData → passthrough
  defp maybe_convert_tensor(%Tinkex.Types.TensorData{} = td, _key), do: td

  # Plain list → TensorData (with dtype inference)
  defp maybe_convert_tensor(list, key) when is_list(list) do
    dtype = infer_dtype(list, key)
    %Tinkex.Types.TensorData{
      data: list,
      dtype: dtype,
      shape: [length(list)]
    }
  end

  # Other values → passthrough
  defp maybe_convert_tensor(value, _key), do: value

  # Infer dtype from first element or key name
  defp infer_dtype([first | _], _key) when is_integer(first), do: :int64
  defp infer_dtype([first | _], _key) when is_float(first), do: :float32
  defp infer_dtype([], _key), do: :float32
end
```

## Next Steps

See `02_client_architecture.md` for analysis of the client implementation patterns.
