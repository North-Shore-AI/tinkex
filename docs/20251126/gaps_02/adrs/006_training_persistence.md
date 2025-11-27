# ADR-006: Training Persistence and Checkpoint Management

## Status
Proposed

## Context

### Current State Analysis

The Python Tinker SDK provides a comprehensive checkpoint persistence API for saving and loading model weights with optimizer state, enabling training resumption and model versioning. The Elixir Tinkex port has the underlying types and API infrastructure in place but lacks public-facing functions to expose this functionality.

### Python SDK Implementation

The Python SDK (`tinker/src/tinker/lib/public_interfaces/training_client.py`) exposes the following persistence methods:

#### 1. **save_state** (lines 479-528)
```python
def save_state(self, name: str) -> APIFuture[types.SaveWeightsResponse]:
    """Save model weights to persistent storage.

    Args:
    - `name`: Name for the saved checkpoint

    Returns:
    - `APIFuture` containing the save response with checkpoint path
    """
```

**Implementation details:**
- Creates `SaveWeightsRequest` with `model_id`, `path=name`, and `seq_id`
- Posts to `/api/v1/save_weights` endpoint via `client.weights.save()`
- Returns `APIFuture[SaveWeightsResponse]` containing the Tinker URI path
- Uses sequential request ordering via `_get_request_id()` and `_take_turn()`
- Tracks request as "SaveWeights" type for telemetry

#### 2. **load_state** (lines 560-582)
```python
def load_state(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights from a saved checkpoint.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

    Returns:
    - `APIFuture` containing the load response
    """
```

**Implementation details:**
- Calls internal `_load_state_impl(request_id, path, optimizer=False)`
- Creates `LoadWeightsRequest` with `optimizer=False` field
- Posts to `/api/v1/load_weights` endpoint
- Does NOT restore optimizer state (Adam moments, etc.)

#### 3. **load_state_with_optimizer** (lines 585-611)
```python
def load_state_with_optimizer(self, path: str) -> APIFuture[types.LoadWeightsResponse]:
    """Load model weights and optimizer state from a checkpoint.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

    Returns:
    - `APIFuture` containing the load response
    """
```

**Implementation details:**
- Calls internal `_load_state_impl(request_id, path, optimizer=True)`
- Creates `LoadWeightsRequest` with `optimizer=True` field
- Restores optimizer state (momentum, variance estimates) along with weights
- Critical for resuming training without losing convergence properties

#### 4. **ServiceClient.create_training_client_from_state** (lines 222-254)
```python
def create_training_client_from_state(
    self, path: str, user_metadata: dict[str, str] | None = None
) -> TrainingClient:
    """Create a TrainingClient from saved model weights.

    Args:
    - `path`: Tinker path to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
    - `user_metadata`: Optional metadata to attach to the new training run

    Returns:
    - `TrainingClient` loaded with the specified weights
    """
```

**Implementation details:**
- Uses `rest_client.get_weights_info_by_tinker_path(path)` to fetch checkpoint metadata
- Extracts `base_model` and `lora_rank` from weights info
- Creates new TrainingClient with matching LoRA configuration
- Calls `training_client.load_state(path)` to restore weights (without optimizer)
- Enables checkpoint-based workflow bootstrapping

### Wire Protocol

**Python types** (`tinker/src/tinker/types/`):

**SaveWeightsRequest:**
```python
class SaveWeightsRequest(StrictBase):
    model_id: ModelID
    path: Optional[str] = None      # Checkpoint name
    seq_id: Optional[int] = None
    type: Literal["save_weights"] = "save_weights"
```

**LoadWeightsRequest:**
```python
class LoadWeightsRequest(StrictBase):
    model_id: ModelID
    path: str                        # Tinker URI
    optimizer: bool                  # Load optimizer state?
    seq_id: Optional[int] = None
    type: Literal["load_weights"] = "load_weights"
```

**Key difference:** The Python `LoadWeightsRequest` uses `optimizer: bool` field, while Elixir uses `load_optimizer_state: boolean()`.

### Elixir Tinkex Implementation

The Elixir port has complete infrastructure but no public API:

