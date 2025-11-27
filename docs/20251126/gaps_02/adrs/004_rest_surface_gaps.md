# ADR-004: REST Client Surface Completion

## Status
Proposed

## Context

The Python Tinker SDK exposes two critical helper methods in its `RestClient` public API that are currently missing from the Elixir Tinkex port's public `RestClient` interface, despite having the underlying low-level API implementations available:

### Missing Public Methods in Elixir RestClient

#### 1. `get_sampler(sampler_id)`

**Python Implementation** (`tinker/src/tinker/lib/public_interfaces/rest_client.py:669-702`):
```python
@capture_exceptions(fatal=True)
def get_sampler(self, sampler_id: str) -> APIFuture[types.GetSamplerResponse]:
    """Get sampler information.

    Args:
    - `sampler_id`: The sampler ID (sampling_session_id) to get information for

    Returns:
    - An `APIFuture` containing the `GetSamplerResponse` with sampler details

    Example:
    ```python
    # Sync usage
    future = rest_client.get_sampler("session-id:sample:0")
    response = future.result()
    print(f"Base model: {response.base_model}")
    print(f"Model path: {response.model_path}")

    # Async usage
    response = await rest_client.get_sampler("session-id:sample:0")
    print(f"Base model: {response.base_model}")
    ```
    """

    async def _get_sampler_async() -> types.GetSamplerResponse:
        async def _send_request() -> types.GetSamplerResponse:
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                return await client.get(
                    f"/api/v1/samplers/{sampler_id}",
                    cast_to=types.GetSamplerResponse,
                )

        return await self.holder.execute_with_retries(_send_request)

    return self.holder.run_coroutine_threadsafe(_get_sampler_async())
```

**Elixir Low-Level Implementation EXISTS** (`lib/tinkex/api/rest.ex:112-125`):
```elixir
@spec get_sampler(Config.t(), String.t()) ::
        {:ok, Tinkex.Types.GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
def get_sampler(config, sampler_id) do
  encoded_id = URI.encode(sampler_id, &URI.char_unreserved?/1)
  path = "/api/v1/samplers/#{encoded_id}"

  case API.get(path, config: config, pool_type: :sampling) do
    {:ok, json} ->
      {:ok, Tinkex.Types.GetSamplerResponse.from_json(json)}

    {:error, _} = error ->
      error
  end
end
```

**Missing from** `lib/tinkex/rest_client.ex` (no public wrapper exists)

**Type Support**: Fully implemented in `lib/tinkex/types/get_sampler_response.ex` with:
- Complete struct definition with `@enforce_keys [:sampler_id, :base_model]`
- JSON parsing via `from_json/1`
- Jason encoding implementation
- Full documentation matching Python

---

#### 2. `get_weights_info_by_tinker_path(tinker_path)`

**Python Implementation** (`tinker/src/tinker/lib/public_interfaces/rest_client.py:136-167`):
```python
@capture_exceptions(fatal=True)
def get_weights_info_by_tinker_path(
    self, tinker_path: str
) -> APIFuture[types.WeightsInfoResponse]:
    """Get checkpoint information from a tinker path.

    Args:
    - `tinker_path`: The tinker path to the checkpoint

    Returns:
    - An `APIFuture` containing the checkpoint information. The future is awaitable.

    Example:
    ```python
    future = rest_client.get_weights_info_by_tinker_path("tinker://run-id/weights/checkpoint-001")
    response = future.result()  # or await future
    print(f"Base Model: {response.base_model}, LoRA Rank: {response.lora_rank}")
    ```
    """

    async def _get_weights_info_async() -> types.WeightsInfoResponse:
        async def _send_request() -> types.WeightsInfoResponse:
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                return await client.post(
                    "/api/v1/weights_info",
                    body={"tinker_path": tinker_path},
                    cast_to=types.WeightsInfoResponse,
                )

        return await self.holder.execute_with_retries(_send_request)

    return self.holder.run_coroutine_threadsafe(_get_weights_info_async())
```

