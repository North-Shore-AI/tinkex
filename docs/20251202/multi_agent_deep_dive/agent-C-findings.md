# Agent C: Cross-Cutting Parity Analysis Findings

## Scope
Comprehensive comparison of Python SDK (`/home/home/p/g/North-Shore-AI/tinkex/tinker/`) and Elixir SDK (`/home/home/p/g/North-Shore-AI/tinkex/`) across interface schemas, default values, documentation alignment, and API parity. Analysis based on upstream commit 0622760 and ADRs 001-006.

## Evidence
All file references use absolute paths from repository root.

## Parity Matrix

| Feature | Python | Elixir | Status | Risk |
|---------|--------|--------|--------|------|
| **Image chunk schema** | `expected_tokens` only (no height/width/tokens) | Still has `height`, `width`, `tokens` (enforced keys) | ❌ **BREAKING DIVERGENCE** | **CRITICAL** - Wire format mismatch, will cause request failures |
| **Image chunk `.length`** | Raises if `expected_tokens` is None | Returns `tokens` field (always present) | ❌ **BREAKING DIVERGENCE** | **HIGH** - No validation of expected_tokens |
| **Chunk counting (batching)** | Uses `len(chunk.data)` for images, `len(chunk.location)` for asset pointers | Uses `ModelInput.length()` which calls chunk `.length` (depends on `tokens`) | ❌ **BREAKING DIVERGENCE** | **CRITICAL** - Will crash when ADR-002 lands without ADR-003 |
| **Checkpoint resume helpers** | `create_training_client_from_state_with_optimizer` + async variants | `load_optimizer: true` opt via existing function only | ⚠️ **ERGONOMICS GAP** | **MEDIUM** - Users must know about hidden option |
| **Checkpoint resume defaults** | Weights-only explicitly documented | Weights-only implemented but not documented | ⚠️ **DOCUMENTATION GAP** | **LOW** - Behavior matches but unclear |
| **CLI multi-delete** | Accepts multiple paths, validates all, progress bar | Single path only, no batch support | ❌ **FEATURE GAP** | **LOW** - UX only, no breaking change |
| **Progress timeout default** | 120 minutes (7,200,000 ms) | 30 minutes (1,800,000 ms) | ❌ **DEFAULT MISMATCH** | **HIGH** - 4x premature timeouts for long ops |
| **Llama-3 tokenizer repo** | `thinkingmachineslabinc/meta-llama-3-tokenizer` | `baseten/Meta-Llama-3-tokenizer` | ❌ **CONFIG MISMATCH** | **MEDIUM** - Gating issues, inconsistent tokenization |
| **LoadWeightsRequest schema** | `optimizer: bool` (required field) | `optimizer: bool` (defaults to false) | ✅ **ALIGNED** | **NONE** - Both support same wire format |
| **ImageChunk wire format** | `{data, format, expected_tokens?, type}` | `{data, format, height, width, tokens, expected_tokens?, type}` | ❌ **BREAKING DIVERGENCE** | **CRITICAL** - Extra fields sent to API |
| **ImageAssetPointerChunk wire** | `{location, format, expected_tokens?, type}` | `{location, format, height, width, tokens, type}` | ❌ **BREAKING DIVERGENCE** | **CRITICAL** - Extra fields sent to API |

## Detailed Findings

### 1. Multimodal Schema Parity

#### Python Implementation
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_chunk.py` (lines 12-44)
- **Schema**:
  ```python
  class ImageChunk(StrictBase):
      data: bytes
      format: Literal["png", "jpeg"]
      expected_tokens: int | None = None
      type: Literal["image"] = "image"
  ```
- **`.length` behavior** (line 41-44): Raises `ValueError` if `expected_tokens is None`
- **No height/width/tokens fields present**

#### Elixir Implementation
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_chunk.ex` (lines 40-52)
- **Schema**:
  ```elixir
  @enforce_keys [:data, :format, :height, :width, :tokens]
  defstruct [:data, :format, :height, :width, :tokens, :expected_tokens, type: "image"]
  ```
- **`.length` behavior** (line 96): Returns `tokens` field (no validation)
- **Wire encoding** (lines 99-121): Serializes `height`, `width`, `tokens` to JSON