#### Types (Complete)
- `Tinkex.Types.SaveWeightsRequest` - Mirrors Python type ✓
- `Tinkex.Types.SaveWeightsResponse` - Mirrors Python type ✓
- `Tinkex.Types.LoadWeightsRequest` - **Field mismatch**: uses `load_optimizer_state` instead of `optimizer` ⚠️
- `Tinkex.Types.LoadWeightsResponse` - Mirrors Python type ✓

#### API Layer (Complete)
- `Tinkex.API.Weights.save_weights/2` - Posts to `/api/v1/save_weights` ✓
- `Tinkex.API.Weights.load_weights/2` - Posts to `/api/v1/load_weights` ✓
- Both have typed variants (`_typed/2`) ✓

#### TrainingClient (Missing Public APIs)
- **save_weights_for_sampler/2** - Public, but only for sampling workflow ✓
- **No save_state** - Gap ✗
- **No load_state** - Gap ✗
- **No load_state_with_optimizer** - Gap ✗

#### ServiceClient (Missing)
- **No create_training_client_from_state** - Gap ✗

### Gap Summary

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| save_state | ✓ | ✗ | **Missing** |
| load_state | ✓ | ✗ | **Missing** |
| load_state_with_optimizer | ✓ | ✗ | **Missing** |
| create_training_client_from_state | ✓ | ✗ | **Missing** |
| Wire protocol types | ✓ | ⚠️ | **Field name mismatch** |
| HTTP API layer | ✓ | ✓ | **Complete** |
| save_weights_for_sampler | ✓ | ✓ | **Complete** |

### Impact Analysis

**User workflows blocked:**
1. **Checkpoint-based training resumption** - Cannot save/load checkpoints during training
2. **Training state recovery** - No way to resume with optimizer state after interruption
3. **Model versioning** - Cannot save named checkpoints for comparison
4. **Transfer learning from checkpoints** - Cannot bootstrap new training from existing checkpoints
5. **Distributed training coordination** - Cannot coordinate checkpoints across workers

**Current workarounds:**
- Users must use `save_weights_for_sampler` (intended for inference only)
- No optimizer state persistence available
- No ServiceClient-level checkpoint bootstrapping

## Decision Drivers

1. **API Parity** - Elixir SDK should match Python SDK capabilities
2. **Training Continuity** - Optimizer state persistence is critical for training resumption
3. **Wire Protocol Compatibility** - Must match Python SDK wire format exactly
4. **Elixir Idioms** - Async Task-based API should follow existing patterns
5. **Sequential Ordering** - Weight operations must respect request sequencing
6. **Type Safety** - Strong typing for all request/response structures
7. **Telemetry** - Consistent instrumentation with other training operations

## Considered Options

### Option 1: Direct Port (Recommended)
Port Python implementation directly to Elixir, maintaining exact API semantics.

**Pros:**
- Full feature parity with Python SDK
- Familiar API for users migrating from Python
- Proven design patterns
- Complete telemetry coverage

**Cons:**
- Requires fixing `LoadWeightsRequest` field name mismatch
- Need to add RestClient integration for `create_training_client_from_state`

### Option 2: Elixir-Idiomatic Redesign
Create a more Elixir-native API (e.g., `TrainingClient.save_checkpoint/3`, `ServiceClient.from_checkpoint/2`).

**Pros:**
- More Elixir-like naming conventions
- Potential for better GenServer integration

**Cons:**
- Breaks API parity with Python
- Confusion for users familiar with Python SDK
- Documentation divergence
- No clear advantage over direct port

### Option 3: Minimal Implementation (Defer Optimizer State)
Implement only `save_state` and `load_state`, defer `load_state_with_optimizer`.

**Pros:**
- Faster initial implementation
- Simpler testing surface

**Cons:**
- Training resumption remains broken (optimizer state critical)
- Incomplete feature parity
- Users blocked on key workflows
- Would require follow-up work anyway

## Decision

**Choose Option 1: Direct Port**

Implement the complete Python API surface in Elixir:
1. `TrainingClient.save_state/2` - Save checkpoint with name
2. `TrainingClient.load_state/2` - Load checkpoint without optimizer state
3. `TrainingClient.load_state_with_optimizer/2` - Load checkpoint with optimizer state
4. `ServiceClient.create_training_client_from_state/3` - Bootstrap training from checkpoint