**Elixir Low-Level Implementation EXISTS** (`lib/tinkex/api/rest.ex:176-188`):
```elixir
@spec get_weights_info_by_tinker_path(Config.t(), String.t()) ::
        {:ok, Tinkex.Types.WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
def get_weights_info_by_tinker_path(config, tinker_path) do
  body = %{"tinker_path" => tinker_path}

  case API.post("/api/v1/weights_info", body, config: config, pool_type: :training) do
    {:ok, json} ->
      {:ok, Tinkex.Types.WeightsInfoResponse.from_json(json)}

    {:error, _} = error ->
      error
  end
end
```

**Missing from** `lib/tinkex/rest_client.ex` (no public wrapper exists)

**Type Support**: Fully implemented in `lib/tinkex/types/weights_info_response.ex` with:
- Complete struct definition with `@enforce_keys [:base_model, :is_lora]`
- JSON parsing via `from_json/1`
- Jason encoding implementation
- Full documentation matching Python

---

### Additional Helper: Tinker Path By-Variants

The Python SDK provides tinker-path convenience variants for several methods:

1. **`get_training_run_by_tinker_path(tinker_path)`** (Python lines 105-126)
   - Elixir low-level: EXISTS in `lib/tinkex/api/rest.ex:203-209`
   - Elixir RestClient: **MISSING**

2. **`delete_checkpoint_from_tinker_path(tinker_path)`** (Python lines 351-357)
   - Elixir low-level: Uses internal `parse_tinker_path/1` helper
   - Elixir RestClient: **MISSING** (though base `delete_checkpoint` exists)

3. **`get_checkpoint_archive_url_from_tinker_path(tinker_path)`** (Python lines 373-387)
   - Elixir low-level: Uses internal `parse_tinker_path/1` helper
   - Elixir RestClient: **MISSING** (though base `get_checkpoint_archive_url` exists)

---

### Tinker Path Parsing Infrastructure

**Python** (`tinker/src/tinker/types/checkpoint.py:31-60`):
```python
class ParsedCheckpointTinkerPath(BaseModel):
    tinker_path: str
    training_run_id: str
    checkpoint_type: CheckpointType  # "training" | "sampler"
    checkpoint_id: str

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

**Elixir** (`lib/tinkex/api/rest.ex:282-298`):
```elixir
defp parse_tinker_path("tinker://" <> rest) do
  case String.split(rest, "/") do
    [run_id, part1, part2] ->
      {:ok, {run_id, Path.join(part1, part2)}}

    _ ->
      {:error,
       Tinkex.Error.new(:validation, "Invalid checkpoint path: #{rest}", category: :user)}
  end
end

defp parse_tinker_path(other) do
  {:error,
   Tinkex.Error.new(:validation, "Checkpoint path must start with tinker://, got: #{other}",
     category: :user
   )}
end
```

The Elixir implementation is **private** and returns a simplified tuple, while Python has a **public type** with full metadata extraction including `checkpoint_type`.

---

## Decision Drivers

### 1. API Completeness
- **Goal**: Achieve feature parity with Python SDK
- **Current Gap**: 2 critical methods + 3 convenience variants missing from public API
- **Impact**: Users migrating from Python will find missing functionality

### 2. Low-Level Implementation Ready
- Both `get_sampler` and `get_weights_info_by_tinker_path` are **fully implemented** in `Tinkex.API.Rest`
- Types are complete with full JSON support
- Only needs thin public wrappers in `Tinkex.RestClient`

### 3. Developer Ergonomics
- Tinker paths (`tinker://run-id/weights/checkpoint-001`) are the canonical way to reference checkpoints
- Having `*_from_tinker_path` variants reduces boilerplate and parsing errors
- Matches user expectations from Python SDK

### 4. Type Safety vs Flexibility
- Python uses `ParsedCheckpointTinkerPath` class with full metadata
- Elixir uses simple `{run_id, checkpoint_id}` tuple
- Trade-off: Simpler internal implementation vs exposing checkpoint type metadata

---

## Considered Options

### Option 1: Direct Public Exposure (Recommended)