#### Image Asset Pointer - Python
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/image_asset_pointer_chunk.py` (lines 8-27)
- **Schema**: Only `location`, `format`, `expected_tokens`, `type`
- **`.length` behavior** (line 24-27): Raises `ValueError` if `expected_tokens is None`

#### Image Asset Pointer - Elixir
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/image_asset_pointer_chunk.ex` (lines 10-27)
- **Schema**: Has `location`, `format`, `height`, `width`, `tokens`, `type` (no `expected_tokens`)
- **`.length` behavior** (line 27): Returns `tokens` field
- **Wire encoding** (lines 30-44): Serializes all fields including height/width/tokens

#### Impact Assessment
- **Wire format incompatibility**: Elixir sends 3 extra fields (`height`, `width`, `tokens`) that Python/backend no longer expect
- **Validation missing**: Elixir never checks `expected_tokens`, defeating the early-rejection purpose
- **Breaking change required**: Elixir must drop the 3 fields to match Python (ADR-002)
- **No migration path**: Current Elixir code enforces these keys, so all callers must update

### 2. Checkpoint/Resume Parity

#### Python Implementation - Helper Methods
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/public_interfaces/service_client.py`
- **Weights-only** (lines 222-257):
  ```python
  def create_training_client_from_state(self, path: str, ...) -> TrainingClient:
      """This loads only the model weights, not optimizer state."""
      training_client = self.create_lora_training_client(...)
      training_client.load_state(path).result()
      return training_client
  ```
- **With optimizer** (lines 283-319):
  ```python
  def create_training_client_from_state_with_optimizer(self, path: str, ...) -> TrainingClient:
      """This is similar to create_training_client_from_state but also restores optimizer state."""
      training_client = self.create_lora_training_client(...)
      training_client.load_state_with_optimizer(path).result()
      return training_client
  ```
- **Documentation**: Explicitly distinguishes weights-only vs. weights+optimizer in docstrings

#### Elixir Implementation - Unified Method
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/service_client.ex`
- **Public API** (lines 75-92):
  ```elixir
  @spec create_training_client_from_state(t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def create_training_client_from_state(service_client, path, opts \\ [])
  ```
- **Implementation** (lines 298-329): Checks `Keyword.get(opts, :load_optimizer, false)` in private helper
- **Private helper** (lines 436-446):
  ```elixir
  defp load_checkpoint(training_client_module, training_client, path, opts) do
    load_fn =
      if Keyword.get(opts, :load_optimizer, false) do
        &training_client_module.load_state_with_optimizer/3
      else
        &training_client_module.load_state/3
      end
    load_fn.(training_client, path, load_opts)
  end
  ```
- **Documentation gap**: No mention of `:load_optimizer` option in public docs (line 73-74 only says "may reset optimizer state")
- **No dedicated helper**: Users must discover the `:load_optimizer` option

#### LoadWeightsRequest Schema - Both SDKs
- **Python**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/load_weights_request.py` (lines 11-27)
  - `optimizer: bool` (required field, no default)
- **Elixir**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/load_weights_request.ex` (lines 34-44)
  - `optimizer: false` (default in defstruct)
  - Wire format identical to Python when serialized

#### Gap Analysis
- **Ergonomics**: Python provides explicit `create_training_client_from_state_with_optimizer()` method; Elixir requires knowing about hidden `:load_optimizer` opt
- **Documentation**: Python clearly documents the distinction; Elixir mentions "may reset" but doesn't explain how to preserve
- **ADR-001 proposal**: Add explicit helper to Elixir for parity
- **Risk**: Medium - Elixir users may unknowingly reset optimizer state when resuming training

### 3. CLI Command Parity

#### Python Implementation - Multi-Delete
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/cli/commands/checkpoint.py` (lines 428-469)
- **Signature**: `def delete(..., checkpoint_paths: tuple[str, ...], yes: bool)`
- **Features**:
  - Accepts multiple paths as arguments
  - Validates all paths upfront (line 437-442)
  - Shows confirmation with count (line 446-456)
  - Progress bar during deletion (line 461-468)
  - Deletes sequentially with `click.progressbar`

#### Elixir Implementation - Single Delete
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/cli.ex` (lines 944-956)
- **Signature**: `defp checkpoint_delete(config, options, deps)`
- **Features**:
  - Single path only: `path = Map.fetch!(options, :path)`
  - No confirmation prompt
  - No progress indicator
  - Immediate deletion via `deps.rest_api_module.delete_checkpoint(config, path)`