**Rationale:**
- Complete feature parity critical for production use
- Optimizer state persistence non-negotiable for training resumption
- Proven Python implementation provides clear specification
- Existing Elixir infrastructure (types, API layer) already in place
- Only missing piece is public API wrappers

## Consequences

### Positive
1. **Feature Parity** - Elixir SDK matches Python capabilities
2. **Training Resumption** - Users can resume training with full optimizer state
3. **Checkpoint Workflows** - Named checkpoints enable versioning and comparison
4. **Bootstrap Workflows** - Transfer learning from existing checkpoints enabled
5. **Production Ready** - Critical missing functionality filled
6. **Consistent API** - Users familiar with Python SDK have same API in Elixir

### Negative
1. **Breaking Change** - Must fix `LoadWeightsRequest.load_optimizer_state` → `optimizer` field name
2. **RestClient Dependency** - `create_training_client_from_state` requires RestClient integration
3. **Testing Surface** - Additional test cases for checkpoint workflows
4. **Documentation** - Need to document checkpoint patterns and best practices

### Risks & Mitigations

**Risk 1: Wire Protocol Compatibility**
- Python uses `optimizer: bool`, Elixir has `load_optimizer_state: boolean()`
- **Mitigation:** Update Elixir `LoadWeightsRequest` to use `optimizer` field name, add deprecation path if needed

**Risk 2: Sequential Ordering Violations**
- Weight operations must respect sequential request ordering
- **Mitigation:** Follow existing `optim_step` pattern with `request_id_counter` and async Task replies

**Risk 3: Future API Changes**
- Asynchronous polling required for `save_state` (returns future)
- **Mitigation:** Match existing `save_weights_for_sampler` implementation pattern

## Implementation Plan

### Phase 1: Fix Wire Protocol Compatibility (Breaking Change)

**File:** `lib/tinkex/types/load_weights_request.ex`

```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  ## Fields
  - `model_id` - The model/training run ID
  - `path` - Tinker URI for model weights
  - `seq_id` - Sequence ID for request ordering
  - `optimizer` - Whether to also load optimizer state (default: false)
  - `type` - Request type, always "load_weights"
  """

  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :optimizer, :type]}
  defstruct [:model_id, :path, :seq_id, optimizer: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          optimizer: boolean(),  # Changed from load_optimizer_state
          type: String.t()
        }

  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(model_id, path, opts \\ []) do
    %__MODULE__{
      model_id: model_id,
      path: path,
      seq_id: Keyword.get(opts, :seq_id),
      optimizer: Keyword.get(opts, :optimizer, false),  # Changed
      type: "load_weights"
    }
  end
end
```

**Breaking change note:** Existing code using `load_optimizer_state:` will break. Migration path:
```elixir
# Old (breaks):
LoadWeightsRequest.new(model_id, path, load_optimizer_state: true)

# New:
LoadWeightsRequest.new(model_id, path, optimizer: true)
```

### Phase 2: Implement TrainingClient.save_state/2

**File:** `lib/tinkex/training_client.ex`

Add after `save_weights_for_sampler/2` (around line 123):

```elixir
@doc """
Save model weights to persistent storage.

Returns a `Task.t()` that yields `{:ok, %SaveWeightsResponse{}}` or
`{:error, %Tinkex.Error{}}`.

## Parameters
- `client` - TrainingClient pid
- `name` - Name for the saved checkpoint

## Returns
Task that resolves to:
- `{:ok, %SaveWeightsResponse{path: "tinker://..."}}` - Checkpoint saved successfully
- `{:error, Error.t()}` - Save operation failed

## Examples

    # Save checkpoint
    {:ok, task} = TrainingClient.save_state(client, "checkpoint-001")
    {:ok, response} = Task.await(task)
    IO.puts("Saved to: \#{response.path}")
    # => "Saved to: tinker://run-abc123/weights/checkpoint-001"
"""
@spec save_state(t(), String.t()) :: {:ok, Task.t()} | {:error, Error.t()}
def save_state(client, name) when is_binary(name) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:save_state, name}, :infinity)
   end)}
end
```

Add GenServer handler:

```elixir
@impl true
def handle_call({:save_state, name}, from, state) do
  seq_id = state.request_id_counter
  new_counter = seq_id + 1

  case send_save_weights_request(name, seq_id, state) do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, future} ->
      Task.start(fn ->
        reply =
          try do
            task = state.future_module.poll(
              future,
              poll_opts_with_type(state, [], "SaveWeights")
            )
            unlink_task(task)

            case safe_await(state.future_module, task, :infinity) do
              {:ok, result} ->
                {:ok, SaveWeightsResponse.from_json(result)}
              {:error, %Error{} = error} ->
                {:error, error}
            end
          rescue
            e ->
              {:error,
               %Error{
                 message: "Save state failed: #{Exception.message(e)}",
                 type: :request_failed,
                 data: %{exception: e, stacktrace: __STACKTRACE__}
               }}
          end

        try do
          GenServer.reply(from, reply)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:noreply, %{state | request_id_counter: new_counter}}
  end
end
```

Add helper function:

```elixir
defp send_save_weights_request(name, seq_id, state) do
  request = %SaveWeightsRequest{
    model_id: state.model_id,
    path: name,
    seq_id: seq_id
  }

  case state.weights_api.save_weights(request,
         config: state.config,
         telemetry_metadata:
           base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
       ) do
    {:ok, %{"request_id" => _} = future} -> {:ok, future}
    {:ok, %{request_id: _} = future} -> {:ok, future}
    {:ok, result} -> {:ok, result}
    {:error, %Error{} = error} -> {:error, error}
    other -> {:error, Error.new(:validation, "Invalid save_weights response: #{inspect(other)}")}
  end
end
```

Add import for `SaveWeightsResponse`:

```elixir
alias Tinkex.Types.{
  # ... existing imports ...
  SaveWeightsResponse  # Add this
}
```

### Phase 3: Implement TrainingClient.load_state/2

**File:** `lib/tinkex/training_client.ex`

```elixir
@doc """
Load model weights from a saved checkpoint.

Does NOT restore optimizer state. For training resumption with optimizer state,
use `load_state_with_optimizer/2` instead.

Returns a `Task.t()` that yields `{:ok, %LoadWeightsResponse{}}` or
`{:error, %Tinkex.Error{}}`.

## Parameters
- `client` - TrainingClient pid
- `path` - Tinker URI to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

## Returns
Task that resolves to:
- `{:ok, %LoadWeightsResponse{}}` - Weights loaded successfully
- `{:error, Error.t()}` - Load operation failed

## Examples

    # Load checkpoint to continue training (without optimizer state)
    {:ok, task} = TrainingClient.load_state(client, "tinker://run-abc123/weights/checkpoint-001")
    {:ok, _response} = Task.await(task)

    # Continue training from loaded state
    {:ok, fwdbwd_task} = TrainingClient.forward_backward(client, data, :cross_entropy)
"""
@spec load_state(t(), String.t()) :: {:ok, Task.t()} | {:error, Error.t()}
def load_state(client, path) when is_binary(path) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:load_state, path, false}, :infinity)
   end)}
end
```

### Phase 4: Implement TrainingClient.load_state_with_optimizer/2

```elixir
@doc """
Load model weights and optimizer state from a checkpoint.

Restores both model weights and optimizer state (Adam momentum, variance estimates).
Critical for resuming training without losing convergence properties.

Returns a `Task.t()` that yields `{:ok, %LoadWeightsResponse{}}` or
`{:error, %Tinkex.Error{}}`.

## Parameters
- `client` - TrainingClient pid
- `path` - Tinker URI to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")

## Returns
Task that resolves to:
- `{:ok, %LoadWeightsResponse{}}` - Weights and optimizer state loaded
- `{:error, Error.t()}` - Load operation failed

## Examples

    # Resume training with optimizer state
    {:ok, task} = TrainingClient.load_state_with_optimizer(
      client,
      "tinker://run-abc123/weights/checkpoint-001"
    )
    {:ok, _response} = Task.await(task)

    # Continue training with restored optimizer momentum
    {:ok, fwdbwd_task} = TrainingClient.forward_backward(client, data, :cross_entropy)
"""
@spec load_state_with_optimizer(t(), String.t()) :: {:ok, Task.t()} | {:error, Error.t()}
def load_state_with_optimizer(client, path) when is_binary(path) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:load_state, path, true}, :infinity)
   end)}
end
```

Add shared GenServer handler:

```elixir
@impl true
def handle_call({:load_state, path, optimizer}, from, state) do
  seq_id = state.request_id_counter
  new_counter = seq_id + 1

  case send_load_weights_request(path, optimizer, seq_id, state) do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, future} ->
      Task.start(fn ->
        reply =
          try do
            task = state.future_module.poll(
              future,
              poll_opts_with_type(state, [], "LoadWeights")
            )
            unlink_task(task)

            case safe_await(state.future_module, task, :infinity) do
              {:ok, result} ->
                {:ok, LoadWeightsResponse.from_json(result)}
              {:error, %Error{} = error} ->
                {:error, error}
            end
          rescue
            e ->
              {:error,
               %Error{
                 message: "Load state failed: #{Exception.message(e)}",
                 type: :request_failed,
                 data: %{exception: e, stacktrace: __STACKTRACE__}
               }}
          end

        try do
          GenServer.reply(from, reply)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:noreply, %{state | request_id_counter: new_counter}}
  end
end
```

Add helper function:

```elixir
defp send_load_weights_request(path, optimizer, seq_id, state) do
  request = %LoadWeightsRequest{
    model_id: state.model_id,
    path: path,
    seq_id: seq_id,
    optimizer: optimizer  # Changed from load_optimizer_state
  }

  case state.weights_api.load_weights(request,
         config: state.config,
         telemetry_metadata:
           base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
       ) do
    {:ok, %{"request_id" => _} = future} -> {:ok, future}
    {:ok, %{request_id: _} = future} -> {:ok, future}
    {:ok, result} -> {:ok, result}
    {:error, %Error{} = error} -> {:error, error}
    other -> {:error, Error.new(:validation, "Invalid load_weights response: #{inspect(other)}")}
  end
end
```

Add import:

```elixir
alias Tinkex.Types.{
  # ... existing imports ...
  LoadWeightsRequest,
  LoadWeightsResponse,
  SaveWeightsRequest,
  SaveWeightsResponse
}
```

### Phase 5: Implement ServiceClient.create_training_client_from_state/3

**File:** `lib/tinkex/service_client.ex`

```elixir
@doc """
Create a training client from saved model weights.

Fetches checkpoint metadata, creates a new TrainingClient with matching configuration,
and loads the saved weights. Does NOT restore optimizer state.

## Parameters
- `service_client` - ServiceClient pid
- `path` - Tinker URI to saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
- `opts` - Optional keyword list:
  - `:user_metadata` - Metadata to attach to the new training run

## Returns
- `{:ok, pid}` - New TrainingClient with loaded weights
- `{:error, term()}` - Creation failed

## Examples

    # Resume training from checkpoint
    {:ok, training_client} = ServiceClient.create_training_client_from_state(
      service_pid,
      "tinker://run-abc123/weights/checkpoint-001"
    )

    # Continue training from loaded state
    {:ok, fwdbwd_task} = TrainingClient.forward_backward(training_client, data, :cross_entropy)
"""
@spec create_training_client_from_state(t(), String.t(), keyword()) ::
        {:ok, pid()} | {:error, term()}
def create_training_client_from_state(service_client, path, opts \\ [])
    when is_binary(path) do
  GenServer.call(service_client, {:create_training_client_from_state, path, opts}, :infinity)
end
```

Add GenServer handler:

```elixir
@impl true
def handle_call({:create_training_client_from_state, path, opts}, _from, state) do
  with {:ok, rest_client} <- create_rest_client_internal(state),
       {:ok, task} <- Tinkex.RestClient.get_weights_info_by_tinker_path(rest_client, path),
       {:ok, weights_info} <- Task.await(task),
       {:ok, training_client} <- create_training_client_with_config(state, weights_info, opts),
       {:ok, load_task} <- Tinkex.TrainingClient.load_state(training_client, path),
       {:ok, _load_response} <- Task.await(load_task, :infinity) do
    {:reply, {:ok, training_client}, state}
  else
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end
```

Add helper functions:

```elixir
defp create_rest_client_internal(state) do
  {:ok, Tinkex.RestClient.new(state.session_id, state.config)}
end

defp create_training_client_with_config(state, weights_info, opts) do
  model_seq_id = state.training_client_counter

  # Extract LoRA config from weights info
  lora_config = %Tinkex.Types.LoraConfig{
    rank: weights_info.lora_rank
    # Add other LoRA fields as needed from weights_info
  }

  child_opts =
    opts
    |> Keyword.put(:session_id, state.session_id)
    |> Keyword.put(:config, state.config)
    |> Keyword.put(:model_seq_id, model_seq_id)
    |> Keyword.put(:base_model, weights_info.base_model)
    |> Keyword.put(:lora_config, lora_config)
    |> Keyword.put(:client_supervisor, state.client_supervisor)
    |> Keyword.put(:telemetry, state.telemetry)
    |> Keyword.put(:telemetry_metadata, state.telemetry_metadata)

  case DynamicSupervisor.start_child(
         state.client_supervisor,
         {state.training_client_module, child_opts}
       ) do
    {:ok, pid} ->
      # Update counter in parent process
      send(self(), {:increment_training_counter})
      {:ok, pid}

    {:error, _} = error ->
      error
  end
end

@impl true
def handle_info({:increment_training_counter}, state) do
  {:noreply, %{state | training_client_counter: state.training_client_counter + 1}}
end
```

**Note:** This requires `Tinkex.RestClient.get_weights_info_by_tinker_path/2` to exist. If not implemented, this is a dependency that needs to be added.

### Phase 6: Testing

**File:** `test/tinkex/training_client_test.exs`

```elixir
describe "save_state/2" do
  test "saves model weights with checkpoint name" do
    {:ok, client} = start_training_client()

    {:ok, task} = TrainingClient.save_state(client, "checkpoint-001")
    assert {:ok, %SaveWeightsResponse{path: path}} = Task.await(task)
    assert path =~ "tinker://"
    assert path =~ "checkpoint-001"
  end

  test "returns error for invalid checkpoint name" do
    {:ok, client} = start_training_client()

    assert_raise FunctionClauseError, fn ->
      TrainingClient.save_state(client, nil)
    end
  end
end

describe "load_state/2" do
  test "loads model weights without optimizer state" do
    {:ok, client} = start_training_client()
    path = "tinker://run-123/weights/checkpoint-001"

    {:ok, task} = TrainingClient.load_state(client, path)
    assert {:ok, %LoadWeightsResponse{}} = Task.await(task)
  end
end

describe "load_state_with_optimizer/2" do
  test "loads model weights with optimizer state" do
    {:ok, client} = start_training_client()
    path = "tinker://run-123/weights/checkpoint-001"

    {:ok, task} = TrainingClient.load_state_with_optimizer(client, path)
    assert {:ok, %LoadWeightsResponse{}} = Task.await(task)
  end
end

describe "checkpoint workflow" do
  test "save and load checkpoint preserves weights" do
    {:ok, client} = start_training_client()

    # Train for a few steps
    {:ok, fwdbwd_task} = TrainingClient.forward_backward(client, data, :cross_entropy)
    {:ok, _} = Task.await(fwdbwd_task)

    # Save checkpoint
    {:ok, save_task} = TrainingClient.save_state(client, "test-checkpoint")
    {:ok, %{path: checkpoint_path}} = Task.await(save_task)

    # Train more
    {:ok, fwdbwd_task2} = TrainingClient.forward_backward(client, data, :cross_entropy)
    {:ok, _} = Task.await(fwdbwd_task2)

    # Load checkpoint (should revert to earlier state)
    {:ok, load_task} = TrainingClient.load_state(client, checkpoint_path)
    {:ok, _} = Task.await(load_task)
  end
end
```

**File:** `test/tinkex/service_client_test.exs`

```elixir
describe "create_training_client_from_state/3" do
  test "creates training client from checkpoint" do
    {:ok, service} = start_service_client()
    path = "tinker://run-123/weights/checkpoint-001"

    {:ok, client} = ServiceClient.create_training_client_from_state(service, path)
    assert is_pid(client)
    assert Process.alive?(client)
  end

  test "loads weights automatically" do
    {:ok, service} = start_service_client()
    path = "tinker://run-123/weights/checkpoint-001"

    {:ok, client} = ServiceClient.create_training_client_from_state(service, path)

    # Client should be ready for training immediately
    {:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
    assert {:ok, _} = Task.await(task)
  end
end
```

### Phase 7: Documentation

**File:** `docs/guides/checkpointing.md` (new)

