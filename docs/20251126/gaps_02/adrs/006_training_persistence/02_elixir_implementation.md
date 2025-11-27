# Elixir Training Persistence Implementation

**Date:** 2025-11-26
**Status:** Partial Implementation - Missing Critical Features
**Source:** `tinkex/lib/tinkex/training_client.ex`, `tinkex/lib/tinkex/service_client.ex`

## Overview

The Elixir Tinkex SDK has **partial** checkpoint persistence capabilities. It implements `save_weights_for_sampler` but is **missing all checkpoint loading functionality** and has a **critical wire protocol compatibility issue**.

---

## Current TrainingClient Implementation

### 1. `save_weights_for_sampler(client, opts)` → `Task.t()`

**Location:** `lib/tinkex/training_client.ex` lines 116-122

**Purpose:** Save weights for downstream sampling (NOT for training checkpoints)

**Implementation:**

```elixir
@doc """
Save weights for downstream sampling.

Returns a `Task.t()` that yields `{:ok, map()}` or `{:error, %Tinkex.Error{}}`.
"""
@spec save_weights_for_sampler(t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def save_weights_for_sampler(client, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:save_weights_for_sampler, opts}, :infinity)
   end)}
end
```

**GenServer Handler:** Lines 441-473

```elixir
@impl true
def handle_call({:save_weights_for_sampler, opts}, from, state) do
  seq_id = state.request_id_counter
  new_counter = seq_id + 1

  case send_save_weights_for_sampler_request(seq_id, opts, state) do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, response} ->
      Task.start(fn ->
        reply =
          try do
            handle_save_weights_response(response, state, opts)
          rescue
            e ->
              {:error,
               %Error{
                 message: "Save weights failed: #{Exception.message(e)}",
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

**Request Builder:** Lines 665-694

```elixir
defp send_save_weights_for_sampler_request(seq_id, opts, state) do
  request = %SaveWeightsForSamplerRequest{
    model_id: state.model_id,
    path: Keyword.get(opts, :path),
    sampling_session_seq_id: Keyword.get(opts, :sampling_session_seq_id),
    seq_id: seq_id
  }

  case state.weights_api.save_weights_for_sampler(request,
         config: state.config,
         telemetry_metadata:
           base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
       ) do
    {:ok, %{"request_id" => _} = future} ->
      {:ok, future}

    {:ok, %{request_id: _} = future} ->
      {:ok, future}

    {:ok, result} ->
      {:ok, result}

    {:error, %Error{} = error} ->
      {:error, error}

    other ->
      {:error,
       Error.new(:validation, "Invalid save_weights_for_sampler response: #{inspect(other)}")}
  end
