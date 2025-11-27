# Gap #10: Asynchronous Convenience Methods - Deep Dive Analysis

**Date:** November 27, 2025
**Status:** Analysis Complete
**Severity:** Medium
**Impact:** API Ergonomics & Usability

---

## Executive Summary

Python's Tinker SDK provides comprehensive async variants (`*_async`) for virtually all client methods across `ServiceClient`, `TrainingClient`, `SamplingClient`, and `RestClient`. Elixir's Tinkex has a **partially implemented async pattern** with good coverage in some areas (RestClient) but **missing critical async variants** in high-level client convenience methods (ServiceClient).

**Key Finding:** The gap is **not about BEAM's async capabilities** (which are excellent) but about **API consistency and user expectations** coming from the Python SDK. Elixir returns `Task.t()` for many operations, but not all methods that return Tasks have dedicated `*_async/N` wrapper functions.

---

## 1. Python SDK Async Architecture

### 1.1 Pattern Overview

Python implements a **dual API pattern** across all clients:

```python
# Pattern 1: Synchronous (blocks until complete)
result = client.method(args)  # Returns result directly

# Pattern 2: Asynchronous (returns awaitable)
result = await client.method_async(args)  # Returns awaitable/coroutine
```

**Implementation Strategy:**
- Both sync and async methods delegate to a common `_submit` method
- `_submit` returns `AwaitableConcurrentFuture[T]`
- Sync version calls `.result()` to block
- Async version calls `await` on the future

### 1.2 ServiceClient Async Methods

**File:** `tinker/lib/public_interfaces/service_client.py`

| Method | Line | Async Variant | Status |
|--------|------|---------------|--------|
| `get_server_capabilities()` | 82 | `get_server_capabilities_async()` | ✅ Line 98 |
| `create_lora_training_client()` | 153 | `create_lora_training_client_async()` | ✅ Line 199 |
| `create_training_client_from_state()` | 222 | `create_training_client_from_state_async()` | ✅ Line 257 |
| `create_sampling_client()` | 279 | `create_sampling_client_async()` | ✅ Line 323 |
| `create_rest_client()` | 342 | ❌ None | Synchronous factory |

**Key Implementation:**

```python
# Pattern used in ServiceClient
def _get_server_capabilities_submit(self) -> AwaitableConcurrentFuture[types.GetServerCapabilitiesResponse]:
    async def _get_server_capabilities_async():
        async def _send_request():
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                return await client.service.get_server_capabilities()
        return await self.holder.execute_with_retries(_send_request)
    return self.holder.run_coroutine_threadsafe(_get_server_capabilities_async())

@sync_only
@capture_exceptions(fatal=True)
def get_server_capabilities(self) -> types.GetServerCapabilitiesResponse:
    return self._get_server_capabilities_submit().result()  # Block until complete

@capture_exceptions(fatal=True)
async def get_server_capabilities_async(self) -> types.GetServerCapabilitiesResponse:
    return await self._get_server_capabilities_submit()  # Return awaitable
```

### 1.3 TrainingClient Async Methods

**File:** `tinker/lib/public_interfaces/training_client.py`

All major operations have async variants:

| Method | Async Variant | Return Type |
|--------|---------------|-------------|
| `forward()` | `forward_async()` | Line 225 |
| `forward_backward()` | `forward_backward_async()` | Line 319 |
| `forward_backward_custom()` | `forward_backward_custom_async()` | Line 364 |
| `optim_step()` | `optim_step_async()` | Line 472 |
| `save_state()` | `save_state_async()` | Line 526 |
| `load_state()` | `load_state_async()` | Line 580 |
| `load_state_with_optimizer()` | `load_state_with_optimizer_async()` | Line 607 |
| `save_weights_for_sampler()` | `save_weights_for_sampler_async()` | Line 683 |
| `save_weights_and_get_sampling_client()` | `save_weights_and_get_sampling_client_async()` | Line 822 |
| `get_info()` | `get_info_async()` | Line 721 |
| `create_sampling_client()` | `create_sampling_client_async()` | Line 768 |

**Pattern:** All async methods simply return the sync method result (which is already an `APIFuture`)

```python
async def forward_async(
    self,
    data: List[types.Datum],
    loss_fn: types.LossFnType,
    loss_fn_config: Dict[str, float] | None = None,
) -> APIFuture[types.ForwardBackwardOutput]:
    """Async version of forward."""
    return self.forward(data, loss_fn, loss_fn_config)  # Already returns future
```

### 1.4 SamplingClient Async Methods

**File:** `tinker/lib/public_interfaces/sampling_client.py`

