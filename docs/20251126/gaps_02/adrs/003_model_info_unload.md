# ADR-003: Model Info and Unload Endpoint Support

## Status
Proposed

## Context

### Current State Analysis

The Python Tinker SDK exposes comprehensive model metadata retrieval and model unloading capabilities through the `AsyncModelsResource` class, while the Elixir Tinkex port has a stub implementation that returns "not implemented" errors.

### Python Implementation

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\resources\models.py`

The Python SDK provides three methods in `AsyncModelsResource` (lines 18-159):

#### 1. Model Creation (Implemented in Elixir)
```python
async def create(self, request: CreateModelRequest) -> UntypedAPIFuture:
    """Creates a new model. Pass a LoRA config to create a new LoRA adapter."""
    return await self._post(
        "/api/v1/create_model",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=UntypedAPIFuture,
    )
```

#### 2. Get Model Info (NOT implemented in Elixir)
```python
async def get_info(self, request: GetInfoRequest) -> GetInfoResponse:
    """Retrieves information about the current model"""
    return await self._post(
        "/api/v1/get_info",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=GetInfoResponse,
    )
```

**Request Type:** `tinker/src/tinker/types/get_info_request.py` (lines 11-18)
```python
class GetInfoRequest(StrictBase):
    model_id: ModelID
    type: Literal["get_info"] = "get_info"
```

**Response Type:** `tinker/src/tinker/types/get_info_response.py` (lines 10-33)
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

#### 3. Unload Model (NOT implemented in Elixir)
```python
async def unload(self, request: UnloadModelRequest) -> UntypedAPIFuture:
    """Unload the model weights and ends the user's session."""
    return await self._post(
        "/api/v1/unload_model",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=UntypedAPIFuture,
    )
```

**Request Type:** `tinker/src/tinker/types/unload_model_request.py` (lines 11-18)
```python
class UnloadModelRequest(StrictBase):
    model_id: ModelID
    type: Literal["unload_model"] = "unload_model"
```

**Response Type:** `tinker/src/tinker/types/unload_model_response.py` (lines 11-14)
```python
class UnloadModelResponse(BaseModel):
    model_id: ModelID
    type: Optional[Literal["unload_model"]] = None
```

### Python Client Usage

The Python client exposes these methods via:
- **Client:** `AsyncTinker` (line 120-123 in `_client.py`)
- **Resource Property:** `client.models` → `AsyncModelsResource`
- **High-level API:** `TrainingClient.get_info()` (lines 689-723 in `training_client.py`)

**TrainingClient Integration:**
```python
def get_info(self) -> types.GetInfoResponse:
    """Get information about the current model."""
    async def _get_info_async():
        with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
            request = types.GetInfoRequest(model_id=self._guaranteed_model_id())
            return await client.models.get_info(request=request)
    return self.holder.run_coroutine_threadsafe(_get_info_async()).result()
```

**Critical Usage: Tokenizer Resolution** (lines 850-895 in `training_client.py`)

The `get_info` endpoint is **essential** for tokenizer resolution. The `_get_tokenizer()` function:
1. Calls `get_info()` to retrieve `info.model_data.tokenizer_id`
2. Falls back to heuristic logic if `tokenizer_id` is `None`
3. Applies workarounds for gated models (e.g., "baseten/Meta-Llama-3-tokenizer")

```python
info = holder.run_coroutine_threadsafe(_get_info_async()).result()
model_name = info.model_data.model_name
tokenizer_id = info.model_data.tokenizer_id
if tokenizer_id is None:
    if model_name.startswith("meta-llama/Llama-3"):
        tokenizer_id = "baseten/Meta-Llama-3-tokenizer"
    # ... more heuristics
return AutoTokenizer.from_pretrained(tokenizer_id, fast=True, **kwargs)
```

### Elixir Implementation

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\training_client.ex`

#### Current Status: Stub Implementation

**Lines 46-55:** Public API (documented but returns error)
```elixir
@doc """
Fetch model metadata for the training client.

Used by tokenizer resolution to obtain `model_data.tokenizer_id`. Returns an
error until the info endpoint is wired.
"""
@spec get_info(t()) :: {:ok, map()} | {:error, Error.t()}
def get_info(client) do
  GenServer.call(client, :get_info)
end
```