end
```

**Key Features:**
- Sequential request ordering (via `seq_id`)
- Background Task for async execution
- Error handling and exception capture
- GenServer-based concurrency control

**HTTP Details:**
- Endpoint: `POST /api/v1/save_weights_for_sampler`
- Request type: `SaveWeightsForSamplerRequest`
- Response type: `SaveWeightsForSamplerResponse`

**Limitations:**
- This is for SAMPLING, not training checkpoints
- Cannot save training state for later resumption
- Different endpoint than Python's `save_state()`

---

## Missing TrainingClient Methods

### 1. `save_state(name)` - MISSING

**Status:** Not implemented
**Required for:** Checkpoint persistence during training

**Expected Signature:**
```elixir
@spec save_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def save_state(client, name, opts \\ [])
```

**Expected Behavior:**
- Should call `POST /api/v1/save_weights`
- Should use `SaveWeightsRequest` (NOT `SaveWeightsForSamplerRequest`)
- Should return `SaveWeightsResponse` with tinker:// path
- Should support sequential request ordering

**Current Workaround:** NONE - Feature completely missing

---

### 2. `load_state(path)` - MISSING

**Status:** Not implemented
**Required for:** Loading checkpoints without optimizer state

**Expected Signature:**
```elixir
@spec load_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def load_state(client, path, opts \\ [])
```

**Expected Behavior:**
- Should call `POST /api/v1/load_weights`
- Should use `LoadWeightsRequest` with `load_optimizer_state: false`
- **CRITICAL:** Must use correct field name (see Wire Protocol section)
- Should return `LoadWeightsResponse`
- Should support sequential request ordering

**Current Workaround:** NONE - Feature completely missing

---

### 3. `load_state_with_optimizer(path)` - MISSING

**Status:** Not implemented
**Required for:** Resuming training with optimizer state

**Expected Signature:**
```elixir
@spec load_state_with_optimizer(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def load_state_with_optimizer(client, path, opts \\ [])
```

**Expected Behavior:**
- Should call `POST /api/v1/load_weights`
- Should use `LoadWeightsRequest` with `load_optimizer_state: true`
- **CRITICAL:** Must use correct field name (see Wire Protocol section)
- Should return `LoadWeightsResponse`
- Should preserve optimizer momentum and variance

**Current Workaround:** NONE - Feature completely missing

---

## Missing ServiceClient Methods

### 4. `create_training_client_from_state(path, opts)` - MISSING

**Status:** Not implemented
**Required for:** Creating training clients from checkpoints

**Expected Signature:**
```elixir
@spec create_training_client_from_state(t(), String.t(), keyword()) ::
  {:ok, TrainingClient.t()} | {:error, Error.t()}
def create_training_client_from_state(service_client, path, opts \\ [])
```

**Expected Workflow:**
1. Query checkpoint metadata via REST API
2. Extract base_model and lora_config
3. Create new TrainingClient with same architecture
4. Load weights into client
5. Return configured client

**Current Workaround:** Manual multi-step process:
```elixir
# 1. Query metadata manually
{:ok, rest_client} = ServiceClient.create_rest_client(service)
{:ok, weights_info} = RestClient.get_weights_info_by_tinker_path(rest_client, path)

# 2. Create client with same config
{:ok, training_client} = ServiceClient.create_lora_training_client(service,
  base_model: weights_info.base_model,
  rank: weights_info.lora_rank
)

# 3. Load weights - BUT THIS METHOD DOESN'T EXIST!
# {:ok, task} = TrainingClient.load_state(training_client, path)
# Task.await(task)
```

**Problem:** Even manual workaround fails because `load_state()` doesn't exist!

---

## Existing Type Definitions

### SaveWeightsRequest

**Location:** `lib/tinkex/types/save_weights_request.ex`

```elixir
defmodule Tinkex.Types.SaveWeightsRequest do
  @moduledoc """
  Request to save model weights as a checkpoint.

  Mirrors Python tinker.types.SaveWeightsRequest.
  """

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :type]}
  defstruct [:model_id, :path, :seq_id, type: "save_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          seq_id: integer() | nil,
          type: String.t()
        }
end
```

**Status:** ✅ Complete and compatible with Python

**Wire Format:**
```json
{
  "model_id": "run-123",
  "path": "checkpoint-001",
  "seq_id": 1,
  "type": "save_weights"
}
```

---

### SaveWeightsResponse

**Location:** `lib/tinkex/types/save_weights_response.ex`

```elixir
defmodule Tinkex.Types.SaveWeightsResponse do
  @moduledoc """
  Response payload for save_weights.
  """

  @enforce_keys [:path]
  defstruct [:path, type: "save_weights"]

  @type t :: %__MODULE__{
          path: String.t(),
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"path" => path} = json) do
    %__MODULE__{path: path, type: json["type"] || "save_weights"}
  end

  def from_json(%{path: path} = json) do
    %__MODULE__{path: path, type: json[:type] || "save_weights"}
  end