| Method | Async Variant | Implementation |
|--------|---------------|----------------|
| `sample()` | `sample_async()` | Line 238 - wraps with `AwaitableConcurrentFuture` |
| `compute_logprobs()` | `compute_logprobs_async()` | Line 294 - wraps with `AwaitableConcurrentFuture` |

```python
async def sample_async(
    self,
    prompt: types.ModelInput,
    num_samples: int,
    sampling_params: types.SamplingParams,
    include_prompt_logprobs: bool = False,
    topk_prompt_logprobs: int = 0,
) -> types.SampleResponse:
    """Async version of sample."""
    return await AwaitableConcurrentFuture(
        self.sample(prompt, num_samples, sampling_params,
                   include_prompt_logprobs, topk_prompt_logprobs)
    )
```

### 1.5 RestClient Async Methods

**File:** `tinker/lib/public_interfaces/rest_client.py`

**Coverage:** 14 async entry points cover training runs, checkpoints, sessions, and samplers. Publish/unpublish are only exposed as `_from_tinker_path[_async]` and `get_weights_info_by_tinker_path` already returns an awaitable `APIFuture` (so no dedicated `_async` wrapper).

**Pattern:**

```python
def _get_training_run_submit(self, training_run_id: types.ModelID) -> AwaitableConcurrentFuture[types.TrainingRun]:
    async def _get_training_run_async() -> types.TrainingRun:
        async def _send_request() -> types.TrainingRun:
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                return await client.weights.get_training_run(model_id=training_run_id)
        return await self.holder.execute_with_retries(_send_request)
    return self.holder.run_coroutine_threadsafe(_get_training_run_async())

@sync_only
def get_training_run(self, training_run_id: types.ModelID) -> types.TrainingRun:
    return self._get_training_run_submit(training_run_id).result()

async def get_training_run_async(self, training_run_id: types.ModelID) -> types.TrainingRun:
    """Async version of get_training_run."""
    return await self._get_training_run_submit(training_run_id)
```

---

## 2. Elixir SDK Current State

### 2.1 ServiceClient Analysis

**File:** `lib/tinkex/service_client.ex`

| Method | Lines | Returns | Async Variant | Status |
|--------|-------|---------|---------------|--------|
| `create_lora_training_client/3` | 43-46 | `{:ok, pid()}` | ❌ **MISSING** | **GAP** |
| `create_training_client_from_state/3` | 54-58 | `{:ok, pid()}` | ❌ **MISSING** | **GAP** |
| `create_sampling_client/2` | 63-67 | `{:ok, pid()}` | ✅ Line 97 | **OK** |
| `get_server_capabilities/1` | 72-76 | `{:ok, response}` | ✅ Line 81 | **OK** |
| `create_rest_client/1` | 106-109 | `{:ok, RestClient.t()}` | ❌ None | Factory (OK) |

**Current Async Methods:**

```elixir
# ✅ HAS async variant
@spec get_server_capabilities_async(t()) :: Task.t()
def get_server_capabilities_async(service_client) do
  Task.async(fn -> get_server_capabilities(service_client) end)
end

# ✅ HAS async variant
@spec create_sampling_client_async(t(), keyword()) :: Task.t()
def create_sampling_client_async(service_client, opts \\ []) do
  Task.async(fn -> create_sampling_client(service_client, opts) end)
end
```

**Missing Async Methods:**

```elixir
# ❌ MISSING: create_lora_training_client_async/3
# ❌ MISSING: create_training_client_from_state_async/3
```

### 2.2 TrainingClient Analysis

**File:** `lib/tinkex/training_client.ex`

**Pattern:** Heavy operations already return `{:ok, Task.t()}` (async by default); lighter calls like `get_info/1` stay synchronous.

| Method | Lines | Returns | Dedicated `_async` Variant | Notes |
|--------|-------|---------|---------------------------|-------|
| `forward/4` | 194-201 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `forward_backward/4` | 194-201 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `forward_backward_custom/4` | 408-421 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `optim_step/3` | 236-240 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `save_state/3` | 306-312 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `load_state/3` | 320-326 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `load_state_with_optimizer/3` | 334-341 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `save_weights_for_sampler/3` | 253-260 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `save_weights_and_get_sampling_client/2` | 268-275 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `create_sampling_client_async/3` | 356-361 | `Task.t()` | ✅ Yes | **Only** async variant; no sync mirror |
| `get_info/1` | 70-73 | `{:ok, response}` | ❌ No | Synchronous call (Python has `_async`) |

**Special Case:**