```markdown
# Checkpoint Management

This guide covers saving and loading model checkpoints during training.

## Saving Checkpoints

Use `TrainingClient.save_state/2` to save model weights:

\```elixir
{:ok, task} = TrainingClient.save_state(client, "checkpoint-001")
{:ok, response} = Task.await(task)
IO.puts("Saved to: \#{response.path}")
# => "Saved to: tinker://run-abc123/weights/checkpoint-001"
\```

## Loading Checkpoints

### Without Optimizer State

Use `load_state/2` for transfer learning or inference:

\```elixir
{:ok, task} = TrainingClient.load_state(client, "tinker://run-123/weights/checkpoint-001")
{:ok, _} = Task.await(task)
\```

### With Optimizer State

Use `load_state_with_optimizer/2` to resume training:

\```elixir
{:ok, task} = TrainingClient.load_state_with_optimizer(
  client,
  "tinker://run-123/weights/checkpoint-001"
)
{:ok, _} = Task.await(task)
\```

This restores Adam momentum and variance estimates, maintaining convergence properties.

## Bootstrap from Checkpoint

Create a new training client from an existing checkpoint:

\```elixir
{:ok, client} = ServiceClient.create_training_client_from_state(
  service,
  "tinker://run-123/weights/checkpoint-001"
)
\```

This automatically:
1. Fetches checkpoint metadata
2. Creates TrainingClient with matching LoRA config
3. Loads weights (without optimizer state)

## Best Practices

1. **Regular checkpointing**: Save every N steps or M minutes
2. **Named checkpoints**: Use descriptive names (e.g., "epoch-5-loss-1.23")
3. **Optimizer state**: Always use `load_state_with_optimizer/2` when resuming training
4. **Checkpoint cleanup**: Delete old checkpoints to manage storage
\```

**File:** `README.md` (update)

Add to "Features" section:
```markdown
- **Checkpoint Management** - Save/load training checkpoints with optimizer state
  - `TrainingClient.save_state/2` - Save named checkpoints
  - `TrainingClient.load_state/2` - Load weights without optimizer
  - `TrainingClient.load_state_with_optimizer/2` - Resume training with optimizer state
  - `ServiceClient.create_training_client_from_state/3` - Bootstrap from checkpoint
```

## References

### Python Source Files
- `tinker/src/tinker/lib/public_interfaces/training_client.py` (lines 479-611)
  - `save_state()` implementation (lines 479-528)
  - `load_state()` implementation (lines 560-582)
  - `load_state_with_optimizer()` implementation (lines 585-611)
  - `_load_state_impl()` shared implementation (lines 531-557)

- `tinker/src/tinker/lib/public_interfaces/service_client.py` (lines 222-276)
  - `create_training_client_from_state()` implementation (lines 222-254)
  - `create_training_client_from_state_async()` implementation (lines 257-276)

- `tinker/src/tinker/types/save_weights_request.py`
  - Wire protocol definition for save requests

- `tinker/src/tinker/types/load_weights_request.py`
  - Wire protocol definition for load requests
  - **Critical:** Uses `optimizer: bool` field

### Elixir Source Files
- `lib/tinkex/training_client.ex`
  - Existing infrastructure for request sequencing
  - Pattern for async Task-based handlers (lines 386-433: `optim_step`)
  - Pattern for save operations (lines 440-473: `save_weights_for_sampler`)

- `lib/tinkex/service_client.ex`
  - Client creation patterns (lines 200-247)
  - Session management integration

- `lib/tinkex/api/weights.ex`
  - HTTP API layer (complete, lines 19-87)
  - `save_weights/2`, `load_weights/2` ready to use

- `lib/tinkex/types/load_weights_request.ex`
  - **Needs update:** Change `load_optimizer_state` to `optimizer` (line 36, 42, 70)

- `lib/tinkex/types/save_weights_request.ex`
  - Complete, matches Python wire format

- `lib/tinkex/types/save_weights_response.ex`
  - Complete, matches Python wire format

- `lib/tinkex/types/load_weights_response.ex`
  - Complete, matches Python wire format

### Related Documentation
- Python SDK API docs: `tinker/docs/api/trainingclient.md`
- Python SDK API docs: `tinker/docs/api/serviceclient.md`
- Checkpoint persistence patterns in production ML systems
- Adam optimizer state persistence requirements