#### Gap Analysis
- **UX difference**: Python provides bulk delete with safety prompts; Elixir requires repeated CLI invocations
- **Error handling**: Python validates all paths before any deletes; Elixir fails on first error
- **ADR-004 proposal**: Update Elixir CLI to accept multiple paths and show progress
- **Risk**: Low - UX convenience only, no breaking changes to API

### 4. Timeout/Retry Parity

#### Python Configuration
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/retry_handler.py` (line 41)
- **Default**: `progress_timeout: float = 120 * 60  # 7200 seconds`
- **Usage**: Line 124-145 checks deadline and raises `TinkerError` with "No progress made in {progress_timeout}s"

#### Elixir Configuration
- **Files**:
  - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_handler.ex` (line 10): `@default_progress_timeout_ms 1_800_000`
  - `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_config.ex` (line 35): `@default_progress_timeout_ms 1_800_000`
- **Default**: 30 minutes (1,800,000 ms = 1800 seconds)
- **Usage**: Lines 105-110 check elapsed time against `handler.progress_timeout_ms`

#### Impact Assessment
- **4x difference**: Python waits 120 minutes by default; Elixir times out at 30 minutes
- **Use case**: Long-running checkpoints, large model saves, heavy training steps can legitimately exceed 30 minutes
- **Risk**: High - Elixir users will experience premature timeouts that Python users don't see
- **ADR-005 proposal**: Raise Elixir default to 7,200,000 ms (120 minutes) for parity

### 5. Tokenizer Parity

#### Python Configuration
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/public_interfaces/training_client.py` (line 890)
- **Llama-3 override**: `tokenizer_id = "thinkingmachineslabinc/meta-llama-3-tokenizer"`
- **Condition**: When model name starts with `"meta-llama/Llama-3"`

#### Elixir Configuration
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer.ex` (line 16)
- **Llama-3 override**: `@llama3_tokenizer "baseten/Meta-Llama-3-tokenizer"`
- **Usage**: Line 193 applies this override when model name matches Llama-3 pattern
- **Documentation**: Line 28 mentions the workaround in module docs

#### Gap Analysis
- **Different repos**: Elixir uses `baseten/Meta-Llama-3-tokenizer`, Python uses `thinkingmachineslabinc/meta-llama-3-tokenizer`
- **Gating risk**: The `baseten` repo may be gated; `thinkingmachineslabinc` repo avoids this (per ADR-006)
- **Tokenization consistency**: Different tokenizer repos may have different vocabulary or special tokens
- **Risk**: Medium - Tokenization differences could cause subtle training/inference mismatches
- **ADR-006 proposal**: Update Elixir constant to match Python

### 6. Type/Schema Alignment

#### Batch Counting - Python
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/public_interfaces/training_client.py` (lines 124-134)
- **Method**: `_estimate_number_count_in_chunk`
  ```python
  def _estimate_number_count_in_chunk(self, chunk: types.ModelInputChunk) -> int:
      if isinstance(chunk, types.ImageChunk):
          return len(chunk.data)  # base64 string length
      if isinstance(chunk, types.ImageAssetPointerChunk):
          return len(chunk.location)  # location string length
      return chunk.length  # other chunks
  ```
- **Method**: `_estimate_number_count` (lines 131-134) - sums chunk counts + loss input lengths
- **Batching logic**: Lines 136-156 use estimates to split data into chunks bounded by `MAX_CHUNK_NUMBER_COUNT = 500000` and `MAX_CHUNK_LEN = 128`

#### Batch Counting - Elixir
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/training_client.ex` (lines 1259-1276)
- **Method**: `estimate_number_count`
  ```elixir
  defp estimate_number_count(%{model_input: model_input, loss_fn_inputs: loss_inputs}) do
    model_input_count =
      case model_input do
        nil -> 0
        %_{} -> Tinkex.Types.ModelInput.length(model_input)  # calls chunk.length on each
        _ -> 0
      end
    loss_count = ... # sums length(data) for loss inputs
    model_input_count + loss_count
  end
  ```
- **Delegation**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/model_input.ex` (lines 89-98)
  ```elixir
  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, &chunk_length/1))
  end

  defp chunk_length(%ImageChunk{} = chunk), do: ImageChunk.length(chunk)  # returns tokens field
  ```
