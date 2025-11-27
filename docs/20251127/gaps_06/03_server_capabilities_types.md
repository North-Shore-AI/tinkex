# Gap #3: Server Capabilities - Reduced Type Information

**Date:** November 27, 2025
**Severity:** Medium-High
**Status:** Confirmed
**Category:** Type Fidelity & Data Modeling

---

## Executive Summary

Both SDKs currently drop most of the server-provided model metadata. The Python `SupportedModel` only declares `model_name` and inherits a Pydantic `model_config` of `extra="ignore"`, so `model_id` and `arch` are removed during response serialization. The Elixir SDK then further flattens the response down to a list of strings, losing even the minimal struct shape. As a result, clients in either language cannot:

- Validate model identifiers before requests
- Display model architectures in UIs
- Make architecture-specific optimizations
- Maintain parity when the server adds metadata

**Impact Level:** Medium-High - Data loss in type system, limiting downstream usage.

---

## 1. Python Deep Dive

### 1.1 Type Definitions

**File:** `tinker/src/tinker/types/get_server_capabilities_response.py`

```python
from typing import List, Optional
from .._models import BaseModel

__all__ = ["GetServerCapabilitiesResponse", "SupportedModel"]


class SupportedModel(BaseModel):
    model_name: Optional[str] = None


class GetServerCapabilitiesResponse(BaseModel):
    supported_models: List[SupportedModel]
```

**Current State Analysis:**
- `SupportedModel` currently has only ONE field: `model_name`
- `BaseModel` sets `model_config = ConfigDict(frozen=True, extra="ignore")`, so untyped keys like `model_id` and `arch` are dropped at construction/serialization time
- FastAPI uses this type as the `response_model`, so the HTTP response itself omits `model_id` and `arch`
- As written there is no forward compatibility—extra metadata is discarded, not preserved

### 1.2 API Response Format

**File:** `tinker/tests/mock_api_server.py` (lines 92-117)

```python
SUPPORTED_MODELS = [
    {"model_id": "llama-3-8b", "model_name": "meta-llama/Meta-Llama-3-8B", "arch": "llama"},
    {"model_id": "llama-3-70b", "model_name": "meta-llama/Meta-Llama-3-70B", "arch": "llama"},
    {"model_id": "qwen2-72b", "model_name": "Qwen/Qwen2-72B", "arch": "qwen2"},
]

@app.get("/get_server_capabilities", response_model=types.GetServerCapabilitiesResponse)
async def get_server_capabilities():
    """Get server capabilities including supported models."""
    supported_models = [
        {"model_id": model["model_id"], "model_name": model["model_name"], "arch": model["arch"]}
        for model in SUPPORTED_MODELS
    ]
    return types.GetServerCapabilitiesResponse(supported_models=supported_models)
```

**What the handler builds (before Pydantic validation):**
```json
{
  "supported_models": [
    {
      "model_id": "llama-3-8b",
      "model_name": "meta-llama/Meta-Llama-3-8B",
      "arch": "llama"
    },
    {
      "model_id": "llama-3-70b",
      "model_name": "meta-llama/Meta-Llama-3-70B",
      "arch": "llama"
    },
    {
      "model_id": "qwen2-72b",
      "model_name": "Qwen/Qwen2-72B",
      "arch": "qwen2"
    }
  ]
}
```

**What FastAPI actually returns (because `SupportedModel` drops extras):**
```json
{
  "supported_models": [
    { "model_name": "meta-llama/Meta-Llama-3-8B" },
    { "model_name": "meta-llama/Meta-Llama-3-70B" },
    { "model_name": "Qwen/Qwen2-72B" }
  ]
}
```

**Fields present in `SUPPORTED_MODELS` before serialization (currently dropped):**
1. `model_id` (string) - Short identifier (e.g., "llama-3-8b")
2. `model_name` (string) - Full HuggingFace model path (e.g., "meta-llama/Meta-Llama-3-8B")
3. `arch` (string) - Architecture type (e.g., "llama", "qwen2")

### 1.3 Python SDK Usage Pattern

**File:** `tinker/src/tinker/resources/service.py` (lines 22-42)

```python
class AsyncServiceResource(AsyncAPIResource):
    async def get_server_capabilities(
        self,
        *,
        extra_headers: Headers | None = None,
        extra_query: Query | None = None,
        extra_body: Body | None = None,
        timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    ) -> GetServerCapabilitiesResponse:
        """Retrieves information about supported models and server capabilities"""
        return await self._get(
            "/api/v1/get_server_capabilities",
            options=make_request_options(...),
            cast_to=GetServerCapabilitiesResponse,
        )
```