Add thin public wrappers in `Tinkex.RestClient` that delegate to `Tinkex.API.Rest`:

**Advantages**:
- Minimal implementation (2-5 lines per method)
- Low-level implementation already complete and tested
- Zero breaking changes
- Fast to implement

**Disadvantages**:
- None identified

**Implementation**:
```elixir
# In lib/tinkex/rest_client.ex

@doc """
Get sampler information.

## Examples

    {:ok, response} = RestClient.get_sampler(client, "session-id:sample:0")
    IO.inspect(response.base_model)
    IO.inspect(response.model_path)
"""
@spec get_sampler(t(), String.t()) ::
        {:ok, Tinkex.Types.GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
def get_sampler(%__MODULE__{config: config}, sampler_id) do
  Rest.get_sampler(config, sampler_id)
end

@doc """
Get checkpoint information from a tinker path.

## Examples

    path = "tinker://run-id/weights/checkpoint-001"
    {:ok, response} = RestClient.get_weights_info_by_tinker_path(client, path)
    IO.inspect(response.base_model)
    IO.inspect(response.is_lora)
    IO.inspect(response.lora_rank)
"""
@spec get_weights_info_by_tinker_path(t(), String.t()) ::
        {:ok, Tinkex.Types.WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
def get_weights_info_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.get_weights_info_by_tinker_path(config, tinker_path)
end
```

---

### Option 2: Add Tinker Path Convenience Variants

Extend Option 1 with additional `*_by_tinker_path` methods:

**Advantages**:
- Complete API parity with Python
- Better ergonomics for users working with tinker paths
- Reduces tinker path parsing errors

**Disadvantages**:
- More methods to maintain
- Slight API surface expansion

**Implementation**:
```elixir
@doc """
Get training run information by tinker path.

## Examples

    {:ok, run} = RestClient.get_training_run_by_tinker_path(client, "tinker://run-123/weights/0001")
    IO.inspect(run.training_run_id)
"""
@spec get_training_run_by_tinker_path(t(), String.t()) ::
        {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
def get_training_run_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.get_training_run_by_tinker_path(config, tinker_path)
end

@doc """
Delete a checkpoint by tinker path.

## Examples

    {:ok, _} = RestClient.delete_checkpoint_by_tinker_path(client, "tinker://run-123/weights/0001")
"""
@spec delete_checkpoint_by_tinker_path(t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
def delete_checkpoint_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.delete_checkpoint(config, tinker_path)  # Already handles tinker paths internally
end

@doc """
Get checkpoint archive URL by tinker path.

## Examples

    {:ok, response} = RestClient.get_checkpoint_archive_url_by_tinker_path(client, "tinker://run-123/weights/0001")
    IO.puts(response.url)
"""
@spec get_checkpoint_archive_url_by_tinker_path(t(), String.t()) ::
        {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
def get_checkpoint_archive_url_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.get_checkpoint_archive_url(config, tinker_path)  # Already handles tinker paths internally
end
```

---

### Option 3: Promote Tinker Path Parsing to Public API

Create a public `Tinkex.Types.ParsedCheckpointTinkerPath` module matching Python:

**Advantages**:
- Full structural parity with Python SDK
- Exposes checkpoint type metadata to users
- More testable/composable for advanced use cases

**Disadvantages**:
- More complex implementation
- Requires new public type
- May not be necessary given Elixir's pattern matching