**Lines 436-438:** Handler (hardcoded error)
```elixir
@impl true
def handle_call(:get_info, _from, state) do
  {:reply, {:error, Error.new(:validation, "get_info not implemented")}, state}
end
```

#### Missing Types

**Search Results:**
```bash
$ grep -r "GetInfo\|get_info\|UnloadModel\|unload_model" lib/tinkex/types/
# No results - types do not exist
```

**Confirmed Missing:**
- `lib/tinkex/types/get_info_request.ex` - Does not exist
- `lib/tinkex/types/get_info_response.ex` - Does not exist
- `lib/tinkex/types/unload_model_request.ex` - Does not exist
- `lib/tinkex/types/unload_model_response.ex` - Does not exist

#### Missing API Layer

**File:** `lib/tinkex/api/service.ex` (lines 1-62)

The Service API module only exposes:
- `get_server_capabilities/1` (lines 13-23)
- `health_check/1` (lines 28-34)
- `create_model/2` (lines 39-47)
- `create_sampling_session/2` (lines 52-60)

**Missing:**
- No `get_info/2` function
- No `unload_model/2` function
- No dedicated Models API module

### Elixir Tokenizer Usage

**File:** `lib/tinkex/tokenizer.ex` (lines 22-42)

The Elixir tokenizer **does** attempt to use `get_info`:

```elixir
@doc """
Resolve the tokenizer ID for the given model.

- If a `training_client` is provided, attempts to fetch `model_data.tokenizer_id`
  via the provided `:info_fun` (defaults to `&TrainingClient.get_info/1`).
- Applies the Llama-3 gating workaround.
- Falls back to the provided `model_name`.
"""
def get_tokenizer_id(model_name, training_client, opts) do
  case fetch_tokenizer_id_from_client(training_client, opts) do
    {:ok, tokenizer_id} -> tokenizer_id
    _ -> apply_tokenizer_heuristics(model_name)
  end
end
```

**Impact:** Because `get_info` returns an error, tokenizer resolution **always falls back** to heuristics, preventing server-driven tokenizer configuration.

### Related Type: WeightsInfoResponse

**File:** `lib/tinkex/types/weights_info_response.ex`

Interestingly, Elixir **does** have a similar type for checkpoint metadata:

```elixir
defmodule Tinkex.Types.WeightsInfoResponse do
  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]

  @type t :: %__MODULE__{
          base_model: String.t(),
          is_lora: boolean(),
          lora_rank: non_neg_integer() | nil
        }
end
```

This shows the pattern exists but is only used for checkpoint inspection via REST endpoints, not for active model metadata.

## Decision Drivers

1. **Tokenizer Resolution Dependency:** `get_info` is **critical** for dynamic tokenizer ID resolution in Python. Elixir currently falls back to heuristics 100% of the time.

2. **API Completeness:** The Python SDK provides this endpoint as a first-class feature. Clients expect it.

3. **Resource Management:** `unload_model` is essential for session lifecycle management and GPU memory release.

4. **Type Safety:** Elixir SDK benefits from typed responses rather than raw maps.

5. **Wire Protocol Alignment:** Both endpoints are part of the official Tinker API (`/api/v1/get_info`, `/api/v1/unload_model`).

6. **Documentation Commitment:** The Elixir `TrainingClient.get_info/1` already has a `@doc` comment and typespec, creating an API contract that is currently broken.

## Considered Options

### Option 1: Implement Full Model Info + Unload Support (Recommended)

**Scope:**
- Create typed request/response modules for both endpoints
- Implement API layer functions in a new `Tinkex.API.Models` module
- Wire up `TrainingClient.get_info/1` handler
- Add `TrainingClient.unload_model/1` function
- Update tokenizer resolution to use real endpoint
- Add tests and documentation

**Implementation Steps:**

1. **Create Type Modules** (4 new files):
   - `lib/tinkex/types/get_info_request.ex`
   - `lib/tinkex/types/get_info_response.ex`
   - `lib/tinkex/types/model_data.ex` (nested in response)
   - `lib/tinkex/types/unload_model_request.ex`
   - `lib/tinkex/types/unload_model_response.ex`

2. **Create API Module** (1 new file):
   - `lib/tinkex/api/models.ex` with:
     - `get_info/2` → POST `/api/v1/get_info`
     - `unload_model/2` → POST `/api/v1/unload_model`