**How It Works:**
1. Makes GET request to `/api/v1/get_server_capabilities`
2. FastAPI serializes the response via `GetServerCapabilitiesResponse`, stripping `model_id`/`arch` because they are not typed
3. The client-side Pydantic deserializes each element as `SupportedModel` (only `model_name` survives)
4. Returns strongly-typed `GetServerCapabilitiesResponse`, but the rich metadata is already gone

**Pydantic BaseModel Behavior:**
- Configuration: `model_config = ConfigDict(frozen=True, extra="ignore")`
- **Drops** extra fields (`model_id`, `arch`, future keys) instead of keeping them
- Because FastAPI uses this as the `response_model`, those dropped fields never reach the HTTP response
- No forward compatibility: additional metadata is removed at validation time

### 1.4 Comparison with GetInfoResponse

The Python SDK has a similar pattern in `GetInfoResponse` which shows how structured model metadata should be handled:

**File:** `tinker/src/tinker/types/get_info_response.py`

```python
class GetInfoResponse(BaseModel):
    type: Optional[Literal["get_info"]] = None
    model_data: ModelData
    model_id: ModelID
    is_lora: Optional[bool] = None
    lora_rank: Optional[int] = None
    model_name: Optional[str] = None
```

The API returns structured `model_data` objects with fields like:
- `model_name` (string, optional)
- `arch` (string, optional)
- `tokenizer_id` (string, optional)

---

## 2. Elixir Deep Dive

### 2.1 Current Type Definition

