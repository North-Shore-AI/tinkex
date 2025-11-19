# Type System Analysis

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202. See `203_claude_sonnet_response_to_critiques.md` for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- `AdamParams`: Fixed defaults (beta2: 0.95, eps: 1e-12, learning_rate has default)
- `TensorDtype`: Only 2 types supported (int64, float32)
- `StopReason`: Corrected values ("length", "stop")
- Validation: Using pure functions instead of Ecto for lighter dependencies

**Key Corrections (Round 2 - Critiques 200-202):**
- `ForwardBackwardOutput`: No `loss` field (use `metrics["loss"]`)
- `LossFnType`: Added "importance_sampling", "ppo" values
- `SampleRequest`: Corrected required/optional fields (supports multiple modes)
- `TensorData`: Handle nil shape gracefully
- `Datum`: Added plain list conversion support
- `RequestErrorCategory`: Updated to "unknown", "server", "user"

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

**ForwardBackwardRequest**
```python
class ForwardBackwardRequest(BaseModel):
    forward_backward_input: ForwardBackwardInput
    model_id: ModelID
    seq_id: int  # Sequence ID for request ordering
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

**OptimStepRequest**
```python
class OptimStepRequest(BaseModel):
    adam_params: AdamParams
    model_id: ModelID
    seq_id: int
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

**SampleRequest** ⚠️ CORRECTED
```python
# ACTUAL Python SDK - supports multiple modes
class SampleRequest(BaseModel):
    # Mode 1: Via sampling session (created upfront)
    sampling_session_id: Optional[str] = None
    seq_id: Optional[int] = None

    # Mode 2: Direct model specification (stateless)
    base_model: Optional[str] = None
    model_path: Optional[str] = None

    # Required fields
    prompt: ModelInput
    sampling_params: SamplingParams

    # Optional fields
    num_samples: int = 1
    prompt_logprobs: bool = False
    topk_prompt_logprobs: int = 0

    # Validation: Must specify EITHER session OR model
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

**ForwardBackwardOutput** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
class ForwardBackwardOutput(BaseModel):
    loss_fn_output_type: str  # e.g., "cross_entropy_output"
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
    stop_reason: StopReason  # "max_tokens" | "stop_sequence" | "eos"
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
ModelInputChunk = Union[EncodedTextChunk, ImageChunk, ...]

class EncodedTextChunk(BaseModel):
    tokens: List[int]

    @property
    def length(self) -> int:
        return len(self.tokens)
```

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

**LossFnType** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
LossFnType: TypeAlias = Literal["cross_entropy", "importance_sampling", "ppo"]
# All 3 values already supported by SDK and backend
```

**StopReason** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
StopReason: TypeAlias = Literal["length", "stop"]
# NOT "max_tokens" | "stop_sequence" | "eos"!
```

**TensorDtype** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
TensorDtype: TypeAlias = Literal["int64", "float32"]
# Only 2 types supported, NOT 4!
# float64 and int32 are NOT supported by the backend
```

**RequestErrorCategory** ⚠️ CORRECTED
```python
# ACTUAL Python SDK (verified from source):
class RequestErrorCategory(StrEnum):
    Unknown = auto()  # Unknown error type
    Server = auto()   # Server-side error (retryable)
    User = auto()     # User/client error (not retryable)

# NOT the old values: "user_error", "transient", "fatal"
```

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

**FutureRetrieveResponse**
```python
class FutureRetrieveResponse(BaseModel):
    status: str  # "pending" | "completed" | "failed"
    result: Optional[Dict[str, Any]] = None
    error: Optional[RequestFailedResponse] = None
```

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

### 1. Tensor Conversion ⚠️ UPDATED
- Python: Direct torch.Tensor → TensorData conversion
- Elixir: Need Nx (Numerical Elixir) integration
  - Use `Nx.to_flat_list/1` for serialization
  - Store dtype and shape metadata
  - **Handle nil shape**: When shape is None/nil, treat as 1D array
    ```elixir
    def to_nx(%TensorData{shape: nil, data: data, dtype: dtype}) do
      # No reshape - return as 1D
      Nx.tensor(data, type: tensor_dtype_to_nx(dtype))
    end

    def to_nx(%TensorData{shape: shape, data: data, dtype: dtype}) when is_list(shape) do
      data
      |> Nx.tensor(type: tensor_dtype_to_nx(dtype))
      |> Nx.reshape(List.to_tuple(shape))
    end
    ```

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

### 4. JSON Encoding Strictness ⚠️ NEW
- Prevent internal fields from leaking to API
- Use `@derive {Jason.Encoder, only: [...]}` for explicit control
  ```elixir
  defmodule Tinkex.Types.SampleRequest do
    @derive {Jason.Encoder, only: [
      :sampling_session_id, :seq_id, :num_samples, :base_model, :model_path,
      :prompt, :sampling_params, :prompt_logprobs, :topk_prompt_logprobs
    ]}

    defstruct [...]
  end
  ```
- Ensures only specified fields are serialized to JSON
- Matches Pydantic's `StrictBase` behavior (extra='forbid')

### 5. Immutability
- Elixir structs are immutable by default (advantage!)
- Use `Map.put/3` or struct update syntax for "mutations"
  ```elixir
  %{model_input | chunks: new_chunks}
  ```

### 6. Default Values
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