```elixir
# ✅ HAS dedicated async helper (returns Task directly)
@spec create_sampling_client_async(t(), String.t(), keyword()) :: Task.t()
def create_sampling_client_async(client, model_path, opts \\ []) do
  Task.async(fn ->
    GenServer.call(client, {:create_sampling_client, model_path, opts}, :infinity)
  end)
end

# ✅ HAS synchronous helper for async operation
@spec save_weights_and_get_sampling_client_sync(t(), keyword()) :: {:ok, pid()} | {:error, Error.t()}
def save_weights_and_get_sampling_client_sync(client, opts \\ []) do
  with {:ok, task} <- save_weights_and_get_sampling_client(client, opts) do
    timeout = Keyword.get(opts, :await_timeout, :infinity)
    try do
      Task.await(task, timeout)
    catch
      :exit, reason ->
        {:error, Error.new(:request_failed, "save_weights_and_get_sampling_client failed",
                          data: %{exit_reason: reason})}
    end
  end
end
```

**Analysis:** Elixir's TrainingClient doesn't need `*_async` variants because:
1. All training operations already return `{:ok, Task.t()}`
2. Users can await with `Task.await(task)`
3. The Task pattern is the Elixir equivalent of Python's async/await

### 2.3 SamplingClient Analysis

**File:** `lib/tinkex/sampling_client.ex`

| Method | Lines | Returns | Async Variant | Status |
|--------|-------|---------|---------------|--------|
| `sample/4` | 79-82 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `compute_logprobs/3` | 89-107 | `{:ok, Task.t()}` | ❌ No | Already returns Task |
| `create_async/2` | 68-71 | `Task.t()` | ✅ Yes | Convenience wrapper |

**Pattern:**

```elixir
@spec create_async(pid(), keyword()) :: Task.t()
def create_async(service_client, opts \\ []) do
  Tinkex.ServiceClient.create_sampling_client_async(service_client, opts)
end

@spec sample(t(), map(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def sample(client, prompt, sampling_params, opts \\ []) do
  {:ok, Task.async(fn -> do_sample(client, prompt, sampling_params, opts) end)}
end
```

### 2.4 RestClient Analysis

**File:** `lib/tinkex/rest_client.ex`

**✅ EXCELLENT Coverage:** Async wrappers exist for every sync RestClient function (17 total), including the `*_by_tinker_path[_async]` aliases. Elixir (and Python) expose sampler IDs via session responses; there is no dedicated `list_samplers/0-1` endpoint.

| Method | Async Variant | Line |
|--------|---------------|------|
| `get_session/2` | `get_session_async/2` | 326 |
| `list_sessions/2` | `list_sessions_async/2` | 344 |
| `get_sampler/2` | `get_sampler_async/2` | 354 |
| `get_weights_info_by_tinker_path/2` | `get_weights_info_by_tinker_path_async/2` | 364 |
| `list_checkpoints/2` | `list_checkpoints_async/2` | 374 |
| `list_user_checkpoints/2` | `list_user_checkpoints_async/2` | 384 |
| `get_checkpoint_archive_url/2` | `get_checkpoint_archive_url_async/2` | 394 |
| `delete_checkpoint/2` | `delete_checkpoint_async/2` | 404 |
| `get_training_run/2` | `get_training_run_async/2` | 414 |
| `get_training_run_by_tinker_path/2` | `get_training_run_by_tinker_path_async/2` | 424 |
| `list_training_runs/2` | `list_training_runs_async/2` | 434 |
| `publish_checkpoint/2` | `publish_checkpoint_async/2` | 444 |
| `unpublish_checkpoint/2` | `unpublish_checkpoint_async/2` | 454 |
| `delete_checkpoint_by_tinker_path/2` | `delete_checkpoint_by_tinker_path_async/2` | 463 |
| `publish_checkpoint_from_tinker_path/2` | `publish_checkpoint_from_tinker_path_async/2` | 471 |
| `unpublish_checkpoint_from_tinker_path/2` | `unpublish_checkpoint_from_tinker_path_async/2` | 479 |
| `get_checkpoint_archive_url_by_tinker_path/2` | `get_checkpoint_archive_url_by_tinker_path_async/2` | 487 |

**Consistent Pattern:**

```elixir
@spec list_sessions_async(t(), keyword()) :: Task.t()
def list_sessions_async(client, opts \\ []) do
  Task.async(fn -> list_sessions(client, opts) end)
end
```

---

## 3. Granular Difference Analysis

### 3.1 Missing Methods in Elixir

#### ServiceClient - Missing Async Variants

```elixir
# ❌ MISSING
@spec create_lora_training_client_async(t(), String.t(), keyword()) :: Task.t()
def create_lora_training_client_async(service_client, base_model, opts \\ [])

# ❌ MISSING
@spec create_training_client_from_state_async(t(), String.t(), keyword()) :: Task.t()
def create_training_client_from_state_async(service_client, path, opts \\ [])
```

**Impact:**
- **High:** These are critical client creation methods
- Users coming from Python will expect these variants
- Breaking API consistency with RestClient (which has full coverage)