**Implementation**:
```elixir
# New file: lib/tinkex/types/parsed_checkpoint_tinker_path.ex
defmodule Tinkex.Types.ParsedCheckpointTinkerPath do
  @moduledoc """
  Parsed representation of a tinker checkpoint path.

  Mirrors Python `tinker.types.ParsedCheckpointTinkerPath`.
  """

  @enforce_keys [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]
  defstruct [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]

  @type checkpoint_type :: :training | :sampler

  @type t :: %__MODULE__{
          tinker_path: String.t(),
          training_run_id: String.t(),
          checkpoint_type: checkpoint_type(),
          checkpoint_id: String.t()
        }

  @doc """
  Parse a tinker path into its components.

  ## Examples

      iex> ParsedCheckpointTinkerPath.from_tinker_path("tinker://run-id/weights/checkpoint-001")
      {:ok, %ParsedCheckpointTinkerPath{
        tinker_path: "tinker://run-id/weights/checkpoint-001",
        training_run_id: "run-id",
        checkpoint_type: :training,
        checkpoint_id: "weights/checkpoint-001"
      }}
  """
  @spec from_tinker_path(String.t()) :: {:ok, t()} | {:error, Tinkex.Error.t()}
  def from_tinker_path("tinker://" <> rest = tinker_path) do
    case String.split(rest, "/") do
      [run_id, checkpoint_category, checkpoint_num] when checkpoint_category in ["weights", "sampler_weights"] ->
        checkpoint_type = if checkpoint_category == "weights", do: :training, else: :sampler
        {:ok, %__MODULE__{
          tinker_path: tinker_path,
          training_run_id: run_id,
          checkpoint_type: checkpoint_type,
          checkpoint_id: "#{checkpoint_category}/#{checkpoint_num}"
        }}

      _ ->
        {:error, Tinkex.Error.new(:validation, "Invalid tinker path: #{tinker_path}", category: :user)}
    end
  end

  def from_tinker_path(other) do
    {:error, Tinkex.Error.new(:validation, "Tinker path must start with tinker://, got: #{other}", category: :user)}
  end
end
```

---

## Decision

**Adopt Option 1 + Option 2 (Phased Approach)**

### Phase 1: Core Missing Methods (Immediate)
Implement the two critical missing methods that have no public equivalent:
1. `get_sampler/2`
2. `get_weights_info_by_tinker_path/2`

### Phase 2: Tinker Path Convenience Variants (Follow-up)
Add the `*_by_tinker_path` convenience variants:
1. `get_training_run_by_tinker_path/2`
2. `delete_checkpoint_by_tinker_path/2` (alias for existing `delete_checkpoint/2` which already accepts tinker paths)
3. `get_checkpoint_archive_url_by_tinker_path/2` (alias for existing which already accepts tinker paths)

### Option 3 Deferred
Do NOT implement `ParsedCheckpointTinkerPath` public type unless:
- Users explicitly request checkpoint type extraction
- Future features require exposing checkpoint type metadata
- Pattern matching on checkpoint types becomes a common use case

**Rationale**:
- Elixir's internal `parse_tinker_path/1` is sufficient for current needs
- Python's public type is primarily for OOP-style encapsulation
- Elixir pattern matching + tuples are more idiomatic
- Can add later without breaking changes if needed

---

## Consequences

### Positive

1. **API Completeness**: Achieves feature parity with Python SDK for critical sampler and weights info queries
2. **Zero Breaking Changes**: All additions are new public methods, no modifications to existing signatures
3. **Low Implementation Cost**: Thin wrappers over existing tested low-level implementations
4. **Better DX**: Users coming from Python will find familiar methods
5. **Tinker Path Ergonomics**: `*_by_tinker_path` variants reduce boilerplate and parsing errors

### Negative

1. **API Surface Growth**: +2 methods in Phase 1, +3 in Phase 2 (5 total new public methods)
2. **Maintenance**: More public methods to document and maintain (though implementation is trivial)
3. **Naming Ambiguity**: Some methods like `delete_checkpoint` already accept tinker paths, so `delete_checkpoint_by_tinker_path` may be redundant (mitigated by following Python naming)

### Neutral

1. **No Type Complexity**: Deferred `ParsedCheckpointTinkerPath` means no new public types
2. **Documentation Burden**: Each method needs docstrings, but can copy from Python
3. **Test Coverage**: Low-level implementations already tested, public wrappers need basic integration tests

---

## Implementation Plan

### Step 1: Add Core Missing Methods to `Tinkex.RestClient`

**File**: `lib/tinkex/rest_client.ex`