3. **Update TrainingClient** (`lib/tinkex/training_client.ex`):
   - Replace stub handler (line 436-438) with API call
   - Add `unload_model/1` public function
   - Add `unload_model/2` handler

4. **Update Tokenizer** (`lib/tinkex/tokenizer.ex`):
   - Verify `fetch_tokenizer_id_from_client/2` correctly extracts `model_data.tokenizer_id`

5. **Add Tests:**
   - `test/tinkex/api/models_test.exs` (new)
   - `test/tinkex/types/model_info_types_test.exs` (new)
   - Update `test/tinkex/training_client_test.exs`
   - Update `test/tinkex/tokenizer_test.exs`

**Effort Estimate:** 4-6 hours (types + API + tests)

**Benefits:**
- ✅ Full parity with Python SDK
- ✅ Enables server-driven tokenizer resolution
- ✅ Provides resource cleanup mechanism
- ✅ Type-safe responses
- ✅ Honors existing API contract

**Drawbacks:**
- More code to maintain
- Requires server to support these endpoints

### Option 2: Implement Get Info Only

**Scope:**
- Implement only `get_info` endpoint and types
- Leave `unload_model` for later

**Rationale:** `get_info` is used by tokenizer resolution (active feature), while `unload_model` may be less critical if sessions auto-expire.

**Effort Estimate:** 2-3 hours

**Benefits:**
- ✅ Unblocks tokenizer resolution
- ✅ Smaller change surface

**Drawbacks:**
- ❌ Incomplete parity
- ❌ No resource cleanup mechanism
- ❌ Still requires API module creation

### Option 3: Remove Stub and Document as Unsupported

**Scope:**
- Remove `get_info/1` from TrainingClient public API
- Update tokenizer to remove dead code path
- Document heuristic-only tokenizer resolution

**Effort Estimate:** 30 minutes

**Benefits:**
- ✅ Honest API surface
- ✅ No broken promises

**Drawbacks:**
- ❌ Regression from Python SDK
- ❌ Forces heuristic tokenizer resolution
- ❌ Harder to add later (API removal)

### Option 4: Mock Implementation for Testing

**Scope:**
- Keep stub but allow test injection
- Add config option for custom info provider

**Effort Estimate:** 1 hour

**Benefits:**
- ✅ Enables testing without server support

**Drawbacks:**
- ❌ Not a real solution
- ❌ Confusing for users
- ❌ Technical debt

## Decision

**Recommendation: Option 1 - Implement Full Model Info + Unload Support**

### Rationale

1. **Critical Dependency:** The tokenizer resolution feature **expects** `get_info` to work. The current implementation is a broken promise with fallback behavior.

2. **API Contract:** The function is already documented and exposed in the public API with a typespec. Removing it (Option 3) would be a breaking change.

3. **Lifecycle Completeness:** Model creation (`create_model`) exists, but there's no corresponding cleanup (`unload_model`). This creates a one-way lifecycle.

4. **Modest Effort:** 4-6 hours for complete implementation is reasonable for the value provided.

5. **Future-Proofing:** As server capabilities expand, having the infrastructure in place makes it easier to add model introspection features.

6. **Alignment with Gap Analysis:** VERIFIED_GAP_LIST.md doesn't list this as a gap, but the implementation clearly shows it should be.

## Consequences

### Positive

1. **Tokenizer Resolution:** Server can return canonical `tokenizer_id`, reducing heuristic failures for new models.

2. **API Parity:** Elixir SDK matches Python SDK capabilities for model management.

3. **Type Safety:** Responses are properly typed rather than raw maps.

4. **Resource Management:** Clients can explicitly unload models to free GPU memory.

5. **Testing:** Mock servers can provide model metadata for integration tests.

6. **Documentation:** Fulfills the promise made in existing `@doc` comments.

### Negative

1. **Server Dependency:** Requires server to implement `/api/v1/get_info` and `/api/v1/unload_model` endpoints. If these return 404, clients will get errors instead of graceful degradation.

2. **Maintenance:** Additional code to maintain and test.

3. **Migration Risk:** Existing code using heuristic tokenizers will need to handle server-provided IDs.

### Neutral

1. **Backward Compatibility:** Current error-returning behavior means any existing code already handles failure. Successful responses are strictly better.

2. **Testing Burden:** Need to mock these endpoints in test suites.

## Implementation Plan

### Phase 1: Type Definitions (1-2 hours)

