# Python SDK Parity: Commits e7a0d0c and 2d8e9d5

**Date:** 2025-12-14
**Source:** `./tinker` (Python SDK)
**Target:** Tinkex (Elixir SDK)
**Commits Analyzed:**
- `e7a0d0ca2dea07aebfb825d8fdc3b62b08c994ae` - Dec 15, 2025
- `2d8e9d5e00f746f39148a5d0cb760dff3f2eed43` - Dec 15, 2025

---

## Executive Summary

Two sync commits introduce:
1. **Breaking change**: API key prefix validation (`tml-` required)
2. **Documentation improvements**: Field-level docstrings across type modules + retry config
3. **Model name updates**: Examples updated from `Qwen2.5-7B` to `Qwen3-8B`

[REVIEWED] Commit `2d8e9d5` is doc-only (no Python runtime behavior changes); commit `e7a0d0c` contains the functional API key validation change.

---

## Commit e7a0d0c - Detailed Analysis

### 1. API Key Prefix Validation (BREAKING)

**Python Change:** `src/tinker/_client.py`
```python
if not api_key.startswith("tml-"):
    raise TinkerError("The api_key must start with the 'tml-' prefix")
```

**Elixir Target:** `lib/tinkex/config.ex` (in `Tinkex.Config.validate!/1`)

**Current Elixir Code:**
```elixir
def validate!(%__MODULE__{} = config) do
  unless config.api_key do
    raise ArgumentError,
          "api_key is required. Pass :api_key option or set TINKER_API_KEY env var"
  end
  # ... no prefix validation
end
```

**Required Change:**
```elixir
def validate!(%__MODULE__{} = config) do
  unless config.api_key do
    raise ArgumentError,
          "api_key is required. Pass :api_key option or set TINKER_API_KEY env var"
  end

  unless String.starts_with?(config.api_key, "tml-") do
    raise ArgumentError,
          "api_key must start with 'tml-' prefix"
  end
  # ...
end
```

[REVIEWED] **Test Impact:** This will break many existing Elixir tests (not just config tests). Current tests commonly use `"test-key"`, `"k"`, `"other-key"`, etc. Search results show numerous occurrences under `test/**/*.exs` that will need `tml-` prefixes or a shared helper.

[REVIEWED] **Already Implemented in Elixir:** API key masking/redaction exists (`Tinkex.Config.mask_api_key/1`) and is tested (`test/tinkex/config_test.exs`). This is adjacent to the change but not part of the Python commits.

---

### 2. RetryConfig Field Documentation

**Python Change:** `src/tinker/lib/retry_handler.py`

Added docstrings to `@dataclass` fields:

| Field | Python Docstring |
|-------|------------------|
| `max_connections` | Maximum number of concurrent connections allowed. |
| `progress_timeout` | Timeout in seconds before failing if no progress is made. |
| `retry_delay_base` | Initial delay in seconds before first retry. |
| `retry_delay_max` | Maximum delay in seconds between retries. |
| `jitter_factor` | Random jitter factor (0-1) applied to retry delays. |
| `enable_retry_logic` | Whether to enable automatic retries on failure. |
| `retryable_exceptions` | Exception types that should trigger a retry. |

**Elixir Target:** `lib/tinkex/retry_config.ex`

[REVIEWED] **Current State:** Has a `@moduledoc` and a clear `@type`, but no field-by-field documentation matching Python’s prose.

[REVIEWED] **Correction:** The Python change is *documentation-only* (docstrings on fields). Functional parity is already present (enable/disable toggle, backoff/jitter, progress timeout, connection limiting), but the surface differs:
- Python uses seconds; Elixir uses `*_ms` for most fields.
- Python includes `retryable_exceptions`; Elixir does not expose this knob publicly (Elixir likely relies on internal classification).

[REVIEWED] **Potential parity mismatch not mentioned:** Python’s `RetryConfig.max_connections` default is `DEFAULT_CONNECTION_LIMITS.max_connections or 100` (effectively 100). Elixir default is `@default_max_connections 1000` in `lib/tinkex/retry_config.ex`. This is not introduced by these Python commits, but the new Python docstring makes the mismatch more visible.

---

### 3. Type Module Documentation

#### 3.1 GetInfoResponse & ModelData

**Python Changes:** `src/tinker/types/get_info_response.py`