#### TrainingClient - Philosophical Difference

**Python Pattern:**
```python
# Sync version blocks
result = training_client.forward_backward(data, "cross_entropy")

# Async version returns awaitable
result = await training_client.forward_backward_async(data, "cross_entropy")
```

**Elixir Pattern:**
```elixir
# Already returns Task - no separate async variant needed
{:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
result = Task.await(task)
```

**Conclusion:** This is **NOT a gap** - it's a difference in async patterns:
- Python: Explicit sync/async split
- Elixir: Tasks are async by default, await when needed
- Minor mismatch: Python exposes `get_info_async()`, while Elixir only provides sync `get_info/1` (callers can still wrap it with `Task.async/1` if desired).

### 3.2 Naming Convention Differences

| Python | Elixir | Notes |
|--------|--------|-------|
| `*_async()` | `*_async/N` | Same convention |
| Returns `Awaitable[T]` | Returns `Task.t()` | Equivalent constructs |
| `await method_async()` | `Task.await(method())` | Both block until complete |

### 3.3 Pattern Inconsistencies Within Elixir

**Issue:** Inconsistent async coverage across clients

```elixir
# ✅ RestClient: Full async coverage (17 methods, incl. *_by_tinker_path aliases)
RestClient.list_sessions_async(client)
RestClient.get_training_run_async(client, run_id)
RestClient.publish_checkpoint_async(client, path)

# ✅ ServiceClient: Partial async coverage (2 of 4 factories)
ServiceClient.get_server_capabilities_async(client)
ServiceClient.create_sampling_client_async(client, opts)

# ❌ ServiceClient: Missing async variants
# ServiceClient.create_lora_training_client_async(client, model, opts)
# ServiceClient.create_training_client_from_state_async(client, path, opts)

# ⚠️ TrainingClient: Heavy ops already return Tasks, but get_info/1 is sync (Python has get_info_async)
{:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)

# ✅ SamplingClient: No async variants needed (already returns Tasks)
{:ok, task} = SamplingClient.sample(client, prompt, params)
```

---

## 4. BEAM vs Python Async Architecture

### 4.1 Why Python Needs Explicit Async

**Python's GIL (Global Interpreter Lock):**
- Threads don't provide true parallelism for CPU-bound work
- `async/await` enables cooperative multitasking
- Need explicit `async def` to create coroutines
- `asyncio` event loop required

**Python Pattern:**
```python
# Synchronous - blocks calling thread
def get_data():
    result = expensive_operation()
    return result

# Asynchronous - yields control during I/O
async def get_data_async():
    result = await expensive_operation()
    return result
```

### 4.2 Why Elixir Doesn't Always Need `*_async`

**BEAM's Actor Model:**
- Every process is lightweight (2KB initial)
- Preemptive multitasking by default
- GenServer calls can be async or sync
- Task module provides async primitives

**Elixir Pattern:**
```elixir
# GenServer call - synchronous by default
result = GenServer.call(server, :get_data)

# Task-wrapped - asynchronous execution
task = Task.async(fn -> GenServer.call(server, :get_data) end)
result = Task.await(task)

# Or return Task directly from function
def get_data_async(server) do
  Task.async(fn -> GenServer.call(server, :get_data) end)
end
```

**Key Insight:** Elixir can make ANY function async by wrapping it in `Task.async/1`. Python requires explicit `async def` declaration.

### 4.3 When Elixir Benefits from `*_async` Variants

**1. API Consistency:**
```elixir
# User expects both patterns to exist
{:ok, sessions} = RestClient.list_sessions(client)         # Sync
task = RestClient.list_sessions_async(client)               # Async
```

**2. Parallel Operations:**
```elixir
# Easy parallel execution
tasks = [
  ServiceClient.get_server_capabilities_async(client),
  ServiceClient.create_sampling_client_async(client, opts),
  # ❌ Missing: ServiceClient.create_lora_training_client_async(client, model, opts)
]
results = Task.await_many(tasks)
```

**3. Pipeline Composition:**
```elixir
# Can compose async operations
client
|> ServiceClient.get_server_capabilities_async()
|> Task.await()
|> process_capabilities()
```

---

## 5. TDD Implementation Plan

### 5.1 Phase 1: ServiceClient Async Methods

#### Test Suite: `test/tinkex/service_client_async_test.exs`