- **Constants**: Lines 62-63 define `@max_chunk_len 128` and `@max_chunk_number_count 500_000` (matching Python)

#### Impact Assessment
- **Critical dependency**: Elixir counting depends on `ImageChunk.length()` returning `tokens` field
- **ADR-002 breaks counting**: When `tokens` field is removed, `ModelInput.length()` will crash unless updated
- **ADR-003 solution**: Implement Python's heuristic counting (string lengths for images) in Elixir
- **Risk**: Critical - ADR-002 without ADR-003 causes runtime crashes in batching logic
- **Implementation order**: Must apply ADR-003 simultaneously with ADR-002

#### Forward/Backward Request Schema - Both SDKs
- **Python**: `/home/home/p/g/North-Shore-AI/tinkex/tinker/src/tinker/types/forward_backward_request.py`
  - Schema includes `Datum` list with `model_input: ModelInput` and `loss_fn_inputs: dict`
- **Elixir**: `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/forward_backward_request.ex`
  - Identical schema structure
- **Parity**: ✅ Aligned at request level; divergence is in chunk types only

## Critical Parity Gaps

### Priority 1: CRITICAL (Must Fix Before Production Use)
1. **Image chunk schema mismatch (ADR-002)**
   - **Issue**: Elixir sends `height`, `width`, `tokens` fields that Python/backend don't expect
   - **Impact**: Request failures, API rejections, potential data corruption
   - **Blocker**: Prevents multimodal training/inference on Elixir SDK
   - **Fix**: Remove 3 fields from `ImageChunk` and `ImageAssetPointerChunk` structs, add `expected_tokens`

2. **Chunk counting dependency (ADR-003)**
   - **Issue**: Elixir counting logic will crash when `tokens` field is removed (ADR-002)
   - **Impact**: All training operations fail during batching
   - **Blocker**: ADR-002 cannot land without this fix
   - **Fix**: Replace `ModelInput.length()` calls with heuristic counting (string lengths for images)

### Priority 2: HIGH (Breaks User Expectations)
3. **Progress timeout difference (ADR-005)**
   - **Issue**: Elixir times out 4x faster than Python (30min vs 120min)
   - **Impact**: Long-running operations fail prematurely on Elixir but succeed on Python
   - **User friction**: Cross-SDK inconsistency causes confusion and support burden
   - **Fix**: Change both constants to 7,200,000 ms (120 minutes)

### Priority 3: MEDIUM (Ergonomics & Consistency)
4. **Checkpoint resume ergonomics (ADR-001)**
   - **Issue**: Python has explicit `create_training_client_from_state_with_optimizer()` method; Elixir hides it in `:load_optimizer` opt
   - **Impact**: Elixir users may unknowingly reset optimizer state, harming training continuity
   - **Documentation gap**: Elixir docs don't mention `:load_optimizer` option
   - **Fix**: Add public helper method and update docs

5. **Tokenizer repo mismatch (ADR-006)**
   - **Issue**: Different Llama-3 tokenizer repos (`baseten` vs `thinkingmachineslabinc`)
   - **Impact**: Potential gating issues, inconsistent tokenization across SDKs
   - **Fix**: Update Elixir constant to match Python repo

### Priority 4: LOW (UX Convenience)
6. **CLI multi-delete (ADR-004)**
   - **Issue**: Python supports bulk delete with progress bar; Elixir requires repeated invocations
   - **Impact**: Poor UX for cleanup operations
   - **Fix**: Update CLI parsing to accept multiple paths and show progress

## Documentation Alignment Issues

### ADR-001: Optimizer Resume
- **Python docs**: Clearly distinguish weights-only vs. weights+optimizer in method names and docstrings
- **Elixir docs**: Vague mention of "may reset optimizer state" without explaining how to preserve it
- **Alignment needed**: Document `:load_optimizer` option and add public helper method

### ADR-002: Image Chunk Schema
- **Python docs**: Updated to remove references to height/width/tokens
- **Elixir docs**: Still document and require these fields in examples (lines 25-35 in `image_chunk.ex`)
- **Alignment needed**: Update all docs, examples, and tests to remove old fields and show `expected_tokens` usage

### ADR-003: Chunk Counting
- **Python docs**: No user-facing docs (internal batching logic)
- **Elixir docs**: No user-facing docs (internal batching logic)
- **Alignment needed**: None (internal implementation detail)