end
```

**Status:** ✅ Complete and compatible with Python

**Wire Format:**
```json
{
  "path": "tinker://run-123/weights/checkpoint-001",
  "type": "save_weights"
}
```

---

### LoadWeightsRequest - CRITICAL INCOMPATIBILITY

**Location:** `lib/tinkex/types/load_weights_request.ex`

```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  Mirrors Python `tinker.types.LoadWeightsRequest`.

  ## Wire Format

  ```json
  {
    "model_id": "run-123",
    "path": "tinker://run-123/weights/checkpoint-001",
    "seq_id": 1,
    "load_optimizer_state": true,  # ← WRONG FIELD NAME!
    "type": "load_weights"
  }
  ```
  """

  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}
  defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          load_optimizer_state: boolean(),  # ← WRONG FIELD NAME!
          type: String.t()
        }
end
```

**Status:** ❌ **CRITICAL WIRE PROTOCOL INCOMPATIBILITY**

**Problem:**
- Python uses field name: `optimizer`
- Elixir uses field name: `load_optimizer_state`
- Server expects Python's field name
- Elixir requests will fail or be ignored

**Correct Wire Format (Python):**
```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 1,
  "optimizer": true,
  "type": "load_weights"
}
```

**Current Wire Format (Elixir - WRONG):**
```json
{
  "model_id": "run-123",
  "path": "tinker://run-123/weights/checkpoint-001",
  "seq_id": 1,
  "load_optimizer_state": true,
  "type": "load_weights"
}
```

**Fix Required:**
```elixir
# Change from:
defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]
@derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}

# To:
defstruct [:model_id, :path, :seq_id, optimizer: false, type: "load_weights"]
@derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :optimizer, :type]}
```

---

### LoadWeightsResponse

**Location:** `lib/tinkex/types/load_weights_response.ex`

```elixir
defmodule Tinkex.Types.LoadWeightsResponse do
  @moduledoc """
  Response payload for load_weights.
  """

  defstruct [:path, type: "load_weights"]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"path" => path} = json) do
    %__MODULE__{path: path, type: json["type"] || "load_weights"}
  end

  def from_json(%{} = json) do
    %__MODULE__{path: json[:path], type: json[:type] || "load_weights"}
  end
end
```

**Status:** ✅ Complete and compatible with Python

**Wire Format:**
```json
{
  "path": "tinker://run-123/weights/checkpoint-001",
  "type": "load_weights"
}
```

---

## API Module Implementation

### Tinkex.API.Weights

**Location:** `lib/tinkex/api/weights.ex`

**Implemented Functions:**

```elixir
@doc """
Save model weights.
"""
@spec save_weights(map(), keyword()) ::
        {:ok, map()} | {:error, Tinkex.Error.t()}
def save_weights(request, opts) do
  Tinkex.API.post(
    "/api/v1/save_weights",
    request,
    Keyword.put(opts, :pool_type, :training)
  )
end

@doc """
Load model weights.
"""
@spec load_weights(map(), keyword()) ::
        {:ok, map()} | {:error, Tinkex.Error.t()}
def load_weights(request, opts) do
  Tinkex.API.post(
    "/api/v1/load_weights",
    request,
    Keyword.put(opts, :pool_type, :training)
  )
end

@doc """
Save weights for sampler.
"""
@spec save_weights_for_sampler(map(), keyword()) ::
        {:ok, map()} | {:error, Tinkex.Error.t()}
def save_weights_for_sampler(request, opts) do
  Tinkex.API.post(
    "/api/v1/save_weights_for_sampler",
    request,
    Keyword.put(opts, :pool_type, :training)
  )
end
```

**Status:**
- ✅ `save_weights()` - API exists but NOT exposed in TrainingClient
- ✅ `load_weights()` - API exists but NOT exposed in TrainingClient
- ✅ `save_weights_for_sampler()` - API exists AND exposed in TrainingClient

**Problem:** Low-level API exists but high-level TrainingClient methods don't call them!

---

## Request Ordering & Sequencing

### Current Implementation

```elixir
defmodule Tinkex.TrainingClient do
  # State includes request counter
  defstruct [
    :model_id,
    :session_id,
    :model_seq_id,
    :config,
    :http_pool,
    request_id_counter: 1,  # ← Sequential counter
    # ...
  ]

  # Allocate sequential IDs
  defp allocate_request_ids(count, counter) when count <= 0, do: {[], counter}

  defp allocate_request_ids(count, counter) do
    ids = Enum.to_list(counter..(counter + count - 1))
    {ids, counter + count}
  end
end
```

**Features:**
- ✅ Sequential request ID allocation
- ✅ Maintains order across operations
- ✅ Thread-safe (GenServer ensures serialization)

**Status:** Sequencing infrastructure is ready, just needs to be used for load/save operations

---

## ServiceClient Status

**Location:** `lib/tinkex/service_client.ex`

**Implemented:**
- ✅ `create_lora_training_client(service, opts)`
- ✅ `create_sampling_client(service, opts)`
- ✅ `create_rest_client(service)`

**Missing:**
- ❌ `create_training_client_from_state(service, path, opts)`

**Current Creation Methods:**

```elixir
@doc """
Create a training client from this ServiceClient.
"""
@spec create_lora_training_client(t(), keyword()) ::
        {:ok, pid()} | {:error, term()}
def create_lora_training_client(service_client, opts \\ []) do
  GenServer.call(service_client, {:create_training_client, opts})
end
```

**No checkpoint-based creation method exists.**

---

## Gap Summary

### TrainingClient Missing Features

| Feature | Status | Impact |
|---------|--------|--------|
| `save_state(name)` | ❌ Missing | Cannot save training checkpoints |
| `load_state(path)` | ❌ Missing | Cannot load checkpoints |
| `load_state_with_optimizer(path)` | ❌ Missing | Cannot resume training |
| `save_weights_for_sampler(name)` | ✅ Implemented | Only sampler weights work |

### ServiceClient Missing Features

| Feature | Status | Impact |
|---------|--------|--------|
| `create_training_client_from_state(path)` | ❌ Missing | Cannot create client from checkpoint |
| `create_lora_training_client(opts)` | ✅ Implemented | Fresh clients only |

### Type Definition Issues

| Type | Field Name Issue | Status |
|------|------------------|--------|
| `SaveWeightsRequest` | ✅ Correct | Compatible |
| `SaveWeightsResponse` | ✅ Correct | Compatible |
| `LoadWeightsRequest` | ❌ `load_optimizer_state` should be `optimizer` | **BREAKING** |
| `LoadWeightsResponse` | ✅ Correct | Compatible |

### API Module Status

| Function | Exists | Exposed in TrainingClient |
|----------|--------|---------------------------|
| `save_weights()` | ✅ Yes | ❌ No |
| `load_weights()` | ✅ Yes | ❌ No |
| `save_weights_for_sampler()` | ✅ Yes | ✅ Yes |

---

## Critical Issues

### 1. Wire Protocol Incompatibility

**Severity:** CRITICAL
**Impact:** Complete failure of load operations

The `LoadWeightsRequest` type uses the wrong field name. This will cause:
- Server rejecting requests (field not recognized)
- Silent failures (optimizer state not loaded)
- Incompatibility with Python clients

**Must Fix:** Change `load_optimizer_state` → `optimizer`

### 2. No Checkpoint Loading

**Severity:** HIGH
**Impact:** Cannot resume training, cannot use checkpoints

Without `load_state()` and `load_state_with_optimizer()`:
- No training resumption
- No checkpoint-based transfer learning
- No disaster recovery

### 3. No Checkpoint Saving (for training)

**Severity:** HIGH
**Impact:** Cannot create training checkpoints

Only `save_weights_for_sampler()` exists:
- Cannot save training state
- Cannot create recovery points
- Must rely on sampler endpoints for persistence

### 4. No ServiceClient Integration

**Severity:** MEDIUM
**Impact:** Poor user experience

Without `create_training_client_from_state()`:
- Manual multi-step process required
- Error-prone architecture detection
- No convenience wrapper

---

## Architecture Analysis

### Existing Patterns (Good Foundation)

The codebase already has good patterns that can be reused:

1. **GenServer-based concurrency control**
   - Sequential operation execution
   - Request ID allocation
   - Background task spawning

2. **API module structure**
   - Low-level HTTP functions exist
   - Type conversion helpers
   - Error handling

3. **Type definitions**
   - Struct definitions ready
   - JSON encoding/decoding
   - Type specs

**Problem:** High-level TrainingClient methods don't wire everything together!

---

## Next Steps

To close the gap, Elixir needs:

1. **Fix LoadWeightsRequest** - Change field name to `optimizer`
2. **Add TrainingClient.save_state()** - Call existing `Weights.save_weights()`
3. **Add TrainingClient.load_state()** - Call existing `Weights.load_weights()` with `optimizer: false`
4. **Add TrainingClient.load_state_with_optimizer()** - Call existing `Weights.load_weights()` with `optimizer: true`
5. **Add ServiceClient.create_training_client_from_state()** - Query metadata, create client, load weights

All the building blocks exist - they just need to be assembled correctly!