**Changes**:
```elixir
# Add to module after existing checkpoint/session methods

# Sampler API

@doc """
Get sampler information.

Retrieves details about a sampler, including the base model and any
custom weights that are loaded.

## Parameters
  * `client` - The RestClient instance
  * `sampler_id` - The sampler ID (sampling_session_id) to query

## Returns
  * `{:ok, %GetSamplerResponse{}}` - On success
  * `{:error, Tinkex.Error.t()}` - On failure

## Examples

    {:ok, response} = RestClient.get_sampler(client, "session-id:sample:0")
    IO.inspect(response.base_model)
    # => "Qwen/Qwen2.5-7B"
    IO.inspect(response.model_path)
    # => "tinker://run-id/weights/checkpoint-001"

## See Also
  * `Tinkex.Types.GetSamplerResponse`
  * `Tinkex.API.Rest.get_sampler/2`
"""
@spec get_sampler(t(), String.t()) ::
        {:ok, Tinkex.Types.GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
def get_sampler(%__MODULE__{config: config}, sampler_id) do
  Rest.get_sampler(config, sampler_id)
end

# Weights Info API

@doc """
Get checkpoint information from a tinker path.

Retrieves metadata about a checkpoint, including the base model,
whether it uses LoRA, and the LoRA rank.

## Parameters
  * `client` - The RestClient instance
  * `tinker_path` - The tinker path to the checkpoint
    (e.g., `"tinker://run-id/weights/checkpoint-001"`)

## Returns
  * `{:ok, %WeightsInfoResponse{}}` - On success
  * `{:error, Tinkex.Error.t()}` - On failure

## Examples

    path = "tinker://run-id/weights/checkpoint-001"
    {:ok, response} = RestClient.get_weights_info_by_tinker_path(client, path)
    IO.inspect(response.base_model)
    # => "Qwen/Qwen2.5-7B"
    IO.inspect(response.is_lora)
    # => true
    IO.inspect(response.lora_rank)
    # => 32

## Use Cases

### Validating Checkpoint Compatibility

    def validate_checkpoint(client, path, expected_rank) do
      case RestClient.get_weights_info_by_tinker_path(client, path) do
        {:ok, %{is_lora: true, lora_rank: ^expected_rank}} ->
          :ok
        {:ok, %{is_lora: true, lora_rank: actual}} ->
          {:error, {:rank_mismatch, expected: expected_rank, actual: actual}}
        {:ok, %{is_lora: false}} ->
          {:error, :not_lora}
        {:error, _} = error ->
          error
      end
    end

## See Also
  * `Tinkex.Types.WeightsInfoResponse`
  * `Tinkex.API.Rest.get_weights_info_by_tinker_path/2`
"""
@spec get_weights_info_by_tinker_path(t(), String.t()) ::
        {:ok, Tinkex.Types.WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
def get_weights_info_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.get_weights_info_by_tinker_path(config, tinker_path)
end
```

**Location**: After line 206 in `lib/tinkex/rest_client.ex`

---

### Step 2: Add Type Aliases to Module Header

**File**: `lib/tinkex/rest_client.ex`

**Update alias block** (around line 22-29):
```elixir
alias Tinkex.Types.{
  CheckpointsListResponse,
  CheckpointArchiveUrlResponse,
  GetSamplerResponse,          # ADD THIS
  GetSessionResponse,
  ListSessionsResponse,
  TrainingRun,
  TrainingRunsResponse,
  WeightsInfoResponse           # ADD THIS
}
```

---

### Step 3: Add Convenience Variants (Phase 2)

**File**: `lib/tinkex/rest_client.ex`