**Files to Create:**

1. `lib/tinkex/types/get_info_request.ex`
```elixir
defmodule Tinkex.Types.GetInfoRequest do
  @moduledoc """
  Request to retrieve model metadata.

  ## Fields
  - `model_id` - The model ID to query
  - `type` - Request type discriminator ("get_info")
  """

  @enforce_keys [:model_id]
  defstruct [:model_id, type: "get_info"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t()
        }

  @spec new(String.t()) :: t()
  def new(model_id) when is_binary(model_id) do
    %__MODULE__{model_id: model_id}
  end
end
```

2. `lib/tinkex/types/model_data.ex`
```elixir
defmodule Tinkex.Types.ModelData do
  @moduledoc """
  Model architecture and configuration metadata.

  ## Fields
  - `arch` - Model architecture (e.g., "llama", "qwen")
  - `model_name` - Full model name (e.g., "Qwen/Qwen2.5-7B")
  - `tokenizer_id` - HuggingFace tokenizer ID for loading
  """

  defstruct [:arch, :model_name, :tokenizer_id]

  @type t :: %__MODULE__{
          arch: String.t() | nil,
          model_name: String.t() | nil,
          tokenizer_id: String.t() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      arch: json["arch"] || json[:arch],
      model_name: json["model_name"] || json[:model_name],
      tokenizer_id: json["tokenizer_id"] || json[:tokenizer_id]
    }
  end
end
```

3. `lib/tinkex/types/get_info_response.ex`
```elixir
defmodule Tinkex.Types.GetInfoResponse do
  @moduledoc """
  Response containing model metadata.

  ## Fields
  - `model_id` - The queried model ID
  - `model_data` - Architecture and tokenizer information
  - `is_lora` - Whether this is a LoRA adapter
  - `lora_rank` - LoRA rank if applicable
  - `model_name` - Convenience alias for model_data.model_name
  - `type` - Response type discriminator
  """

  alias Tinkex.Types.ModelData

  @enforce_keys [:model_id, :model_data]
  defstruct [:model_id, :model_data, :is_lora, :lora_rank, :model_name, :type]

  @type t :: %__MODULE__{
          model_id: String.t(),
          model_data: ModelData.t(),
          is_lora: boolean() | nil,
          lora_rank: non_neg_integer() | nil,
          model_name: String.t() | nil,
          type: String.t() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    model_data_json = json["model_data"] || json[:model_data] || %{}

    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      model_data: ModelData.from_json(model_data_json),
      is_lora: json["is_lora"] || json[:is_lora],
      lora_rank: json["lora_rank"] || json[:lora_rank],
      model_name: json["model_name"] || json[:model_name],
      type: json["type"] || json[:type]
    }
  end
end
```

4. `lib/tinkex/types/unload_model_request.ex`
```elixir
defmodule Tinkex.Types.UnloadModelRequest do
  @moduledoc """
  Request to unload model weights and end session.

  ## Fields
  - `model_id` - The model ID to unload
  - `type` - Request type discriminator ("unload_model")
  """

  @enforce_keys [:model_id]
  defstruct [:model_id, type: "unload_model"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t()
        }

  @spec new(String.t()) :: t()
  def new(model_id) when is_binary(model_id) do
    %__MODULE__{model_id: model_id}
  end
end
```

5. `lib/tinkex/types/unload_model_response.ex`
```elixir
defmodule Tinkex.Types.UnloadModelResponse do
  @moduledoc """
  Response confirming model unload.

  ## Fields
  - `model_id` - The unloaded model ID
  - `type` - Response type discriminator
  """

  @enforce_keys [:model_id]
  defstruct [:model_id, :type]

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t() | nil
        }

  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      type: json["type"] || json[:type]
    }
  end
end
```

### Phase 2: API Module (1 hour)

**File to Create:** `lib/tinkex/api/models.ex`