```elixir
defmodule Tinkex.ServiceClientAsyncTest do
  use Tinkex.IntegrationCase, async: true

  describe "create_lora_training_client_async/3" do
    test "returns Task that resolves to training client pid" do
      service = start_supervised!({ServiceClient, config: test_config()})

      # Act
      task = ServiceClient.create_lora_training_client_async(
        service,
        "meta-llama/Llama-3.1-8B",
        rank: 16
      )

      # Assert
      assert %Task{} = task
      assert {:ok, pid} = Task.await(task, 30_000)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "allows parallel training client creation" do
      service = start_supervised!({ServiceClient, config: test_config()})

      # Act - create multiple clients in parallel
      tasks = [
        ServiceClient.create_lora_training_client_async(service, "model-a", rank: 8),
        ServiceClient.create_lora_training_client_async(service, "model-b", rank: 16),
        ServiceClient.create_lora_training_client_async(service, "model-c", rank: 32)
      ]

      # Assert
      results = Task.await_many(tasks, 60_000)
      assert length(results) == 3
      assert Enum.all?(results, fn {:ok, pid} -> is_pid(pid) end)
    end

    test "handles errors gracefully" do
      service = start_supervised!({ServiceClient, config: test_config()})

      # Act
      task = ServiceClient.create_lora_training_client_async(
        service,
        "invalid-model",
        rank: 16
      )

      # Assert
      assert {:error, %Error{}} = Task.await(task)
    end
  end

  describe "create_training_client_from_state_async/3" do
    test "returns Task that resolves to training client with loaded weights" do
      service = start_supervised!({ServiceClient, config: test_config()})
      checkpoint_path = "tinker://test-run/weights/checkpoint-001"

      # Arrange - create checkpoint first
      {:ok, training_client} = ServiceClient.create_lora_training_client(
        service, "model", rank: 16
      )
      {:ok, save_task} = TrainingClient.save_state(training_client, "checkpoint-001")
      {:ok, _} = Task.await(save_task)

      # Act
      task = ServiceClient.create_training_client_from_state_async(
        service,
        checkpoint_path
      )

      # Assert
      assert %Task{} = task
      assert {:ok, pid} = Task.await(task, 30_000)
      assert is_pid(pid)

      # Verify weights loaded
      {:ok, info} = TrainingClient.get_info(pid)
      assert info.model_data.lora_rank == 16
    end

    test "supports parallel checkpoint loading" do
      service = start_supervised!({ServiceClient, config: test_config()})

      paths = [
        "tinker://run-1/weights/ckpt-001",
        "tinker://run-2/weights/ckpt-001",
        "tinker://run-3/weights/ckpt-001"
      ]

      # Act
      tasks = Enum.map(paths, fn path ->
        ServiceClient.create_training_client_from_state_async(service, path)
      end)

      # Assert
      results = Task.await_many(tasks, 60_000)
      assert length(results) == 3
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "parallel operations" do
    test "can mix async operations from different methods" do
      service = start_supervised!({ServiceClient, config: test_config()})

      # Act - run different operations in parallel
      tasks = [
        ServiceClient.get_server_capabilities_async(service),
        ServiceClient.create_sampling_client_async(service, base_model: "model-a"),
        ServiceClient.create_lora_training_client_async(service, "model-b", rank: 16)
      ]

      # Assert
      [capabilities, sampling, training] = Task.await_many(tasks, 30_000)

      assert {:ok, %GetServerCapabilitiesResponse{}} = capabilities
      assert {:ok, sampling_pid} = sampling
      assert {:ok, training_pid} = training
      assert is_pid(sampling_pid)
      assert is_pid(training_pid)
    end
  end
end
```

#### Implementation: Add to `lib/tinkex/service_client.ex`

```elixir
@doc """
Create a LoRA training client asynchronously.

Returns a Task that resolves to `{:ok, pid()}` or `{:error, reason}`.

## Examples

    task = ServiceClient.create_lora_training_client_async(
      service_pid,
      "meta-llama/Llama-3.1-8B",
      rank: 16
    )
    {:ok, training_pid} = Task.await(task)

    # Parallel creation
    tasks = [
      ServiceClient.create_lora_training_client_async(service, "model-a", rank: 8),
      ServiceClient.create_lora_training_client_async(service, "model-b", rank: 16)
    ]
    results = Task.await_many(tasks)
"""
@spec create_lora_training_client_async(t(), String.t(), keyword()) :: Task.t()
def create_lora_training_client_async(service_client, base_model, opts \\ [])
    when is_binary(base_model) do
  Task.async(fn ->
    create_lora_training_client(service_client, base_model, opts)
  end)
end

@doc """
Create a training client from saved checkpoint asynchronously.

Returns a Task that resolves to `{:ok, pid()}` or `{:error, reason}`.
The checkpoint's metadata (LoRA config, base model) is fetched automatically.

## Examples

    path = "tinker://run-123/weights/checkpoint-001"
    task = ServiceClient.create_training_client_from_state_async(service_pid, path)
    {:ok, training_pid} = Task.await(task, 60_000)

    # Parallel checkpoint loading
    paths = ["tinker://run-1/weights/ckpt-001", "tinker://run-2/weights/ckpt-001"]
    tasks = Enum.map(paths, fn path ->
      ServiceClient.create_training_client_from_state_async(service, path)
    end)
    results = Task.await_many(tasks, :infinity)
"""
@spec create_training_client_from_state_async(t(), String.t(), keyword()) :: Task.t()
def create_training_client_from_state_async(service_client, path, opts \\ [])
    when is_binary(path) do
  Task.async(fn ->
    create_training_client_from_state(service_client, path, opts)
  end)
end
```