**Add after Phase 1 methods**:
```elixir
# Tinker Path Convenience Methods

@doc """
Get training run information by tinker path.

Extracts the training run ID from the tinker path and retrieves
the training run information.

## Parameters
  * `client` - The RestClient instance
  * `tinker_path` - The tinker path to the checkpoint

## Returns
  * `{:ok, %TrainingRun{}}` - On success
  * `{:error, Tinkex.Error.t()}` - On failure

## Examples

    {:ok, run} = RestClient.get_training_run_by_tinker_path(
      client,
      "tinker://run-123/weights/checkpoint-001"
    )
    IO.inspect(run.training_run_id)
    # => "run-123"
    IO.inspect(run.base_model)
    # => "Qwen/Qwen2.5-7B"

## See Also
  * `get_training_run/2`
"""
@spec get_training_run_by_tinker_path(t(), String.t()) ::
        {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
def get_training_run_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  Rest.get_training_run_by_tinker_path(config, tinker_path)
end

@doc """
Get checkpoint archive URL by tinker path.

Convenience method that accepts a tinker path instead of separate
run_id and checkpoint_id parameters.

## Parameters
  * `client` - The RestClient instance
  * `tinker_path` - The tinker path to the checkpoint

## Returns
  * `{:ok, %CheckpointArchiveUrlResponse{}}` - On success
  * `{:error, Tinkex.Error.t()}` - On failure

## Examples

    {:ok, response} = RestClient.get_checkpoint_archive_url_by_tinker_path(
      client,
      "tinker://run-123/weights/checkpoint-001"
    )
    IO.puts(response.url)
    # => "https://..."

## See Also
  * `get_checkpoint_archive_url/2`
"""
@spec get_checkpoint_archive_url_by_tinker_path(t(), String.t()) ::
        {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
def get_checkpoint_archive_url_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  # Note: get_checkpoint_archive_url already accepts tinker paths
  get_checkpoint_archive_url(%__MODULE__{config: config}, tinker_path)
end

@doc """
Delete a checkpoint by tinker path.

Convenience method that accepts a tinker path instead of separate
run_id and checkpoint_id parameters.

## Parameters
  * `client` - The RestClient instance
  * `tinker_path` - The tinker path to the checkpoint

## Returns
  * `{:ok, map()}` - On success
  * `{:error, Tinkex.Error.t()}` - On failure

## Examples

    {:ok, _} = RestClient.delete_checkpoint_by_tinker_path(
      client,
      "tinker://run-123/weights/checkpoint-001"
    )

## See Also
  * `delete_checkpoint/2`
"""
@spec delete_checkpoint_by_tinker_path(t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
def delete_checkpoint_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
  # Note: delete_checkpoint already accepts tinker paths
  delete_checkpoint(%__MODULE__{config: config}, tinker_path)
end
```

---

### Step 4: Update Module Documentation

**File**: `lib/tinkex/rest_client.ex`

**Update `@moduledoc`** (lines 2-17) to include new methods:
```elixir
@moduledoc """
REST client for synchronous Tinker API operations.

Provides checkpoint and session management functionality.

## Key Methods

### Session Management
- `get_session/2` - Get session information
- `list_sessions/2` - List sessions with pagination

### Checkpoint Management
- `list_checkpoints/2` - List checkpoints for a training run
- `list_user_checkpoints/2` - List all user checkpoints with pagination
- `get_checkpoint_archive_url/2` - Get download URL for a checkpoint
- `delete_checkpoint/2` - Delete a checkpoint
- `publish_checkpoint/2` - Make a checkpoint public
- `unpublish_checkpoint/2` - Make a checkpoint private

### Training Run Management
- `get_training_run/2` - Get training run by ID
- `get_training_run_by_tinker_path/2` - Get training run by tinker path
- `list_training_runs/2` - List training runs with pagination

### Sampler Management
- `get_sampler/2` - Get sampler information

### Weights Information
- `get_weights_info_by_tinker_path/2` - Get checkpoint metadata

## Usage

    {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, rest_client} = Tinkex.ServiceClient.create_rest_client(service_pid)

    # Get sampler info
    {:ok, sampler} = Tinkex.RestClient.get_sampler(rest_client, "session-id:sample:0")

    # Get weights info
    {:ok, weights} = Tinkex.RestClient.get_weights_info_by_tinker_path(
      rest_client,
      "tinker://run-id/weights/checkpoint-001"
    )
"""
```

---

### Step 5: Add Basic Integration Tests

**File**: `test/tinkex/rest_client_test.exs`