```python
class ModelData(BaseModel):
    """Metadata about a model's architecture and configuration."""
    arch: Optional[str] = None
    """The model architecture identifier."""
    model_name: Optional[str] = None
    """The human-readable model name."""
    tokenizer_id: Optional[str] = None
    """The identifier of the tokenizer used by this model."""

class GetInfoResponse(BaseModel):
    """Response containing information about a training client's model."""
    type: Optional[Literal["get_info"]] = None
    """Response type identifier."""
    model_data: ModelData
    """Detailed metadata about the model."""
    model_id: ModelID
    """Unique identifier for the model."""
    is_lora: Optional[bool] = None
    """Whether this is a LoRA fine-tuned model."""
    lora_rank: Optional[int] = None
    """The rank of the LoRA adaptation, if applicable."""
    model_name: Optional[str] = None
    """The name of the model."""
```

**Elixir Targets:**
- `lib/tinkex/types/get_info_response.ex` - Current `@moduledoc`: "Response payload containing active model metadata."
- `lib/tinkex/types/model_data.ex` - Current `@moduledoc`: "Model metadata including architecture, display name, and tokenizer id."

**Assessment:** Elixir moduledocs are already reasonable but could add field-level documentation in typespecs or via comments.
[REVIEWED] Elixir types do not typically use per-field docs; if we add them, prefer `@typedoc` on the struct type or expand `@moduledoc` “Fields” sections to avoid noisy inline comments.

---

#### 3.2 GetServerCapabilitiesResponse & SupportedModel

**Python Changes:** `src/tinker/types/get_server_capabilities_response.py`

```python
class SupportedModel(BaseModel):
    """Information about a model supported by the server."""
    model_name: Optional[str] = None
    """The name of the supported model."""

class GetServerCapabilitiesResponse(BaseModel):
    """Response containing the server's supported models and capabilities."""
    supported_models: List[SupportedModel]
    """List of models available on the server."""
```

**Elixir Targets:**
- `lib/tinkex/types/get_server_capabilities_response.ex` - Has good `@moduledoc`
- `lib/tinkex/types/supported_model.ex` - Has comprehensive `@moduledoc` with examples

**Assessment:** Elixir versions are already well-documented. No changes needed.

---

#### 3.3 CreateModelRequest

**Python Changes:** `src/tinker/types/create_model_request.py`

```python
class CreateModelRequest(StrictBase):
    model_seq_id: int
    base_model: str
    """The name of the base model to fine-tune (e.g., 'Qwen/Qwen3-8B')."""
    user_metadata: Optional[dict[str, Any]] = None
    """Optional metadata about this model/training run, set by the end-user."""
    lora_config: Optional[LoraConfig] = None
    """LoRA configuration"""
```

**Elixir Target:** `lib/tinkex/types/create_model_request.ex`

**Current `@moduledoc`:** "Request to create a new model. Mirrors Python tinker.types.CreateModelRequest."

**Required Change:** Add field documentation to struct definition or typespecs.
[REVIEWED] **Note:** Elixir currently defaults `lora_config` to `%LoraConfig{}` (non-optional), while Python’s `lora_config` is optional. This is an Elixir-specific semantic difference worth calling out if strict parity is desired (it affects JSON encoding defaults).

---

#### 3.4 ForwardBackwardOutput

**Python Change:** `src/tinker/types/forward_backward_output.py`

```python
loss_fn_output_type: str
"""The class name of the loss function output records (e.g., 'TorchLossReturn', 'ArrayRecord')."""
```

**Elixir Target:** `lib/tinkex/types/forward_backward_output.ex`

**Current `@moduledoc`:** Has good doc but `loss_fn_output_type` field undocumented.

**Required Change:** Clarify that this is the class name of loss function output records.

---

### 4. Model Name Example Updates

**Python Changes:** Updated all documentation examples from `Qwen/Qwen2.5-7B` to `Qwen/Qwen3-8B`.

**Files Changed:**
- `docs/api/samplingclient.md`
- `docs/api/serviceclient.md`
- `docs/api/trainingclient.md`
- Various Python source file docstrings

[REVIEWED] **Elixir Action (scoped):** Update *user-facing docs/examples* where appropriate. Many `Qwen/Qwen2.5-7B` references appear in tests and internal research docs; those can be skipped unless they are used as public documentation. (Tests must still pass; changing these strings in tests is optional unless the tests assert on the exact help/docs text.)

---

### 5. Test API Key Updates

**Python Changes:** `tests/conftest.py`, `tests/test_client.py`

```python
# Before
api_key = "My API Key"

# After
api_key = "tml-My API Key"
```

Also added new test:
```python
def test_api_key_prefix_validation(self) -> None:
    with pytest.raises(TinkerError):
        Tinker(base_url=base_url, api_key="not-tml-prefix", _strict_response_validation=True)
```