**File:** `lib/tinkex/types/get_server_capabilities_response.ex`

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @moduledoc """
  Supported model metadata returned by the service capabilities endpoint.
  """

  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @type t :: %__MODULE__{
          supported_models: [String.t()]
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    models = map["supported_models"] || map[:supported_models] || []

    names =
      models
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

**Problems Identified:**

1. **Type Degradation:** `supported_models: [String.t()]` - reduces structured data to strings
2. **Data Loss:** Extracts only `model_name`, discards `model_id` and `arch`
3. **Pattern Matching Logic:** Lines 22-27 show the parser can handle:
   - Maps with `"model_name"` key (string)
   - Maps with `:model_name` key (atom)
   - Raw strings (fallback)
   - But **throws away** the map after extraction!

4. **Inconsistent with SDK Patterns:** Compare with `GetInfoResponse.ex` which properly preserves structured data:

**File:** `lib/tinkex/types/get_info_response.ex` (lines 6-9)

```elixir
alias Tinkex.Types.ModelData

@enforce_keys [:model_id, :model_data]
defstruct [:model_id, :model_data, :is_lora, :lora_rank, :model_name, :type]

@type t :: %__MODULE__{
        model_id: String.t(),
        model_data: ModelData.t(),  # ← Structured type!
        is_lora: boolean() | nil,
        lora_rank: non_neg_integer() | nil,
        model_name: String.t() | nil,
        type: String.t() | nil
      }
```

**File:** `lib/tinkex/types/model_data.ex`

```elixir
defmodule Tinkex.Types.ModelData do
  @moduledoc """
  Model metadata including architecture, display name, and tokenizer id.
  """

  defstruct [:arch, :model_name, :tokenizer_id]

  @type t :: %__MODULE__{
          arch: String.t() | nil,
          model_name: String.t() | nil,
          tokenizer_id: String.t() | nil
        }

  @doc """
  Parse model metadata from a JSON map (string or atom keys).
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    %__MODULE__{
      arch: json["arch"] || json[:arch],
      model_name: json["model_name"] || json[:model_name],
      tokenizer_id: json["tokenizer_id"] || json[:tokenizer_id]
    }
  end
end
```

**The Pattern Exists!** The SDK already has `ModelData` type that handles exactly the fields we need.

### 2.2 Current Usage in Tests

**File:** `test/tinkex/api/service_test.exs` (lines 9-23)

```elixir
test "get_server_capabilities returns supported models", %{bypass: bypass, config: config} do
  Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(
      200,
      ~s({"supported_models":[{"model_name":"llama"},{"model_name":"qwen"}]})
    )
  end)

  assert {:ok, %GetServerCapabilitiesResponse{} = resp} =
           Service.get_server_capabilities(config: config)

  assert resp.supported_models == ["llama", "qwen"]
end
```

**Test Only Validates String Extraction:**
- Mock response includes structured objects with `model_name` keys
- Test only asserts the extracted strings match
- No test for `model_id`, `arch`, or other fields
- Test **reinforces** the current limited behavior

### 2.3 Example Usage

**File:** `examples/live_capabilities_and_logprobs.exs` (lines 23-35)

```elixir
case Service.get_server_capabilities(config: config) do
  {:ok, resp} ->
    models =
      case resp.supported_models do
        [] -> "[none reported]"
        models -> Enum.join(models, ", ")
      end

    IO.puts("Supported models: #{models}")

  {:error, %Error{} = error} ->
    IO.puts("Capabilities error: #{Error.format(error)}")
end
```

**Current Usage Pattern:**
- Only uses model names for display
- Joins them as comma-separated string
- No access to model IDs or architectures
- Cannot validate model identifiers before use

---

## 3. Granular Differences

### 3.1 Field-by-Field Comparison

| Field | Python SDK | Elixir SDK | Impact |
|-------|-----------|-----------|--------|
| **Container Type** | `List[SupportedModel]` (only `model_name` survives; extras ignored) | `[String.t()]` | Python keeps a wrapper struct; Elixir flattens to primitives |
| **model_name** | `Optional[str]` in SupportedModel | `String.t()` (extracted) | Data survives in both; Python exposes as struct field |
| **model_id** | **Dropped** by Pydantic (`extra="ignore"`) and response serialization | **Dropped** by parser | Neither SDK can map short IDs to models |
| **arch** | **Dropped** by Pydantic (`extra="ignore"`) and response serialization | **Dropped** by parser | No architecture-aware logic in either SDK |
| **Future fields** | Dropped by Pydantic/response_model | Dropped by parser | No forward compatibility in either SDK |

### 3.2 Type Fidelity

**Python:**
```python
response: GetServerCapabilitiesResponse
model: SupportedModel = response.supported_models[0]
# Only field available:
model.model_name  # Type: Optional[str]
model.model_dump()
# {"model_name": "meta-llama/Meta-Llama-3-8B"}  # model_id/arch already removed
```

**Elixir (Current):**
```elixir
{:ok, response} = Service.get_server_capabilities(config: config)
model = List.first(response.supported_models)
# model is just a string!
# Cannot access model_id, arch, or any other metadata
```

**Elixir (Should Be):**
```elixir
{:ok, response} = Service.get_server_capabilities(config: config)
model = List.first(response.supported_models)
# model should be %SupportedModel{}
model.model_name  # "meta-llama/Meta-Llama-3-8B"
model.model_id    # "llama-3-8b"
model.arch        # "llama"
```

### 3.3 Downstream Impact

**Use Cases Broken by Type Degradation (affects Python and Elixir today):**

1. **Model Validation:**
   ```elixir
   # Cannot validate: is "llama-3-8b" a valid model_id?
   # Because we only have model_names like "meta-llama/Meta-Llama-3-8B"
   ```

2. **Architecture-Specific Logic:**
   ```elixir
   # Cannot do: if model.arch == "llama", use llama-specific tokenizer
   # Because arch field is lost
   ```

3. **UI Display:**
   ```elixir
   # Cannot show: "Llama 3 8B (llama-3-8b) - Architecture: llama"
   # Only have: "meta-llama/Meta-Llama-3-8B"
   ```

4. **Model Selection:**
   ```elixir
   # Cannot filter: "Show me all Qwen models"
   # Would need to parse model names as strings
   ```

5. **API Compatibility:**
   ```elixir
   # If server adds new fields (e.g., "supports_vision": true)
   # Elixir client cannot access them
   # Python client gets them automatically via Pydantic
   ```

---

## 4. Root Cause Analysis

### 4.1 Why This Happened

1. **Over-narrow Python type:** `SupportedModel` only typed `model_name` and inherits `extra="ignore"`, so metadata is removed before serialization
2. **Missing Pattern Application:** `ModelData` struct exists but wasn't reused on either SDK for capabilities
3. **Test Coverage Gap:** Tests only validated string/name extraction and never asserted `model_id`/`arch`
4. **Documentation Gap:** Actual HTTP response shape (only `model_name`) was not captured in docs

### 4.2 Why This Matters

Both SDKs (and the FastAPI mock) currently strip the same metadata:
- **model_id/arch never reach clients** because the response_model drops them
- **No forward compatibility:** new fields are removed by validation
- **Limited debugging:** `.model_dump()` only shows `model_name`
- **Elixir adds one more loss:** it flattens the struct to strings, so even the minimal shape is gone

---

## 5. TDD Implementation Plan

### 5.1 Python & mock server: surface metadata

- Add `model_id` and `arch` fields to `tinker/src/tinker/types/get_server_capabilities_response.py::SupportedModel` (and consider `extra="allow"` if we want future fields)
- With the typed fields in place, FastAPI `response_model` serialization will include them; add a regression test around `get_server_capabilities` to assert `model_dump()` contains `model_id`/`arch`
- Update the mock server fixture expectations accordingly to reflect the serialized output
- Mirror the checks in the Python client tests to ensure the SDK actually exposes the metadata

### 5.2 Elixir: New Type Definitions

**Step 1: Create `SupportedModel` struct**

**File:** `lib/tinkex/types/supported_model.ex`

```elixir
defmodule Tinkex.Types.SupportedModel do
  @moduledoc """
  Metadata for a single supported model from the server capabilities response.

  ## Fields

  - `model_id` - Short identifier (e.g., "llama-3-8b")
  - `model_name` - Full model path (e.g., "meta-llama/Meta-Llama-3-8B")
  - `arch` - Architecture type (e.g., "llama", "qwen2")

  ## Example

      iex> json = %{
      ...>   "model_id" => "llama-3-8b",
      ...>   "model_name" => "meta-llama/Meta-Llama-3-8B",
      ...>   "arch" => "llama"
      ...> }
      iex> model = SupportedModel.from_json(json)
      iex> model.model_id
      "llama-3-8b"
      iex> model.arch
      "llama"
  """

  @enforce_keys [:model_name]
  defstruct [:model_id, :model_name, :arch]

  @type t :: %__MODULE__{
          model_id: String.t() | nil,
          model_name: String.t(),
          arch: String.t() | nil
        }

  @doc """
  Parse a supported model from JSON map with string or atom keys.

  Falls back gracefully if given a plain string (treats as model_name).
  """
  @spec from_json(map() | String.t()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      model_name: json["model_name"] || json[:model_name] || "",
      arch: json["arch"] || json[:arch]
    }
  end

  def from_json(name) when is_binary(name) do
    # Backward compatibility: plain string becomes model_name
    %__MODULE__{model_name: name}
  end
end
```

**Step 2: Update `GetServerCapabilitiesResponse`**

**File:** `lib/tinkex/types/get_server_capabilities_response.ex`

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @moduledoc """
  Supported model metadata returned by the service capabilities endpoint.

  Contains a list of `SupportedModel` structs with full metadata including
  model IDs, names, and architecture types.

  ## Migration Note

  Prior to version X.Y.Z, this type stored only model names as strings.
  The new structure provides richer metadata while maintaining backward
  compatibility for parsing responses.
  """

  alias Tinkex.Types.SupportedModel

  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @type t :: %__MODULE__{
          supported_models: [SupportedModel.t()]
        }

  @doc """
  Parse from JSON map with string or atom keys.

  Handles various input formats for backward compatibility:
  - Array of model objects with metadata fields
  - Array of plain strings (legacy format)
  - Mixed arrays
  """
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    models = map["supported_models"] || map[:supported_models] || []

    parsed_models =
      models
      |> Enum.map(&SupportedModel.from_json/1)
      |> Enum.reject(&is_nil(&1.model_name))

    %__MODULE__{supported_models: parsed_models}
  end
end
```

### 5.3 Test Plan

- **Python:** unit test that `SupportedModel.model_dump()` includes `model_id`/`arch` and an integration test asserting the FastAPI endpoint returns those fields.
- **Elixir:** cases below cover the new struct and response parser.

#### 5.3.1 Unit Tests for `SupportedModel`

**File:** `test/tinkex/types/supported_model_test.exs`

```elixir
defmodule Tinkex.Types.SupportedModelTest do
  use ExUnit.Case, async: true
  alias Tinkex.Types.SupportedModel

  describe "from_json/1" do
    test "parses full model metadata with string keys" do
      json = %{
        "model_id" => "llama-3-8b",
        "model_name" => "meta-llama/Meta-Llama-3-8B",
        "arch" => "llama"
      }

      model = SupportedModel.from_json(json)

      assert model.model_id == "llama-3-8b"
      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.arch == "llama"
    end

    test "parses full model metadata with atom keys" do
      json = %{
        model_id: "qwen2-72b",
        model_name: "Qwen/Qwen2-72B",
        arch: "qwen2"
      }

      model = SupportedModel.from_json(json)

      assert model.model_id == "qwen2-72b"
      assert model.model_name == "Qwen/Qwen2-72B"
      assert model.arch == "qwen2"
    end

    test "handles missing optional fields" do
      json = %{"model_name" => "some-model"}

      model = SupportedModel.from_json(json)

      assert model.model_id == nil
      assert model.model_name == "some-model"
      assert model.arch == nil
    end

    test "backward compatibility: plain string becomes model_name" do
      model = SupportedModel.from_json("meta-llama/Meta-Llama-3-8B")

      assert model.model_id == nil
      assert model.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model.arch == nil
    end

    test "handles empty model_name gracefully" do
      json = %{"model_id" => "test", "arch" => "llama"}

      model = SupportedModel.from_json(json)

      assert model.model_id == "test"
      assert model.model_name == ""
      assert model.arch == "llama"
    end
  end
end
```

#### 5.3.2 Unit Tests for `GetServerCapabilitiesResponse`

**File:** `test/tinkex/types/get_server_capabilities_response_test.exs`

```elixir
defmodule Tinkex.Types.GetServerCapabilitiesResponseTest do
  use ExUnit.Case, async: true
  alias Tinkex.Types.{GetServerCapabilitiesResponse, SupportedModel}

  describe "from_json/1" do
    test "parses array of model objects with full metadata" do
      json = %{
        "supported_models" => [
          %{
            "model_id" => "llama-3-8b",
            "model_name" => "meta-llama/Meta-Llama-3-8B",
            "arch" => "llama"
          },
          %{
            "model_id" => "qwen2-72b",
            "model_name" => "Qwen/Qwen2-72B",
            "arch" => "qwen2"
          }
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2

      [model1, model2] = response.supported_models
      assert %SupportedModel{} = model1
      assert model1.model_id == "llama-3-8b"
      assert model1.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model1.arch == "llama"

      assert model2.model_id == "qwen2-72b"
      assert model2.model_name == "Qwen/Qwen2-72B"
      assert model2.arch == "qwen2"
    end

    test "parses with atom keys" do
      json = %{
        supported_models: [
          %{model_id: "test-1", model_name: "Test Model 1", arch: "test"}
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 1
      [model] = response.supported_models
      assert model.model_id == "test-1"
    end

    test "backward compatibility: handles array of plain strings" do
      json = %{
        "supported_models" => [
          "meta-llama/Meta-Llama-3-8B",
          "Qwen/Qwen2-72B"
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      [model1, model2] = response.supported_models

      assert model1.model_name == "meta-llama/Meta-Llama-3-8B"
      assert model1.model_id == nil
      assert model1.arch == nil

      assert model2.model_name == "Qwen/Qwen2-72B"
    end

    test "backward compatibility: handles mixed array" do
      json = %{
        "supported_models" => [
          %{"model_id" => "llama-3-8b", "model_name" => "meta-llama/Meta-Llama-3-8B", "arch" => "llama"},
          "Qwen/Qwen2-72B"  # Plain string
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 2
      [model1, model2] = response.supported_models

      assert model1.model_id == "llama-3-8b"
      assert model2.model_id == nil
      assert model2.model_name == "Qwen/Qwen2-72B"
    end

    test "filters out entries with no model_name" do
      json = %{
        "supported_models" => [
          %{"model_id" => "valid", "model_name" => "Valid Model"},
          %{"model_id" => "invalid"},  # No model_name
          nil,  # Invalid entry
          ""    # Empty string
        ]
      }

      response = GetServerCapabilitiesResponse.from_json(json)

      assert length(response.supported_models) == 1
      assert hd(response.supported_models).model_name == "Valid Model"
    end

    test "handles empty supported_models array" do
      json = %{"supported_models" => []}

      response = GetServerCapabilitiesResponse.from_json(json)

      assert response.supported_models == []
    end

    test "handles missing supported_models key" do
      json = %{}

      response = GetServerCapabilitiesResponse.from_json(json)

      assert response.supported_models == []
    end
  end
end
```

#### 5.3.3 Integration Tests

**File:** `test/tinkex/api/service_test.exs` (update existing test)

```elixir
test "get_server_capabilities returns supported models with metadata", %{bypass: bypass, config: config} do
  Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(
      200,
      ~s({
        "supported_models": [
          {
            "model_id": "llama-3-8b",
            "model_name": "meta-llama/Meta-Llama-3-8B",
            "arch": "llama"
          },
          {
            "model_id": "qwen2-72b",
            "model_name": "Qwen/Qwen2-72B",
            "arch": "qwen2"
          }
        ]
      })
    )
  end)

  assert {:ok, %GetServerCapabilitiesResponse{} = resp} =
           Service.get_server_capabilities(config: config)

  assert length(resp.supported_models) == 2

  [llama, qwen] = resp.supported_models

  # Verify structured metadata is preserved
  assert llama.model_id == "llama-3-8b"
  assert llama.model_name == "meta-llama/Meta-Llama-3-8B"
  assert llama.arch == "llama"

  assert qwen.model_id == "qwen2-72b"
  assert qwen.model_name == "Qwen/Qwen2-72B"
  assert qwen.arch == "qwen2"
end

test "get_server_capabilities handles backward compatible string format", %{bypass: bypass, config: config} do
  # Legacy format: just model names as strings
  Bypass.expect_once(bypass, "GET", "/api/v1/get_server_capabilities", fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(
      200,
      ~s({"supported_models": ["meta-llama/Meta-Llama-3-8B", "Qwen/Qwen2-72B"]})
    )
  end)

  assert {:ok, %GetServerCapabilitiesResponse{} = resp} =
           Service.get_server_capabilities(config: config)

  assert length(resp.supported_models) == 2
  assert Enum.all?(resp.supported_models, &(&1.model_name != nil))
end
```

#### 5.3.4 Property-Based Tests

**File:** `test/tinkex/types/supported_model_property_test.exs`

```elixir
defmodule Tinkex.Types.SupportedModelPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tinkex.Types.SupportedModel

  property "from_json always returns SupportedModel struct" do
    check all(
            model_id <- one_of([string(:alphanumeric), constant(nil)]),
            model_name <- string(:alphanumeric, min_length: 1),
            arch <- one_of([string(:alphanumeric), constant(nil)])
          ) do
      json = %{
        "model_id" => model_id,
        "model_name" => model_name,
        "arch" => arch
      }

      model = SupportedModel.from_json(json)

      assert %SupportedModel{} = model
      assert model.model_id == model_id
      assert model.model_name == model_name
      assert model.arch == arch
    end
  end

  property "parsing plain string always creates valid SupportedModel" do
    check all(name <- string(:alphanumeric, min_length: 1)) do
      model = SupportedModel.from_json(name)

      assert %SupportedModel{} = model
      assert model.model_name == name
      assert model.model_id == nil
      assert model.arch == nil
    end
  end

  property "round-trip preserves structure" do
    check all(
            model_id <- string(:alphanumeric),
            model_name <- string(:alphanumeric, min_length: 1),
            arch <- string(:alphanumeric)
          ) do
      original = %{
        "model_id" => model_id,
        "model_name" => model_name,
        "arch" => arch
      }

      model = SupportedModel.from_json(original)

      # Reconstruct
      reconstructed = %{
        "model_id" => model.model_id,
        "model_name" => model.model_name,
        "arch" => model.arch
      }

      assert reconstructed == original
    end
  end
end
```

### 5.4 Backward Compatibility Strategy

Python side is additive (new typed fields, still accepts older payloads because Pydantic ignores missing fields). Elixir migration steps remain:

**Migration Path:**

1. **Phase 1: Add new types (non-breaking)**
   - Add `SupportedModel` module
   - Update `GetServerCapabilitiesResponse` type signature
   - Update parser to handle both formats
   - All existing code continues to work

2. **Phase 2: Update examples and documentation**
   - Update `examples/live_capabilities_and_logprobs.exs` to show new fields
   - Add cookbook entries for architecture-specific logic
   - Document migration in CHANGELOG

3. **Phase 3: Deprecation notice (if needed)**
   - If old string-list API is exposed, add deprecation warnings
   - Provide clear upgrade path in documentation

**Compatibility Guarantees:**

```elixir
# Old code that expects strings will fail at compile time:
# supported_models: [String.t()] → supported_models: [SupportedModel.t()]

# But migration is trivial:
# OLD:
Enum.each(resp.supported_models, fn name ->
  IO.puts("Model: #{name}")
end)

# NEW:
Enum.each(resp.supported_models, fn model ->
  IO.puts("Model: #{model.model_name}")
  IO.puts("  ID: #{model.model_id}")
  IO.puts("  Architecture: #{model.arch}")
end)
```

### 5.5 Test Coverage Checklist

- [ ] Python `SupportedModel` retains `model_id`/`arch` in `model_dump()`
- [ ] FastAPI mock endpoint serializes `model_id`/`arch` in HTTP response
- [ ] `SupportedModel.from_json/1` with full metadata
- [ ] `SupportedModel.from_json/1` with missing optional fields
- [ ] `SupportedModel.from_json/1` with plain string (backward compat)
- [ ] `SupportedModel.from_json/1` with atom keys
- [ ] `GetServerCapabilitiesResponse.from_json/1` with object array
- [ ] `GetServerCapabilitiesResponse.from_json/1` with string array
- [ ] `GetServerCapabilitiesResponse.from_json/1` with mixed array
- [ ] `GetServerCapabilitiesResponse.from_json/1` with empty array
- [ ] `GetServerCapabilitiesResponse.from_json/1` with missing key
- [ ] Integration test with full API response
- [ ] Integration test with backward compatible response
- [ ] Property-based tests for type safety
- [ ] Property-based tests for round-trip serialization
- [ ] Dialyzer type checking passes
- [ ] ExDoc documentation generates correctly

---

## 6. Success Criteria

### 6.1 Type Fidelity

- [ ] `supported_models` field typed as `[SupportedModel.t()]`
- [ ] All three fields available: `model_id`, `model_name`, `arch`
- [ ] Dialyzer validates all type signatures
- [ ] No compiler warnings

### 6.2 Backward Compatibility

- [ ] Parser handles old string-array format
- [ ] Parser handles new object-array format
- [ ] Parser handles mixed arrays
- [ ] No breaking changes to public API surface

### 6.3 Test Coverage

- [ ] 100% line coverage for new modules
- [ ] All edge cases tested (empty, nil, mixed types)
- [ ] Property-based tests verify invariants
- [ ] Integration tests with mock API server

### 6.4 Documentation

- [ ] Module docs explain purpose and usage
- [ ] Function specs match implementation
- [ ] Doctests provide examples
- [ ] CHANGELOG entry documents changes
- [ ] Migration guide for users

### 6.5 Python Parity

- [ ] Python `SupportedModel` exposes `model_id`, `model_name`, and `arch` (and retains future fields)
- [ ] FastAPI/mock server serialization returns those fields (validated by tests)
- [ ] Elixir `SupportedModel` matches the Python surface
- [ ] Forward compatibility in both SDKs (no silent field drops)

---

## 7. Implementation Effort Estimate

| Task | Effort | Risk |
|------|--------|------|
| Python: add `model_id`/`arch` fields + tests | 1.5 hours | Low |
| Update mock server serialization/fixtures | 0.5 hour | Low |
| Create Elixir `SupportedModel` module | 1 hour | Low |
| Update Elixir `GetServerCapabilitiesResponse` | 30 min | Low |
| Write unit tests | 2 hours | Low |
| Write property tests | 1 hour | Low |
| Update integration tests | 1 hour | Low |
| Update examples | 30 min | Low |
| Documentation | 1 hour | Low |
| Code review & iteration | 1 hour | Low |
| **Total** | **10 hours** | **Low** |

**Why Low Risk:**
- Pattern already exists in `ModelData` type
- Pydantic changes are additive (typing existing fields) and keep backward compatibility
- Backward compatibility via polymorphic parsing on Elixir side
- Test-first approach catches issues early
- No changes to wire protocol or API calls

---

## 8. Related Gaps

### 8.1 Connected Issues

- **Gap #4:** Missing `get_server_capabilities` on ServiceClient - This gap fixes the type, Gap #4 adds the client method
- **Gap #5:** Missing health check endpoint - Similar pattern of metadata endpoints

### 8.2 Future Enhancements

Once this gap is closed, consider:

1. **Capability Caching:**
   ```elixir
   defmodule Tinkex.CapabilityCache do
     # Cache server capabilities to avoid repeated API calls
     # Invalidate on config changes or explicit refresh
   end
   ```

2. **Model Validation Helpers:**
   ```elixir
   defmodule Tinkex.ModelValidator do
     def valid_model_id?(capabilities, model_id) do
       Enum.any?(capabilities.supported_models, &(&1.model_id == model_id))
     end

     def models_by_arch(capabilities, arch) do
       Enum.filter(capabilities.supported_models, &(&1.arch == arch))
     end
   end
   ```

3. **Type Guards:**
   ```elixir
   defguard is_llama_model(model) when model.arch == "llama"
   defguard is_qwen_model(model) when model.arch == "qwen2"
   ```

---

## 9. Conclusion

### 9.1 Summary

This gap represents a **type degradation anti-pattern** where structured API data is immediately flattened into primitive types, losing valuable metadata. While the current implementation "works" for basic use cases (displaying model names), it:

1. **Violates the principle of preserving API fidelity**
2. **Prevents future extensibility** (cannot add fields without breaking changes)
3. **Ships lossy responses in both SDKs** because FastAPI/Pydantic drop metadata
4. **Contradicts SDK's own patterns** (compare with `ModelData` usage in `GetInfoResponse`)

### 9.2 Recommended Action

**Priority:** Medium-High
**Effort:** 10 hours
**Risk:** Low

**Approach:**
1. Update Python `SupportedModel` (and FastAPI mock expectations) to include `model_id`/`arch` and retain future fields
2. Implement Elixir `SupportedModel` struct following TDD methodology
3. Update `GetServerCapabilitiesResponse` with backward-compatible parser
4. Add comprehensive test coverage (unit + property + integration) in both SDKs
5. Update examples and documentation
6. Release with clear migration guide

**Rationale:**
- Small, focused change with clear scope
- Aligns with existing SDK patterns
- Enables future enhancements
- Stops metadata loss in both SDKs and brings parity
- Low risk due to backward compatibility strategy

### 9.3 Learning Points

This gap highlights the importance of:

1. **Preserving API structure in types** - Don't throw away data
2. **Following existing patterns** - `ModelData` already existed
3. **Testing real responses** - Tests only validated string extraction
4. **Thinking about extensibility** - What happens when API adds fields?
5. **Maintaining parity** - Verify actual serialized shapes; don't assume another SDK is preserving fields

---

## Appendix A: API Response Examples

### A.1 Current mock server serialized response

```json
{
  "supported_models": [
    { "model_name": "meta-llama/Meta-Llama-3-8B" },
    { "model_name": "meta-llama/Meta-Llama-3-70B" },
    { "model_name": "Qwen/Qwen2-72B" }
  ]
}
```

### A.2 Current Elixir Parsing Result

```elixir
%Tinkex.Types.GetServerCapabilitiesResponse{
  supported_models: [
    "meta-llama/Meta-Llama-3-8B",
    "meta-llama/Meta-Llama-3-70B",
    "Qwen/Qwen2-72B"
  ]
}
```

### A.3 Desired Elixir Parsing Result

```elixir
%Tinkex.Types.GetServerCapabilitiesResponse{
  supported_models: [
    %Tinkex.Types.SupportedModel{
      model_id: "llama-3-8b",
      model_name: "meta-llama/Meta-Llama-3-8B",
      arch: "llama"
    },
    %Tinkex.Types.SupportedModel{
      model_id: "llama-3-70b",
      model_name: "meta-llama/Meta-Llama-3-70B",
      arch: "llama"
    },
    %Tinkex.Types.SupportedModel{
      model_id: "qwen2-72b",
      model_name: "Qwen/Qwen2-72B",
      arch: "qwen2"
    }
  ]
}
```

---

## Appendix B: References

### B.1 Files Analyzed

**Python SDK:**
- `tinker/src/tinker/types/get_server_capabilities_response.py` - Type definitions
- `tinker/src/tinker/_models.py` - BaseModel implementation
- `tinker/src/tinker/resources/service.py` - API resource methods
- `tinker/tests/mock_api_server.py` - Mock API implementation

**Elixir SDK:**
- `lib/tinkex/types/get_server_capabilities_response.ex` - Current type
- `lib/tinkex/types/model_data.ex` - Similar pattern for model metadata
- `lib/tinkex/types/get_info_response.ex` - Example of structured metadata
- `lib/tinkex/api/service.ex` - API module
- `test/tinkex/api/service_test.exs` - Current tests
- `examples/live_capabilities_and_logprobs.exs` - Usage example

### B.2 Related Documentation

- Gap #4: ServiceClient.get_server_capabilities (docs/20251126/gaps_03/)
- Verified Gap List (docs/20251126/gaps/VERIFIED_GAP_LIST.md)
- API Reference (docs/guides/api_reference.md)

---

**Document Version:** 1.1
**Last Updated:** November 27, 2025
**Author:** Claude Code Deep-Dive Investigation
