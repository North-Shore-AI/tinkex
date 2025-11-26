# ADR-002: Type System Updates

**Status:** Proposed
**Date:** 2025-11-25
**Decision Makers:** TBD
**Technical Story:** Porting new and updated types from Python Tinker SDK

## Context

The Python Tinker SDK commits (2025-11-25) introduced:
1. **New Types**: `WeightsInfoResponse`, `GetSamplerResponse`
2. **Type Updates**: `LossFnType` (expanded), `ImageChunk` (new field), `LoadWeightsRequest` (new field)

TinKex must implement these changes to maintain API compatibility.

## Decision Drivers

1. **API Compatibility** - Types must match Python SDK wire format
2. **Type Safety** - Leverage Elixir's type system effectively
3. **Consistency** - Follow existing TinKex type patterns
4. **JSON Serialization** - Must correctly serialize/deserialize with Jason
5. **Documentation** - Types should be well-documented

## Changes Required

### 1. New Type: WeightsInfoResponse

**Wire Format:**
```json
{
  "base_model": "Qwen/Qwen2.5-7B",
  "is_lora": true,
  "lora_rank": 32
}
```

**Decision:** Create new module at `lib/tinkex/types/weights_info_response.ex`

**Rationale:**
- Follows existing pattern (one type per file)
- Contains three fields: `base_model`, `is_lora`, `lora_rank` (optional)
- Used by new `get_weights_info_by_tinker_path` API method

### 2. New Type: GetSamplerResponse

**Wire Format:**
```json
{
  "sampler_id": "session-id:sample:0",
  "base_model": "Qwen/Qwen2.5-7B",
  "model_path": "tinker://run-id/weights/001"
}
```

**Decision:** Create new module at `lib/tinkex/types/get_sampler_response.ex`

**Rationale:**
- Follows existing pattern
- Contains three fields: `sampler_id`, `base_model`, `model_path` (optional)
- Used by new `get_sampler` API method

### 3. Updated Type: LossFnType

**Current:**
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo
```

**Required:**
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro
```

**Decision:** Update existing module to add `:cispo` and `:dro`

**Rationale:**
- Backward compatible (existing values still work)
- New loss functions for advanced training scenarios
- Wire format strings: `"cispo"`, `"dro"`

### 4. Updated Type: ImageChunk

**Current Fields:**
- `data`, `format`, `height`, `width`, `tokens`, `type`

**New Field:**
- `expected_tokens: non_neg_integer() | nil`

**Decision:** Add `expected_tokens` field with `nil` default

**Rationale:**
- Advisory field for request validation
- Backend computes actual tokens; this allows fast-fail if mismatch
- Optional field, backward compatible
- Update Jason.Encoder to include when non-nil

### 5. Updated Type: LoadWeightsRequest

**Current Fields:**
- `path`

**New Field:**
- `load_optimizer_state: boolean()` (default: `false`)

**Decision:** Add `load_optimizer_state` field with `false` default

**Rationale:**
- Controls whether optimizer state is restored with weights
- Default false maintains backward compatibility
- Required for advanced training scenarios (resuming training)

## Implementation Plan

### Phase 1: Create New Types

```elixir
# lib/tinkex/types/weights_info_response.ex
defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc "..."
  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]
  @type t :: %__MODULE__{...}
  def from_json(json), do: ...
end

# lib/tinkex/types/get_sampler_response.ex
defmodule Tinkex.Types.GetSamplerResponse do
  @moduledoc "..."
  @enforce_keys [:sampler_id, :base_model]
  defstruct [:sampler_id, :base_model, :model_path]
  @type t :: %__MODULE__{...}
  def from_json(json), do: ...
end
```

### Phase 2: Update Existing Types

```elixir
# lib/tinkex/types/loss_fn_type.ex
# Add to @type t:
:cispo | :dro

# Add parse clauses:
def parse("cispo"), do: :cispo
def parse("dro"), do: :dro

# Add to_string clauses:
def to_string(:cispo), do: "cispo"
def to_string(:dro), do: "dro"
```

```elixir
# lib/tinkex/types/image_chunk.ex
# Add to struct:
defstruct [..., :expected_tokens, ...]

# Add to @type t:
expected_tokens: non_neg_integer() | nil

# Update new/5 to new/6 with opts:
def new(binary, format, height, width, tokens, opts \\ [])

# Update Jason.Encoder:
map = if chunk.expected_tokens, do: Map.put(map, :expected_tokens, ...), else: map
```

```elixir
# lib/tinkex/types/load_weights_request.ex
# Add to struct:
defstruct [:path, load_optimizer_state: false]

# Add to @type t:
load_optimizer_state: boolean()

# Update Jason.Encoder:
%{path: req.path, load_optimizer_state: req.load_optimizer_state}
```

### Phase 3: Update Type Exports

Ensure `Tinkex.Types` module exports the new types (if using a barrel module).

### Phase 4: Tests

Create/update tests for each type:
- Unit tests for `from_json/1`
- Unit tests for Jason encoding
- Property tests for round-trip serialization

## Consequences

### Positive
- Full API compatibility with Python SDK
- Type safety for new API methods
- Well-documented type system
- Backward compatible updates

### Negative
- Additional modules to maintain
- Slightly increased surface area

### Neutral
- Follows existing TinKex patterns
- Standard Elixir struct + Jason approach

## Test Strategy

### WeightsInfoResponse Tests
```elixir
test "from_json/1 parses complete response" do
  json = %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => true, "lora_rank" => 32}
  assert %WeightsInfoResponse{base_model: "Qwen/Qwen2.5-7B", is_lora: true, lora_rank: 32} =
           WeightsInfoResponse.from_json(json)
end

test "from_json/1 handles nil lora_rank" do
  json = %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => false}
  assert %WeightsInfoResponse{lora_rank: nil} = WeightsInfoResponse.from_json(json)
end

test "Jason encoding round-trips" do
  original = %WeightsInfoResponse{base_model: "test", is_lora: true, lora_rank: 16}
  encoded = Jason.encode!(original)
  decoded = Jason.decode!(encoded)
  assert %WeightsInfoResponse{} = WeightsInfoResponse.from_json(decoded)
end
```

### LossFnType Tests
```elixir
test "parse/1 handles new loss types" do
  assert :cispo = LossFnType.parse("cispo")
  assert :dro = LossFnType.parse("dro")
end

test "to_string/1 handles new loss types" do
  assert "cispo" = LossFnType.to_string(:cispo)
  assert "dro" = LossFnType.to_string(:dro)
end
```

### ImageChunk Tests
```elixir
test "new/6 with expected_tokens option" do
  chunk = ImageChunk.new(<<1, 2, 3>>, :png, 512, 512, 256, expected_tokens: 256)
  assert chunk.expected_tokens == 256
end

test "Jason encoding includes expected_tokens when present" do
  chunk = ImageChunk.new(<<1, 2, 3>>, :png, 512, 512, 256, expected_tokens: 256)
  encoded = Jason.encode!(chunk)
  decoded = Jason.decode!(encoded)
  assert decoded["expected_tokens"] == 256
end

test "Jason encoding excludes expected_tokens when nil" do
  chunk = ImageChunk.new(<<1, 2, 3>>, :png, 512, 512, 256)
  encoded = Jason.encode!(chunk)
  decoded = Jason.decode!(encoded)
  refute Map.has_key?(decoded, "expected_tokens")
end
```

## Links

- [ELIXIR_MAPPING.md](../ELIXIR_MAPPING.md) - Full implementation templates
- [COMMIT_ANALYSIS.md](../COMMIT_ANALYSIS.md) - Source commit analysis