### 5.2 Phase 2: Documentation Updates

#### Update Module Documentation

**File:** `lib/tinkex/service_client.ex` - Add to `@moduledoc`

```elixir
@moduledoc """
Entry point for Tinkex operations.

## Async Operations

ServiceClient provides async variants for long-running operations:

    # Synchronous - blocks until complete
    {:ok, training_pid} = ServiceClient.create_lora_training_client(
      service, "model", rank: 16
    )

    # Asynchronous - returns Task immediately
    task = ServiceClient.create_lora_training_client_async(
      service, "model", rank: 16
    )
    {:ok, training_pid} = Task.await(task, 30_000)

Async methods enable parallel operations:

    tasks = [
      ServiceClient.get_server_capabilities_async(service),
      ServiceClient.create_sampling_client_async(service, base_model: "model-a"),
      ServiceClient.create_lora_training_client_async(service, "model-b", rank: 16)
    ]
    results = Task.await_many(tasks, 30_000)

## Available Async Methods

- `get_server_capabilities_async/1`
- `create_lora_training_client_async/3` ⭐ New
- `create_training_client_from_state_async/3` ⭐ New
- `create_sampling_client_async/2`
"""
```

### 5.3 Phase 3: Integration Tests

```elixir
defmodule Tinkex.AsyncIntegrationTest do
  use Tinkex.IntegrationCase

  @moduletag :integration
  @moduletag timeout: 120_000

  test "end-to-end async workflow" do
    # Arrange
    {:ok, service} = ServiceClient.start_link(config: test_config())

    # Act - Phase 1: Parallel initialization
    init_tasks = [
      ServiceClient.get_server_capabilities_async(service),
      ServiceClient.create_sampling_client_async(service, base_model: test_model()),
      ServiceClient.create_lora_training_client_async(service, test_model(), rank: 16)
    ]

    [{:ok, capabilities}, {:ok, sampling}, {:ok, training}] =
      Task.await_many(init_tasks, 30_000)

    # Act - Phase 2: Parallel training operations
    training_tasks = [
      Task.async(fn ->
        {:ok, task} = TrainingClient.forward_backward(training, test_data(), :cross_entropy)
        Task.await(task)
      end),
      Task.async(fn ->
        {:ok, task} = TrainingClient.optim_step(training, adam_params())
        Task.await(task)
      end)
    ]

    [{:ok, fwdbwd_result}, {:ok, optim_result}] = Task.await_many(training_tasks, 30_000)

    # Act - Phase 3: Parallel checkpoint operations
    {:ok, save_task} = TrainingClient.save_state(training, "test-checkpoint")
    {:ok, save_result} = Task.await(save_task)

    checkpoint_tasks = [
      Task.async(fn ->
        {:ok, client} = ServiceClient.create_rest_client(service)
        RestClient.list_checkpoints(client, save_result.training_run_id)
      end),
      ServiceClient.create_training_client_from_state_async(
        service,
        save_result.tinker_path
      )
    ]

    [{:ok, checkpoints}, {:ok, restored_training}] = Task.await_many(checkpoint_tasks)

    # Assert
    assert is_struct(capabilities, GetServerCapabilitiesResponse)
    assert is_pid(sampling)
    assert is_pid(training)
    assert is_pid(restored_training)
    assert length(checkpoints.checkpoints) > 0
  end
end
```

### 5.4 Phase 4: Benchmark Async Performance

```elixir
defmodule Tinkex.AsyncBenchmark do
  def benchmark_parallel_creation do
    service = start_service()

    # Sequential baseline
    sequential_time = :timer.tc(fn ->
      Enum.each(1..10, fn i ->
        {:ok, _} = ServiceClient.create_lora_training_client(
          service, "model-#{i}", rank: 16
        )
      end)
    end) |> elem(0)

    # Parallel with async
    parallel_time = :timer.tc(fn ->
      tasks = Enum.map(1..10, fn i ->
        ServiceClient.create_lora_training_client_async(
          service, "model-#{i}", rank: 16
        )
      end)
      Task.await_many(tasks, :infinity)
    end) |> elem(0)

    IO.puts("Sequential: #{sequential_time / 1_000_000}s")
    IO.puts("Parallel: #{parallel_time / 1_000_000}s")
    IO.puts("Speedup: #{sequential_time / parallel_time}x")
  end
end
```