**Elixir Action:**
1. Update test fixtures to use `tml-` prefixed keys
2. Add test for prefix validation error

---

## Commit 2d8e9d5 - Detailed Analysis

### 1. SamplingClient Documentation Polish

[REVIEWED] **Correction:** This commit modifies `docs/api/samplingclient.md` (not `src/tinker/lib/public_interfaces/sampling_client.py`). The `SamplingClient` docstring change in the Python source landed in `e7a0d0c`.

Changed docstring format:
```python
# Before
Args:
- `holder`: Internal client managing HTTP connections and async operations
- `model_path`: Path to saved model weights (starts with 'tinker://')
- `base_model`: Name of base model to use for inference

# After
Create method parameters:
- `model_path`: Path to saved model weights (starts with 'tinker://')
- `base_model`: Name of base model to use for inference (e.g., 'Qwen/Qwen3-8B')
```

Removed internal `holder` parameter from public docs.

**Elixir Target:** `lib/tinkex/sampling_client.ex`

**Assessment:** Elixir version doesn't expose internal holder. Moduledoc focuses on user-facing behavior. Minor polish only.

---

### 2. Additional Type Documentation (docs/api/types.md)

Extended documentation for:
- `AdamParams.weight_decay` and `grad_clip_norm`
- `SupportedModel` and `GetServerCapabilitiesResponse`
- `ModelData` and `GetInfoResponse`
- `CreateModelRequest` field descriptions

**Assessment:** These are doc-only changes. Elixir typespecs and moduledocs should be reviewed for parity.
[REVIEWED] The Elixir equivalents are primarily:
- `lib/tinkex/types/adam_params.ex` (for `weight_decay`, `grad_clip_norm`)
- `lib/tinkex/types/forward_backward_output.ex` (for `loss_fn_output_type`)
- `lib/tinkex/types/get_info_response.ex` / `lib/tinkex/types/model_data.ex`
- `lib/tinkex/types/create_model_request.ex`

---

## Implementation Checklist

### High Priority (Breaking/Functional)

- [ ] Add API key `tml-` prefix validation in `lib/tinkex/config.ex`
- [ ] Update all test API keys to use `tml-` prefix
- [ ] Add test case for API key prefix validation error

### Medium Priority (Documentation)

- [ ] Add field docs to `lib/tinkex/retry_config.ex`
- [ ] Add field docs to `lib/tinkex/types/create_model_request.ex`
- [ ] Clarify `loss_fn_output_type` in `lib/tinkex/types/forward_backward_output.ex`
- [ ] Review `lib/tinkex/types/get_info_response.ex` field documentation
- [ ] Review `lib/tinkex/types/model_data.ex` field documentation

### Low Priority (Polish)

- [ ] Search and update `Qwen2.5-7B` references to `Qwen3-8B`
- [ ] Review SamplingClient moduledoc for consistency

---

## File Mapping Reference

| Python File | Elixir Equivalent |
|-------------|-------------------|
| `src/tinker/_client.py` | `lib/tinkex/config.ex` |
| `src/tinker/lib/retry_handler.py` | `lib/tinkex/retry_config.ex` |
| `src/tinker/lib/public_interfaces/sampling_client.py` | `lib/tinkex/sampling_client.ex` |
| `src/tinker/lib/public_interfaces/training_client.py` | `lib/tinkex/training_client.ex` |
| `src/tinker/lib/public_interfaces/service_client.py` | `lib/tinkex/service_client.ex` |
| `src/tinker/types/create_model_request.py` | `lib/tinkex/types/create_model_request.ex` |
| `src/tinker/types/forward_backward_output.py` | `lib/tinkex/types/forward_backward_output.ex` |
| `src/tinker/types/get_info_response.py` | `lib/tinkex/types/get_info_response.ex` |
| `src/tinker/types/get_server_capabilities_response.py` | `lib/tinkex/types/get_server_capabilities_response.ex` |
| `tests/conftest.py` | `test/support/*.ex` |
| `tests/test_client.py` | `test/tinkex/config_test.exs` (+ many other `test/**/*.exs` that construct configs/clients) |

---

## Open Questions

[REVIEWED] 1. Python enforces the prefix unconditionally; if Elixir adds a bypass knob, it will be a deliberate divergence (and should be documented as such).
[REVIEWED] 2. Elixir currently does not expose `retryable_exceptions` like Python; confirm internal classification matches expected retry semantics.
3. Should model name examples use a generic placeholder vs. specific model names?