```elixir
defmodule Tinkex.API.Models do
  @moduledoc """
  Model metadata and lifecycle endpoints.

  Uses :training pool for model operations.
  """

  alias Tinkex.Types.{GetInfoResponse, UnloadModelResponse}

  @doc """
  Retrieve metadata for a model.

  ## Examples

      Tinkex.API.Models.get_info(
        %{model_id: "model-123"},
        config: config
      )
  """
  @spec get_info(map(), keyword()) ::
          {:ok, GetInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_info(request, opts) do
    case Tinkex.API.post(
           "/api/v1/get_info",
           request,
           Keyword.put(opts, :pool_type, :training)
         ) do
      {:ok, json} -> {:ok, GetInfoResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Unload model weights and end the user's session.

  ## Examples

      Tinkex.API.Models.unload_model(
        %{model_id: "model-123"},
        config: config
      )
  """
  @spec unload_model(map(), keyword()) ::
          {:ok, UnloadModelResponse.t()} | {:error, Tinkex.Error.t()}
  def unload_model(request, opts) do
    case Tinkex.API.post(
           "/api/v1/unload_model",
           request,
           Keyword.put(opts, :pool_type, :training)
         ) do
      {:ok, json} -> {:ok, UnloadModelResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end
end
```

### Phase 3: TrainingClient Integration (1 hour)

**File to Update:** `lib/tinkex/training_client.ex`

**Changes:**

1. **Add to alias block** (line 22-34):
```elixir
alias Tinkex.Types.{
  # ... existing types ...
  GetInfoRequest,
  GetInfoResponse,
  UnloadModelRequest,
  UnloadModelResponse
}
```

2. **Replace handler** (lines 436-438):
```elixir
@impl true
def handle_call(:get_info, _from, state) do
  case Tinkex.API.Models.get_info(
         %GetInfoRequest{model_id: state.model_id},
         config: state.config,
         telemetry_metadata: base_telemetry_metadata(state, %{model_id: state.model_id})
       ) do
    {:ok, response} ->
      {:reply, {:ok, response}, state}

    {:error, %Error{} = error} ->
      {:reply, {:error, error}, state}
  end
end
```

3. **Add unload_model function** (after `get_info`):
```elixir
@doc """
Unload model weights and end the session.

Releases GPU memory and terminates the model server process.
"""
@spec unload_model(t()) :: {:ok, UnloadModelResponse.t()} | {:error, Error.t()}
def unload_model(client) do
  GenServer.call(client, :unload_model)
end

@impl true
def handle_call(:unload_model, _from, state) do
  case Tinkex.API.Models.unload_model(
         %UnloadModelRequest{model_id: state.model_id},
         config: state.config,
         telemetry_metadata: base_telemetry_metadata(state, %{model_id: state.model_id})
       ) do
    {:ok, response} ->
      {:reply, {:ok, response}, state}

    {:error, %Error{} = error} ->
      {:reply, {:error, error}, state}
  end
end
```

### Phase 4: Testing (2 hours)

**Files to Create/Update:**

1. `test/tinkex/types/model_info_types_test.exs`
2. `test/tinkex/api/models_test.exs`
3. Update `test/tinkex/training_client_test.exs`
4. Update `test/tinkex/tokenizer_test.exs`

### Phase 5: Documentation (30 minutes)

1. Add examples to module docs
2. Update CHANGELOG.md
3. Update gap analysis documents

## References

### Python SDK Files
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\resources\models.py` (lines 68-158)
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\types\get_info_request.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\types\get_info_response.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\types\unload_model_request.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\types\unload_model_response.py`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\training_client.py` (lines 689-723, 850-895)

### Elixir SDK Files
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\training_client.ex` (lines 46-55, 436-438)
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\api\service.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\tokenizer.ex` (lines 22-42)
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\types\weights_info_response.ex` (reference pattern)

### Documentation
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\docs\20251126\gaps\VERIFIED_GAP_LIST.md`

## Notes

### Server Endpoint Validation

Before implementation, verify server support:
```bash
curl -X POST https://tinker.server/api/v1/get_info \
  -H "Content-Type: application/json" \
  -d '{"model_id": "test-id", "type": "get_info"}'
```

If server returns 404, coordinate with backend team to implement endpoints first.

### Tokenizer Fallback Strategy

Even with `get_info` implemented, maintain heuristic fallback in `Tinkex.Tokenizer` for:
1. Server errors (network, 5xx)
2. Missing `tokenizer_id` field in response
3. Testing with mock servers

### Future Enhancements

1. **Caching:** Cache `GetInfoResponse` per model_id to reduce API calls
2. **Refresh:** Add `force_refresh` option to bypass cache
3. **Batch Query:** Add `get_info_batch/1` for multiple models
4. **Session Lifecycle:** Automatically call `unload_model` on TrainingClient termination