---

## 6. API Design Considerations

### 6.1 BEAM Idiom Consistency

**Recommendation:** Follow BEAM conventions while maintaining Python SDK compatibility.

```elixir
# ✅ Good: Clear async variant
def create_lora_training_client_async(service, model, opts) do
  Task.async(fn -> create_lora_training_client(service, model, opts) end)
end

# ❌ Bad: Hiding Task behavior
def create_lora_training_client_async(service, model, opts) do
  create_lora_training_client(service, model, opts)  # Returns {:ok, pid} directly?
end
```

**Pattern Chosen:**
- Async variants return `Task.t()` directly (not `{:ok, Task.t()}`)
- Consistent with `RestClient` and existing `ServiceClient` methods
- Mirrors Elixir stdlib (`Task.async/1`, `GenServer.call/3`)

### 6.2 Error Handling in Tasks

```elixir
# Task failures are caught during await
task = ServiceClient.create_lora_training_client_async(service, "invalid-model")

case Task.await(task) do
  {:ok, pid} -> {:ok, pid}
  {:error, %Error{} = error} -> {:error, error}
end

# Or use Task.yield/2 for timeout control
case Task.yield(task, 30_000) || Task.shutdown(task) do
  {:ok, {:ok, pid}} -> {:ok, pid}
  {:ok, {:error, error}} -> {:error, error}
  nil -> {:error, :timeout}
end
```

### 6.3 Deprecation Strategy (if needed)

**Not Needed:** Adding `*_async` variants is **additive** - no breaking changes.

```elixir
# Old code continues to work
{:ok, pid} = ServiceClient.create_lora_training_client(service, model)

# New async option available
task = ServiceClient.create_lora_training_client_async(service, model)
{:ok, pid} = Task.await(task)
```

---

## 7. Summary & Recommendations

### 7.1 Current State Assessment

| Client | Async Coverage | Status |
|--------|---------------|--------|
| **RestClient** | 100% (17/17 methods, incl. `_by_tinker_path` aliases) | ✅ **Excellent** |
| **ServiceClient** | 50% (2/4 factories; missing training client async helpers) | ⚠️ **Incomplete** |
| **TrainingClient** | Heavy ops already return `{:ok, Task.t()}`; `get_info/1` is sync-only (Python has `_async`) | ⚠️ **Minor mismatch** |
| **SamplingClient** | Task-returning by design (`sample/4`, `compute_logprobs/3`) | ✅ **By Design** |

### 7.2 Priority Actions

**High Priority:**
1. ✅ Add `create_lora_training_client_async/3` to ServiceClient
2. ✅ Add `create_training_client_from_state_async/3` to ServiceClient
3. ✅ Update documentation with async patterns
4. ✅ Add integration tests for parallel workflows

**Medium Priority:**
5. Document async vs sync tradeoffs in guides
6. Add benchmarks for parallel vs sequential operations
7. Create migration guide for Python SDK users
8. Optional parity helper: add `TrainingClient.get_info_async/1` wrapper (Task-wrapped `GenServer.call/3`)

**Low Priority:**
9. Consider adding convenience helpers like `Task.await_many_ok/2`
10. Add telemetry events for async operation tracking

### 7.3 Final Recommendation

**Implement the missing async variants** to achieve:

1. **API Consistency:** Match RestClient's comprehensive async coverage
2. **User Expectations:** Python SDK users expect `*_async` variants
3. **Parallel Workflows:** Enable efficient concurrent client creation
4. **Zero Breaking Changes:** Purely additive API enhancement

**Implementation Effort:** Low (< 50 LOC)
**User Impact:** High (better API ergonomics, parallel execution)
**Risk:** Minimal (no existing code affected)

---

## 8. Code Metrics

### 8.1 Lines of Code Analysis

**Python Async Implementation:**
- ServiceClient: ~200 lines for 4 async methods
- TrainingClient: ~150 lines for 11 async methods
- SamplingClient: ~50 lines for 2 async methods
- RestClient: ~400 lines for 14 async methods (no `publish_checkpoint_async`; only `_from_tinker_path` variants)
- **Total:** ~750-800 lines

**Elixir Async Surface (current vs. proposed):**
- Current async-named helpers: 2 (ServiceClient) + 17 (RestClient) + 1 (TrainingClient helper) + 1 (SamplingClient helper) = 21
- Proposed additions for parity: +2 ServiceClient async factories (LoRA + from_state)