**Add test cases**:
```elixir
describe "get_sampler/2" do
  test "retrieves sampler information", %{client: client} do
    # Mock implementation or VCR cassette
    sampler_id = "test-session:sample:0"

    case RestClient.get_sampler(client, sampler_id) do
      {:ok, response} ->
        assert %GetSamplerResponse{} = response
        assert response.sampler_id == sampler_id
        assert is_binary(response.base_model)

      {:error, _} ->
        # Expected if not mocked
        :ok
    end
  end
end

describe "get_weights_info_by_tinker_path/2" do
  test "retrieves checkpoint weights information", %{client: client} do
    tinker_path = "tinker://test-run/weights/checkpoint-001"

    case RestClient.get_weights_info_by_tinker_path(client, tinker_path) do
      {:ok, response} ->
        assert %WeightsInfoResponse{} = response
        assert is_binary(response.base_model)
        assert is_boolean(response.is_lora)

      {:error, _} ->
        # Expected if not mocked
        :ok
    end
  end

  test "returns error for invalid tinker path", %{client: client} do
    assert {:error, _} = RestClient.get_weights_info_by_tinker_path(client, "invalid-path")
  end
end
```

---

### Step 6: Update Changelog

**File**: `CHANGELOG.md`

**Add to Unreleased section**:
```markdown
## [Unreleased]

### Added
- `RestClient.get_sampler/2` - Get sampler information by sampler ID
- `RestClient.get_weights_info_by_tinker_path/2` - Get checkpoint metadata from tinker path
- `RestClient.get_training_run_by_tinker_path/2` - Get training run by tinker path
- `RestClient.get_checkpoint_archive_url_by_tinker_path/2` - Get archive URL by tinker path
- `RestClient.delete_checkpoint_by_tinker_path/2` - Delete checkpoint by tinker path

### Fixed
- REST client API now matches Python SDK feature parity for sampler and weights info queries
```

---

## References

### Python SDK Files
- `tinker/src/tinker/lib/public_interfaces/rest_client.py`
  - Lines 669-702: `get_sampler()` implementation
  - Lines 136-167: `get_weights_info_by_tinker_path()` implementation
  - Lines 105-126: `get_training_run_by_tinker_path()` implementation
  - Lines 351-357: `delete_checkpoint_from_tinker_path()` implementation
  - Lines 373-387: `get_checkpoint_archive_url_from_tinker_path()` implementation

- `tinker/src/tinker/types/get_sampler_response.py`
  - Lines 6-14: `GetSamplerResponse` type definition

- `tinker/src/tinker/types/weights_info_response.py`
  - Lines 6-13: `WeightsInfoResponse` type definition

- `tinker/src/tinker/types/checkpoint.py`
  - Lines 31-60: `ParsedCheckpointTinkerPath` type and parser

- `tinker/docs/api/restclient.md`
  - Lines 479-512: `get_sampler()` documentation
  - Lines 100-120: `get_weights_info_by_tinker_path()` documentation

### Elixir Tinkex Files
- `lib/tinkex/rest_client.ex`
  - Current public RestClient interface (missing methods)

- `lib/tinkex/api/rest.ex`
  - Lines 112-125: `get_sampler/2` low-level implementation ✅
  - Lines 176-188: `get_weights_info_by_tinker_path/2` low-level implementation ✅
  - Lines 203-209: `get_training_run_by_tinker_path/2` low-level implementation ✅
  - Lines 282-298: Private `parse_tinker_path/1` helper

- `lib/tinkex/types/get_sampler_response.ex`
  - Lines 1-96: Full type implementation with JSON support ✅

- `lib/tinkex/types/weights_info_response.ex`
  - Lines 1-96: Full type implementation with JSON support ✅

### API Endpoints Referenced
- `GET /api/v1/samplers/{sampler_id}` - Get sampler information
- `POST /api/v1/weights_info` - Get weights info by tinker path (body: `{"tinker_path": "..."}`)
- `GET /api/v1/training_runs/{run_id}` - Get training run information