### ADR-005: Progress Timeout
- **Python docs**: Default mentioned in retry handler docs
- **Elixir docs**: Need to update guide (`docs/guides/retry_and_error_handling.md` referenced in ADR-005)
- **Alignment needed**: Document the new 120-minute default and rationale

### ADR-006: Tokenizer Override
- **Python docs**: Tokenizer heuristics mentioned in training client docs
- **Elixir docs**: Mentions Llama-3 workaround but with old repo name (line 28 in `tokenizer.ex`)
- **Alignment needed**: Update module docs and CHANGELOG to reflect new repo

### Multimodal Viability Doc
- **File**: `/home/home/p/g/North-Shore-AI/tinkex/docs/20251202/multimodal_viability.md`
- **Accuracy**: Correctly identifies Elixir's outdated schema and proposes ADR-002/003 as solution
- **Alignment**: ✅ Accurately reflects both codebases' current state

## Suggested Actions

### Immediate (Before Next Release)
1. **Apply ADR-002 + ADR-003 atomically**:
   - Update `ImageChunk` and `ImageAssetPointerChunk` structs (remove height/width/tokens, add `expected_tokens`)
   - Update `ModelInput.length()` and counting helpers to use string-length heuristics
   - Update JSON encoders to match new wire format
   - Add tests for mixed text+image batching
   - **Timeline**: Single PR, comprehensive test coverage required

2. **Apply ADR-005 (timeout increase)**:
   - Change both constants in `retry_handler.ex` and `retry_config.ex` to 7,200,000 ms
   - Add regression test verifying default value
   - Update retry guide documentation
   - **Timeline**: Small PR, can merge independently

3. **Apply ADR-006 (tokenizer repo)**:
   - Change `@llama3_tokenizer` constant to `"thinkingmachineslabinc/meta-llama-3-tokenizer"`
   - Update module docs
   - Add CHANGELOG entry about clearing cached tokenizers
   - **Timeline**: Small PR, can merge independently

### Short-Term (Next Sprint)
4. **Apply ADR-001 (optimizer resume ergonomics)**:
   - Add `create_training_client_from_state_with_optimizer/3` and async variant to `service_client.ex`
   - Update docs to clearly distinguish weights-only vs. weights+optimizer
   - Add integration tests for both paths
   - **Timeline**: Medium PR, public API addition

5. **Apply ADR-004 (CLI multi-delete)**:
   - Update CLI parsing to accept multiple paths
   - Add validation and confirmation prompt
   - Add progress indicator (spinner or per-path log)
   - Return summary map for test assertions
   - **Timeline**: Medium PR, localized to CLI code

### Documentation Updates (Parallel Track)
6. **Update all examples and guides**:
   - Remove references to `height`, `width`, `tokens` in image chunk examples
   - Add `expected_tokens` usage examples
   - Document checkpoint resume with optimizer state preservation
   - Update retry/timeout documentation with new defaults
   - **Timeline**: Ongoing, coordinate with code changes

### Testing Strategy
7. **Cross-SDK integration tests**:
   - Test Elixir requests against Python-generated checkpoints
   - Verify wire format compatibility after ADR-002
   - Test timeout behavior under long-running operations
   - Validate tokenizer output matches between SDKs
   - **Timeline**: Add to CI pipeline after code changes land

## Confidence

**HIGH** confidence in findings based on:
- ✅ Direct code inspection of both Python and Elixir implementations
- ✅ Line-by-line comparison of schema definitions and wire encoders
- ✅ Verification against ADR proposals and upstream changes document
- ✅ Tracing execution paths through batching, counting, and serialization logic
- ✅ Validation of default values in configuration modules

**Specific confidence levels**:
- Image chunk schema mismatch: **100%** - Enforced keys and wire encoders confirm divergence
- Counting logic dependency: **100%** - Direct code path shows `ModelInput.length()` → `chunk.length()` → `tokens` field
- Timeout difference: **100%** - Constants are explicit in both codebases
- Tokenizer repo: **100%** - String constants differ in source code
- Checkpoint resume ergonomics: **95%** - Implementation confirmed, only user impact is subjective
- CLI multi-delete: **100%** - Single-path signature vs. tuple argument confirmed

**Areas of uncertainty**: None significant. All comparisons based on verifiable source code.