**Relative size:** Elixir implementation is substantially smaller because:
- No need for `_submit` infrastructure
- `Task.async/1` is simpler than Python's `asyncio`
- No GIL/threading concerns

### 8.2 Complexity Metrics

**Python Async Complexity:**
- Cyclomatic Complexity: 3-5 per method
- Requires: Async runtime, futures, threading coordination
- Error handling: Try/except in async context

**Elixir Async Complexity:**
- Cyclomatic Complexity: 1-2 per method
- Requires: Only `Task.async/1` wrapper
- Error handling: Standard `{:ok, result}` tuples

---

## Appendix A: Full Method Inventory

### Python SDK - Complete Async Methods

**ServiceClient (4 methods):**
- `get_server_capabilities_async()`
- `create_lora_training_client_async(base_model, rank=32, ...)`
- `create_training_client_from_state_async(path, user_metadata=None)`
- `create_sampling_client_async(model_path=None, base_model=None, retry_config=None)`

**TrainingClient (11 methods):**
- `forward_async(data, loss_fn, loss_fn_config=None)`
- `forward_backward_async(data, loss_fn, loss_fn_config=None)`
- `forward_backward_custom_async(data, loss_fn)`
- `optim_step_async(adam_params)`
- `save_state_async(name)`
- `load_state_async(path)`
- `load_state_with_optimizer_async(path)`
- `save_weights_for_sampler_async(name)`
- `save_weights_and_get_sampling_client_async(name=None, retry_config=None)`
- `get_info_async()`
- `create_sampling_client_async(model_path, retry_config=None)`

**SamplingClient (2 methods):**
- `sample_async(prompt, num_samples, sampling_params, include_prompt_logprobs=False, topk_prompt_logprobs=0)`
- `compute_logprobs_async(prompt)`

**RestClient (14 methods):**
- `get_training_run_async(training_run_id)`
- `get_training_run_by_tinker_path_async(tinker_path)`
- `list_training_runs_async(limit=20, offset=0)`
- `list_checkpoints_async(training_run_id)`
- `get_checkpoint_archive_url_async(training_run_id, checkpoint_id)`
- `delete_checkpoint_async(training_run_id, checkpoint_id)`
- `delete_checkpoint_from_tinker_path_async(tinker_path)`
- `get_checkpoint_archive_url_from_tinker_path_async(tinker_path)`
- `publish_checkpoint_from_tinker_path_async(tinker_path)`
- `unpublish_checkpoint_from_tinker_path_async(tinker_path)`
- `list_user_checkpoints_async(limit=100, offset=0)`
- `get_session_async(session_id)`
- `list_sessions_async(limit=20, offset=0)`
- `get_sampler_async(sampler_id)`
- _Note:_ `get_weights_info_by_tinker_path` returns an awaitable `APIFuture` and has no dedicated `_async` wrapper.

**Total: 31 async methods**

### Elixir SDK - Current Async Methods

**ServiceClient (2 methods):**
- `get_server_capabilities_async/1`
- `create_sampling_client_async/2`

**TrainingClient (1 method):**
- `create_sampling_client_async/3` (special case)

**SamplingClient (1 method):**
- `create_async/2` (convenience wrapper)

**RestClient (17 methods):**
- `get_session_async/2`
- `list_sessions_async/2`
- `get_sampler_async/2`
- `get_weights_info_by_tinker_path_async/2`
- `list_checkpoints_async/2`
- `list_user_checkpoints_async/2`
- `get_checkpoint_archive_url_async/2`
- `delete_checkpoint_async/2`
- `get_training_run_async/2`
- `get_training_run_by_tinker_path_async/2`
- `list_training_runs_async/2`
- `publish_checkpoint_async/2`
- `unpublish_checkpoint_async/2`
- `delete_checkpoint_by_tinker_path_async/2`
- `publish_checkpoint_from_tinker_path_async/2`
- `unpublish_checkpoint_from_tinker_path_async/2`
- `get_checkpoint_archive_url_by_tinker_path_async/2`

**Total: 21 async-named methods (plus many Task-returning training/sampling ops)**

**Missing: 2 ServiceClient methods**
- `create_lora_training_client_async/3`
- `create_training_client_from_state_async/3`

---

## Appendix B: Implementation Checklist

- [ ] Add `create_lora_training_client_async/3` to ServiceClient
- [ ] Add `create_training_client_from_state_async/3` to ServiceClient
- [ ] Write unit tests for both new methods
- [ ] Write integration tests for parallel workflows
- [ ] Update ServiceClient moduledoc with async examples
- [ ] Add function-level documentation
- [ ] Update CHANGELOG.md
- [ ] Add benchmarks for parallel vs sequential
- [ ] Update migration guide (if exists)
- [ ] Review with Python SDK users for feedback
