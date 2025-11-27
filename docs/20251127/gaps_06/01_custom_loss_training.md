# Gap #1: Custom Loss Training - Deep Dive Analysis

**Date:** 2025-11-27
**Status:** Critical Gap - Training Not Implemented
**Severity:** HIGH - Current Elixir implementation only computes metrics, does not train

---

## Executive Summary

The Python SDK's `TrainingClient.forward_backward_custom()` **actually trains the model** by:
1. Running a forward pass to get logprobs
2. Computing custom loss using PyTorch autograd
3. Building synthetic gradients via `.backward()`
4. Sending gradients back to server via `forward_backward` with linear loss
5. Returning a merged `ForwardBackwardOutput` usable with `optim_step()`

The Elixir SDK's `TrainingClient.forward_backward_custom()` **only computes metrics** by:
1. Running a forward pass to get logprobs
2. Computing custom loss using Nx
3. Computing gradient norms for telemetry
4. Returning `CustomLossOutput` with **no training effect**
5. **Never sends gradients back to the server**

**This is a fundamental functional gap**, not just a difference in API design.

---

## Table of Contents

1. [Python Implementation Deep Dive](#1-python-implementation-deep-dive)
2. [Elixir Implementation Deep Dive](#2-elixir-implementation-deep-dive)
3. [Granular Differences](#3-granular-differences)
4. [Data Flow Comparison](#4-data-flow-comparison)
5. [Type System Comparison](#5-type-system-comparison)
6. [TDD Implementation Plan](#6-tdd-implementation-plan)
7. [Integration Considerations](#7-integration-considerations)
8. [Appendix: Code References](#8-appendix-code-references)

---

## 1. Python Implementation Deep Dive

### 1.1 Entry Point: `forward_backward_custom()`

**File:** `tinker/src/tinker/lib/public_interfaces/training_client.py:330-362`

```python
@sync_only
@capture_exceptions(fatal=True)
def forward_backward_custom(
    self, data: List[types.Datum], loss_fn: CustomLossFnV1
) -> APIFuture[types.ForwardBackwardOutput]:
    """Compute forward/backward with a custom loss function.

    Allows you to define custom loss functions that operate on log probabilities.
    The custom function receives logprobs and computes loss and gradients.

    Returns:
    - `APIFuture` containing the forward/backward outputs with custom loss
    """
    return self.holder.run_coroutine_threadsafe(
        self.forward_backward_custom_async(data, loss_fn)
    ).result()
```

**Key Observations:**
- Synchronous wrapper that calls async version
- Returns `APIFuture[ForwardBackwardOutput]` - **same type as normal forward_backward**
- This is critical: the output is usable with `optim_step()`

### 1.2 Core Logic: `forward_backward_custom_async()`

**File:** `tinker/src/tinker/lib/public_interfaces/training_client.py:363-412`

```python
@capture_exceptions(fatal=True)
async def forward_backward_custom_async(
    self, data: List[types.Datum], loss_fn: CustomLossFnV1
) -> APIFuture[types.ForwardBackwardOutput]:
    """Async version of forward_backward_custom."""
    import torch

    # STEP 1: Forward pass to get logprobs
    forward_future = await self.forward_async(data, "cross_entropy")
    forward_result = await forward_future.result_async()

    # STEP 2: Convert logprobs to PyTorch tensors with gradients
    logprobs_list: List[torch.Tensor] = []
    for out in forward_result.loss_fn_outputs:
        logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)
        logprobs_list.append(logprob)

    # STEP 3: User custom loss function
    loss, metrics = loss_fn(data, logprobs_list)

    # STEP 4: Backward pass to compute gradients
    loss.backward()
    grads = []
    for logprob in logprobs_list:
        if logprob.grad is None:
            raise ValueError("No gradient computed for logprob tensor")
        grads.append(logprob.grad)

    # STEP 5: Build synthetic dataset with gradients as weights
    linear_loss_data = []
    for datum, grad in zip(data, grads):
        loss_fn_inputs: Any = {
            "target_tokens": datum.loss_fn_inputs["target_tokens"],
            "weights": -grad,  # Pass PyTorch tensor directly (will be converted to TensorData)
        }
        linear_loss_data.append(
            types.Datum(
                model_input=datum.model_input,
                loss_fn_inputs=loss_fn_inputs,
            )
        )

    # STEP 6: Do the backward pass with the gradients
    backward_future = await self.forward_backward_async(linear_loss_data, "cross_entropy")

    # STEP 7: Merge custom metrics into the result
    def add_custom_metrics(
        results: List[types.ForwardBackwardOutput],
    ) -> types.ForwardBackwardOutput:
        result = results[0]  # Single result
        result.metrics.update(metrics)
        return result

    return _CombinedAPIFuture([backward_future], add_custom_metrics, self.holder)
```

### 1.3 Critical Implementation Details

#### Step 1: Forward Pass
```python
forward_future = await self.forward_async(data, "cross_entropy")
forward_result = await forward_future.result_async()
```
- Uses standard `forward_async()` which calls `/api/v1/forward` endpoint
- Returns `ForwardBackwardOutput` with `loss_fn_outputs` containing logprobs
- Logprobs are in `TensorData` format: `{"data": [...], "dtype": "float32", "shape": [...]}`

#### Step 2: PyTorch Tensor Conversion
```python
logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)
```
- Extracts raw data from `TensorData`
- Creates PyTorch tensor with `requires_grad=True`
- This enables autograd for custom loss computation

#### Step 3: Custom Loss Function
```python
CustomLossFnV1 = Callable[[List[types.Datum], List[Any]], Tuple[Any, Dict[str, float]]]

loss, metrics = loss_fn(data, logprobs_list)
```
- User function receives original data + logprobs as PyTorch tensors
- Must return: `(loss_tensor, metrics_dict)`
- Loss must be differentiable PyTorch tensor

#### Step 4: Gradient Computation
```python
loss.backward()
grads = [logprob.grad for logprob in logprobs_list]
```
- PyTorch autograd computes gradients w.r.t. logprobs
- Gradients are stored in `.grad` attribute
- These gradients will be sent to the server

#### Step 5: Synthetic Dataset Construction
```python
linear_loss_data = []
for datum, grad in zip(data, grads):
    loss_fn_inputs = {
        "target_tokens": datum.loss_fn_inputs["target_tokens"],
        "weights": -grad,  # Negative gradient as weights
    }
    linear_loss_data.append(types.Datum(...))
```

**Why negative gradients?**
- Server uses `weights` to scale the cross-entropy loss
- Gradient descent: θ ← θ - α∇L
- Negative gradient points toward minimum
- Server will apply these weights to logprobs directly

**Datum conversion:**
```python
# From datum.py:46-49
@classmethod
def _maybe_convert_array(cls, key: str, value: Any) -> Any:
    if _HAVE_TORCH and isinstance(value, torch.Tensor):
        return TensorData.from_torch(value)
```
- PyTorch tensor `grad` is automatically converted to `TensorData`
- Server receives standard `TensorData` format

#### Step 6: Server Training
```python
backward_future = await self.forward_backward_async(linear_loss_data, "cross_entropy")
```
- Calls **standard** `forward_backward` endpoint
- Server receives gradients as `weights` in loss_fn_inputs
- Server applies gradients to model parameters
- **This is where actual training happens**

#### Step 7: Result Merging
```python
def add_custom_metrics(results: List[types.ForwardBackwardOutput]) -> types.ForwardBackwardOutput:
    result = results[0]
    result.metrics.update(metrics)
    return result

return _CombinedAPIFuture([backward_future], add_custom_metrics, self.holder)
```
- Uses `_CombinedAPIFuture` to transform the result
- Merges user's custom metrics into server's response
- Returns standard `ForwardBackwardOutput` type

### 1.4 _CombinedAPIFuture Implementation

**File:** `tinker/src/tinker/lib/api_future_impl.py:279-296`

```python
class _CombinedAPIFuture(APIFuture[T]):
    def __init__(
        self,
        futures: List[APIFuture[T]],
        transform: Callable[[List[T]], T],
        holder: InternalClientHolder,
    ):
        self.futures = futures
        self.transform = transform
        self.holder = holder

    @sync_only
    def result(self, timeout: float | None = None) -> T:
        return self.holder.run_coroutine_threadsafe(self.result_async(timeout)).result()

    async def result_async(self, timeout: float | None = None) -> T:
        results = await asyncio.gather(*[future.result_async(timeout) for future in self.futures])
        return self.transform(results)
```

**Key Features:**
- Wraps one or more futures
- Applies transform function to results
- Preserves the same `APIFuture` interface
- Enables result post-processing without breaking API contract

---

## 2. Elixir Implementation Deep Dive

### 2.1 Entry Point: `forward_backward_custom()`

**File:** `tinkex/lib/tinkex/training_client.ex:360-421`

```elixir
@doc """
Compute forward/backward pass with custom loss function and optional regularizers.

Returns:
`{:ok, Task.t()}` that yields `{:ok, CustomLossOutput.t()}` or `{:error, Error.t()}`
"""
@spec forward_backward_custom(
        t(),
        list(Tinkex.Types.Datum.t()),
        loss_fn :: (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() -> {Nx.Tensor.t(), map()}),
        keyword()
      ) :: {:ok, Task.t()} | {:error, Error.t()}
def forward_backward_custom(client, data, loss_fn, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:forward_backward_custom, data, loss_fn, opts}, :infinity)
   end)}
end
```

**Key Observations:**
- Returns `Task` wrapping `CustomLossOutput.t()` - different type vs. Python’s `ForwardBackwardOutput`
- No backward call or gradients stored on the server, so an `optim_step/2` afterward would operate on stale/empty gradients
- Only computes metrics, no training effect

### 2.2 GenServer Handler

**File:** `tinkex/lib/tinkex/training_client.ex:880-914`

```elixir
@impl true
def handle_call({:forward_backward_custom, data, loss_fn, opts}, from, state) do
  # Spawn background Task for custom loss computation
  start_background_task(
    fn ->
      reply =
        try do
          # Execute forward pass to get logprobs
          case do_forward_for_custom_loss(data, opts, state) do
            {:ok, logprobs} ->
              # Run the regularizer pipeline
              alias Tinkex.Regularizer.Pipeline
              Pipeline.compute(data, logprobs, loss_fn, opts)

            {:error, _} = error ->
              error
          end
        rescue
          e ->
            {:error,
             %Error{
               message: "Custom loss failed: #{Exception.message(e)}",
               type: :request_failed,
               data: %{exception: e, stacktrace: __STACKTRACE__}
             }}
        end

      safe_reply(from, reply)
    end,
    from
  )

  {:noreply, state}
end
```

**Critical Difference:**
- Only calls `Pipeline.compute()` - computes metrics
- **Never calls `forward_backward_async()` or `send_forward_backward_request()`**
- No gradients sent to server
- No training happens

### 2.3 Forward Pass for Custom Loss

**File:** `tinkex/lib/tinkex/training_client.ex:1474-1519`

```elixir
defp do_forward_for_custom_loss(data, opts, state) do
  chunks = chunk_data(data)
  {seq_ids, _} = allocate_request_ids(length(chunks), state.request_id_counter)

  # Send forward requests for all chunks
  send_result =
    Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
      case send_forward_request(chunk, :cross_entropy, seq_id, opts, state) do
        {:ok, future} -> {:cont, {:ok, [future | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)

  case send_result do
    {:error, reason} ->
      {:error, reason}

    {:ok, futures_rev} ->
      futures = Enum.reverse(futures_rev)

      # Poll all futures and collect results
      polling_tasks =
        Enum.map(futures, fn future ->
          task = state.future_module.poll(future, poll_opts_with_type(state, opts, "ForwardCustomLoss"))
          unlink_task(task)
          task
        end)

      # Await results and extract logprobs
      case await_forward_results_for_custom_loss(polling_tasks, state.future_module) do
        {:ok, outputs} ->
          extract_logprobs_from_outputs(outputs)

        {:error, _} = error ->
          error
      end
  end
end
```

### 2.4 Logprobs Extraction

**File:** `tinkex/lib/tinkex/training_client.ex:1536-1555`

```elixir
defp extract_logprobs_from_outputs(outputs) do
  # Extract logprobs from loss_fn_outputs and convert to Nx tensor
  logprobs_lists =
    outputs
    |> Enum.flat_map(fn output ->
      Enum.map(output.loss_fn_outputs, fn
        %{"logprobs" => logprobs} when is_list(logprobs) -> logprobs
        %{"logprobs" => %{"data" => data}} when is_list(data) -> data
        _ -> []
      end)
    end)
    |> List.flatten()

  if logprobs_lists == [] do
    # Return a dummy tensor if no logprobs available (for testing)
    {:ok, Nx.tensor([0.0])}
  else
    {:ok, Nx.tensor(logprobs_lists)}
  end
end
```

**Issues:**
1. Flattens all logprobs into single tensor - loses structure
2. Dummy tensor fallback for testing - not production-ready
3. Drops dtype/shape metadata, making it impossible to map gradients back to individual loss_fn_inputs
4. No gradient computation setup

### 2.5 Regularizer Pipeline

**File:** `tinkex/lib/tinkex/regularizer/pipeline.ex:82-148`

```elixir
@spec compute(
        list(Tinkex.Types.Datum.t()),
        Nx.Tensor.t(),
        base_loss_fn :: function(),
        keyword()
      ) :: {:ok, CustomLossOutput.t()} | {:error, term()}
def compute(data, logprobs, base_loss_fn, opts \\ []) do
  regularizers = Keyword.get(opts, :regularizers, [])
  track_grad_norms = Keyword.get(opts, :track_grad_norms, false)

  # Execute base loss function
  {base_loss_tensor, base_metrics} = base_loss_fn.(data, logprobs)
  base_loss_value = Nx.to_number(base_loss_tensor)

  # Compute base gradient norm if tracking
  base_grad_norm =
    if track_grad_norms do
      compute_base_grad_norm(base_loss_fn, data, logprobs)
    else
      nil
    end

  # Execute regularizers
  case Executor.execute_all(regularizers, data, logprobs, opts) do
    {:ok, reg_outputs} ->
      # Compute total gradient norm if tracking
      total_grad_norm =
        if track_grad_norms and length(regularizers) > 0 do
          GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)
        else
          base_grad_norm
        end

      # Build output
      output = CustomLossOutput.build(
        base_loss_value,
        base_metrics,
        reg_outputs,
        base_grad_norm: base_grad_norm,
        total_grad_norm: total_grad_norm
      )

      {:ok, output}

    {:error, _} = error ->
      error
  end
end
```

**What it does:**
- Executes base loss function
- Executes regularizers
- Computes gradient norms for **telemetry only**
- Returns `CustomLossOutput` with metrics

**What it doesn't do:**
- No `.backward()` equivalent
- No gradient extraction
- No synthetic dataset creation
- No server communication
- **No training**

### 2.6 CustomLossOutput Type

**File:** `tinkex/lib/tinkex/types/custom_loss_output.ex:1-117`

```elixir
defmodule Tinkex.Types.CustomLossOutput do
  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizer_total,
    :total_grad_norm,
    regularizers: %{}
  ]

  @type base_loss_metrics :: %{
          value: float(),
          grad_norm: float() | nil,
          custom: %{String.t() => number()}
        }

  @type t :: %__MODULE__{
          loss_total: float(),
          base_loss: base_loss_metrics() | nil,
          regularizers: %{String.t() => RegularizerOutput.t()},
          regularizer_total: float() | nil,
          total_grad_norm: float() | nil
        }
end
```

**Key Differences from ForwardBackwardOutput:**
- Different struct entirely
- Contains metrics and norms
- No gradient state for `optim_step/2` because no backward happened
- No gradient data
- Purely for telemetry/logging

---

## 3. Granular Differences

### 3.1 API Contract Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Return Type** | `APIFuture[ForwardBackwardOutput]` | `{:ok, Task.t()}` → `CustomLossOutput.t()` |
| **Compatibility** | Provides gradients usable by `optim_step()` | No gradients for `optim_step()` (step would use stale/empty state) |
| **Training Effect** | **YES - trains model** | **NO - only metrics** |
| **Gradient Handling** | Sends to server | **Never sends to server** |
| **Use Case** | Production training | Telemetry/research only |

### 3.2 Data Flow Differences

#### Python Flow:
```
1. forward_async(data, "cross_entropy") → logprobs
2. torch.tensor(logprobs).requires_grad_(True)
3. loss, metrics = user_loss_fn(data, logprobs_tensors)
4. loss.backward() → compute gradients
5. Build linear_loss_data with gradients as weights
6. forward_backward_async(linear_loss_data, "cross_entropy") → TRAIN MODEL
7. Merge metrics into result
8. Return ForwardBackwardOutput (usable with optim_step)
```

#### Elixir Flow:
```
1. send_forward_request(data, :cross_entropy) → logprobs
2. Nx.tensor(logprobs_flat_list)  # No gradient tracking
3. loss_tensor, metrics = user_loss_fn.(data, logprobs_tensor)
4. Compute grad_norms (for telemetry only)
5. Build CustomLossOutput with metrics
6. Return CustomLossOutput (no gradients stored for optim_step)
7. END - no training happens
```

### 3.3 Loss Function Signature Differences

#### Python:
```python
CustomLossFnV1 = Callable[[List[types.Datum], List[Any]], Tuple[Any, Dict[str, float]]]

# User function receives:
# - data: List[Datum]
# - logprobs: List[torch.Tensor] with requires_grad=True
# Must return:
# - loss: torch.Tensor (differentiable)
# - metrics: Dict[str, float]
```

#### Elixir:
```elixir
loss_fn :: (list(Datum.t()), Nx.Tensor.t() -> {Nx.Tensor.t(), map()})

# User function receives:
# - data: list(Datum.t())
# - logprobs: Nx.Tensor (single flattened tensor)
# Must return:
# - loss: Nx.Tensor
# - metrics: map()
```

**Critical Differences:**
1. **Python**: List of tensors (one per datum) - preserves structure
2. **Elixir**: Single flattened tensor - loses per-datum structure
3. **Python**: Tensors have gradient tracking enabled
4. **Elixir**: Tensors have no gradient tracking (Nx.grad exists but not used)

### 3.4 Gradient Computation Differences

#### Python (PyTorch Autograd):
```python
# Step 1: Enable gradient tracking
logprob = torch.tensor(data).requires_grad_(True)

# Step 2: Compute loss
loss = my_loss_fn(logprob)

# Step 3: Backward pass
loss.backward()

# Step 4: Access gradients
grad = logprob.grad  # Shape matches logprob
```

#### Elixir (Nx.grad - NOT USED in current implementation):
```elixir
# Nx provides gradient computation
grad_fn = Nx.Defn.grad(fn logprobs -> my_loss_fn.(logprobs) end)
gradients = grad_fn.(logprobs_tensor)

# But this is NEVER called in forward_backward_custom!
```

**Why Elixir doesn't use Nx.grad:**
- Current implementation only computes gradient **norms** for telemetry
- No mechanism to send gradients to server
- Missing the synthetic dataset construction step

### 3.5 Server Communication Differences

#### Python:
```python
# STEP 1: Forward pass (get logprobs)
POST /api/v1/forward
Request: {
  "forward_input": {
    "data": [...],
    "loss_fn": "cross_entropy"
  }
}
Response: {
  "loss_fn_outputs": [{"logprobs": {"data": [...]}}]
}

# STEP 2: Backward pass (send gradients)
POST /api/v1/forward_backward
Request: {
  "forward_backward_input": {
    "data": [
      {
        "model_input": {...},
        "loss_fn_inputs": {
          "target_tokens": {...},
          "weights": {"data": [...gradients...]}  # CRITICAL!
        }
      }
    ],
    "loss_fn": "cross_entropy"
  }
}
Response: {
  "metrics": {...}  # Training happened on server
}
```

#### Elixir:
```elixir
# STEP 1: Forward pass (get logprobs)
POST /api/v1/forward
Request: same as Python

# STEP 2: ???
# NO SECOND REQUEST - training never happens!
```

### 3.6 Request/Seq ID Handling
- **Python**: Uses `_get_request_id()` for each call, so request IDs/seq IDs advance for every forward/backward phase.
- **Elixir**: `do_forward_for_custom_loss/3` calls `allocate_request_ids/2` but **throws away the updated counter** (`lib/tinkex/training_client.ex:1476-1518`), so repeated calls reuse the same seq_ids. This diverges from Python and can cause request/telemetry collisions even before addressing the missing backward pass.

---

## 4. Data Flow Comparison

### 4.1 Python Training Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                  forward_backward_custom()                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  forward_async()     │
                │  (cross_entropy)     │
                └──────────┬───────────┘
                           │
                           ▼
         ┌─────────────────────────────────┐
         │  Server: Forward Pass           │
         │  Returns: logprobs              │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  torch.tensor(logprobs)         │
         │  .requires_grad_(True)          │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  user_loss_fn(data, logprobs)   │
         │  Returns: (loss, metrics)       │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  loss.backward()                │
         │  Compute gradients              │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Build linear_loss_data         │
         │  weights = -gradients           │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  forward_backward_async()       │
         │  (with gradient weights)        │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Server: Apply Gradients        │
         │  MODEL TRAINED!                 │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  _CombinedAPIFuture             │
         │  Merge custom metrics           │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Return ForwardBackwardOutput   │
         │  Compatible with optim_step()   │
         └─────────────────────────────────┘
```

### 4.2 Elixir Metrics-Only Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                  forward_backward_custom()                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  do_forward_for_     │
                │  custom_loss()       │
                └──────────┬───────────┘
                           │
                           ▼
         ┌─────────────────────────────────┐
         │  send_forward_request()         │
         │  (cross_entropy)                │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Server: Forward Pass           │
         │  Returns: logprobs              │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Nx.tensor(flat_logprobs)       │
         │  (no gradient tracking)         │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Pipeline.compute()             │
         │  user_loss_fn.(data, logprobs)  │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Compute gradient norms         │
         │  (for telemetry only)           │
         └─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  CustomLossOutput.build()       │
         │  Return metrics                 │
└─────────────┬───────────────────┘
                       │
                       ▼
         ┌─────────────────────────────────┐
         │  Return CustomLossOutput        │
         │  No gradients for optim_step    │
         │  NO TRAINING HAPPENED!          │
         └─────────────────────────────────┘
```

---

## 5. Type System Comparison

### 5.1 Python Types

#### Datum
```python
# File: tinker/types/datum.py
class Datum(StrictBase):
    loss_fn_inputs: LossFnInputs  # Dict[str, TensorData]
    model_input: ModelInput

    @model_validator(mode="before")
    @classmethod
    def convert_tensors(cls, data: Any) -> Any:
        """Convert torch.Tensor and numpy arrays to TensorData."""
        # Automatically converts:
        # - torch.Tensor → TensorData.from_torch()
        # - np.ndarray → TensorData.from_numpy()
        # - list → TensorData (with dtype inference)
```

**Key Feature:** Automatic tensor conversion in constructor

#### TensorData
```python
# Inferred from usage
class TensorData:
    data: List[float]  # Flattened data
    dtype: str         # "float32", "int64", etc.
    shape: List[int]   # Tensor shape

    @staticmethod
    def from_torch(tensor: torch.Tensor) -> TensorData:
        return TensorData(
            data=tensor.flatten().tolist(),
            dtype=str(tensor.dtype),
            shape=list(tensor.shape)
        )
```

#### ForwardBackwardOutput
```python
# File: tinker/types/forward_backward_output.py
class ForwardBackwardOutput(BaseModel):
    loss_fn_output_type: str
    loss_fn_outputs: List[LossFnOutput]  # Contains logprobs
    metrics: Dict[str, float]
```

**Critical:** This is the **same type** returned by both:
- `forward_backward()` - normal training
- `forward_backward_custom()` - custom loss training

**Why it matters:**
```python
# Both work with optim_step:
result1 = training_client.forward_backward(data, "cross_entropy").result()
result2 = training_client.forward_backward_custom(data, custom_loss).result()

# Both can be followed by:
optim_result = training_client.optim_step(adam_params).result()
```

### 5.2 Elixir Types

#### Datum
```elixir
# File: tinkex/lib/tinkex/types/datum.ex
defmodule Tinkex.Types.Datum do
  @enforce_keys [:model_input]
  @derive {Jason.Encoder, only: [:model_input, :loss_fn_inputs]}
  defstruct [:model_input, loss_fn_inputs: %{}]

  @type t :: %__MODULE__{
          model_input: ModelInput.t(),
          loss_fn_inputs: %{String.t() => TensorData.t()}
        }

  def new(attrs) do
    %__MODULE__{
      model_input: attrs[:model_input],
      loss_fn_inputs: convert_loss_fn_inputs(attrs[:loss_fn_inputs] || %{})
    }
  end

  defp convert_loss_fn_inputs(inputs) do
    Map.new(inputs, fn {key, value} ->
      {to_string(key), maybe_convert_tensor(value)}
    end)
  end

  defp maybe_convert_tensor(%Nx.Tensor{} = tensor) do
    TensorData.from_nx(tensor)
  end
end
```

**Key Feature:** Similar auto-conversion, but for Nx tensors

#### CustomLossOutput
```elixir
# File: tinkex/lib/tinkex/types/custom_loss_output.ex
defmodule Tinkex.Types.CustomLossOutput do
  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizer_total,
    :total_grad_norm,
    regularizers: %{}
  ]

  @type base_loss_metrics :: %{
          value: float(),
          grad_norm: float() | nil,
          custom: %{String.t() => number()}
        }

  @type t :: %__MODULE__{
          loss_total: float(),
          base_loss: base_loss_metrics() | nil,
          regularizers: %{String.t() => RegularizerOutput.t()},
          regularizer_total: float() | nil,
          total_grad_norm: float() | nil
        }
end
```

**Critical Difference:** This is a **completely different type** from `ForwardBackwardOutput`

#### ForwardBackwardOutput
```elixir
# Inferred from usage in training_client.ex
defmodule Tinkex.Types.ForwardBackwardOutput do
  @type t :: %__MODULE__{
          loss_fn_output_type: String.t(),
          loss_fn_outputs: [map()],
          metrics: %{String.t() => float()}
        }
end
```

**The Problem:**
```elixir
# This works:
{:ok, task} = TrainingClient.forward_backward(client, data, :cross_entropy)
{:ok, result1} = Task.await(task)  # ForwardBackwardOutput
{:ok, optim_task} = TrainingClient.optim_step(client, adam_params)

# This does NOT work:
{:ok, task} = TrainingClient.forward_backward_custom(client, data, custom_loss)
{:ok, result2} = Task.await(task)  # CustomLossOutput - different type!
# optim_step would have no gradients to apply
```

### 5.3 Loss Function Types

#### Python
```python
CustomLossFnV1 = Callable[
    [List[types.Datum], List[Any]],  # (data, logprobs_list)
    Tuple[Any, Dict[str, float]]     # → (loss, metrics)
]

# Example:
def my_loss(data: List[Datum], logprobs: List[torch.Tensor]) -> Tuple[torch.Tensor, Dict]:
    # logprobs[0] is tensor for datum[0]
    # logprobs[1] is tensor for datum[1]
    # ...
    total_loss = sum(compute_loss(lp) for lp in logprobs)
    return total_loss, {"custom_metric": 1.23}
```

#### Elixir
```elixir
@type loss_fn :: (
  list(Datum.t()),
  Nx.Tensor.t()  # Single flattened tensor!
) -> {Nx.Tensor.t(), map()}

# Example:
def my_loss(data, logprobs) do
  # logprobs is a SINGLE tensor with all data concatenated
  # Cannot easily match to individual datums!
  loss = Nx.mean(logprobs)
  {loss, %{"custom_metric" => 1.23}}
end
```

---

## 6. TDD Implementation Plan

### 6.1 Test-Driven Development Strategy

**Principle:** Write tests first, then implement to make tests pass.

### 6.2 Phase 1: Core Infrastructure Tests

#### Test 1: Gradient Extraction from Forward Pass
```elixir
# File: test/tinkex/training/custom_loss/gradient_extraction_test.exs
defmodule Tinkex.Training.CustomLoss.GradientExtractionTest do
  use ExUnit.Case, async: false

  describe "extract_gradients_from_logprobs/2" do
    test "converts logprobs to Nx tensors with gradient tracking" do
      # Given: Forward pass output with logprobs
      forward_output = %ForwardBackwardOutput{
        loss_fn_outputs: [
          %{"logprobs" => %{"data" => [1.0, 2.0, 3.0], "shape" => [3], "dtype" => "float32"}},
          %{"logprobs" => %{"data" => [4.0, 5.0], "shape" => [2], "dtype" => "float32"}}
        ]
      }

      # When: Extract and prepare for gradient computation
      result = CustomLoss.extract_gradients_from_logprobs(forward_output)

      # Then: Should return list of Nx tensors
      assert {:ok, tensors} = result
      assert length(tensors) == 2
      assert Nx.to_flat_list(Enum.at(tensors, 0)) == [1.0, 2.0, 3.0]
      assert Nx.to_flat_list(Enum.at(tensors, 1)) == [4.0, 5.0]
    end

    test "preserves tensor shapes from forward pass" do
      forward_output = %ForwardBackwardOutput{
        loss_fn_outputs: [
          %{"logprobs" => %{"data" => [1.0, 2.0, 3.0, 4.0], "shape" => [2, 2], "dtype" => "float32"}}
        ]
      }

      {:ok, [tensor]} = CustomLoss.extract_gradients_from_logprobs(forward_output)

      assert Nx.shape(tensor) == {2, 2}
    end
  end
end
```

#### Test 2: Custom Loss Function Execution
```elixir
# File: test/tinkex/training/custom_loss/loss_execution_test.exs
defmodule Tinkex.Training.CustomLoss.LossExecutionTest do
  use ExUnit.Case, async: false

  describe "execute_custom_loss/3" do
    test "calls user function with data and logprobs" do
      data = [%Datum{model_input: ..., loss_fn_inputs: ...}]
      logprobs = [Nx.tensor([1.0, 2.0, 3.0])]

      loss_fn = fn received_data, received_logprobs ->
        assert received_data == data
        assert length(received_logprobs) == 1
        {Nx.tensor(2.5), %{"custom" => 1.0}}
      end

      result = CustomLoss.execute_custom_loss(data, logprobs, loss_fn)

      assert {:ok, %{loss: loss, metrics: metrics}} = result
      assert Nx.to_number(loss) == 2.5
      assert metrics == %{"custom" => 1.0}
    end

    test "validates loss function returns correct format" do
      loss_fn = fn _data, _logprobs ->
        # Invalid return - missing metrics
        Nx.tensor(1.0)
      end

      result = CustomLoss.execute_custom_loss([], [], loss_fn)

      assert {:error, %Error{type: :validation}} = result
    end
  end
end
```

#### Test 3: Gradient Computation with Nx
```elixir
# File: test/tinkex/training/custom_loss/gradient_computation_test.exs
defmodule Tinkex.Training.CustomLoss.GradientComputationTest do
  use ExUnit.Case, async: false

  describe "compute_gradients/2" do
    test "computes gradients using Nx.grad" do
      logprobs = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])

      loss_fn = fn lp ->
        Nx.sum(Nx.pow(lp, 2))
      end

      gradients = CustomLoss.compute_gradients(loss_fn, logprobs)

      # Gradient of sum(x^2) is 2x
      expected = Nx.multiply(logprobs, 2)
      assert Nx.all_close(gradients, expected)
    end

    test "handles multiple tensors" do
      logprobs_list = [
        Nx.tensor([1.0, 2.0]),
        Nx.tensor([3.0, 4.0, 5.0])
      ]

      loss_fn = fn [lp1, lp2] ->
        Nx.add(Nx.sum(lp1), Nx.sum(lp2))
      end

      gradients = CustomLoss.compute_gradients(loss_fn, logprobs_list)

      assert length(gradients) == 2
      # Gradient of sum is all ones
      assert Nx.to_flat_list(Enum.at(gradients, 0)) == [1.0, 1.0]
      assert Nx.to_flat_list(Enum.at(gradients, 1)) == [1.0, 1.0, 1.0]
    end
  end
end
```

#### Test 4: Synthetic Dataset Construction
```elixir
# File: test/tinkex/training/custom_loss/synthetic_dataset_test.exs
defmodule Tinkex.Training.CustomLoss.SyntheticDatasetTest do
  use ExUnit.Case, async: false

  describe "build_linear_loss_data/2" do
    test "creates Datum with negative gradients as weights" do
      original_data = [
        %Datum{
          model_input: %ModelInput{data: [1, 2, 3]},
          loss_fn_inputs: %{"target_tokens" => %TensorData{data: [10, 20, 30]}}
        }
      ]

      gradients = [Nx.tensor([0.5, 0.3, 0.1])]

      result = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(result) == 1
      datum = Enum.at(result, 0)

      # Should preserve model_input
      assert datum.model_input == %ModelInput{data: [1, 2, 3]}

      # Should have target_tokens and weights
      assert Map.has_key?(datum.loss_fn_inputs, "target_tokens")
      assert Map.has_key?(datum.loss_fn_inputs, "weights")

      # Weights should be negative gradients
      weights = datum.loss_fn_inputs["weights"]
      assert weights.data == [-0.5, -0.3, -0.1]
    end

    test "preserves target_tokens from original data" do
      original = [
        %Datum{
          model_input: %ModelInput{data: [1]},
          loss_fn_inputs: %{
            "target_tokens" => %TensorData{data: [99]},
            "other_field" => %TensorData{data: [88]}
          }
        }
      ]

      gradients = [Nx.tensor([1.0])]

      [result_datum] = CustomLoss.build_linear_loss_data(original, gradients)

      # Should only have target_tokens and weights
      assert Map.keys(result_datum.loss_fn_inputs) |> Enum.sort() == ["target_tokens", "weights"]
      assert result_datum.loss_fn_inputs["target_tokens"].data == [99]
    end
  end
end
```

### 6.3 Phase 2: Integration Tests

#### Test 5: End-to-End Custom Loss Training
```elixir
# File: test/tinkex/training/custom_loss/integration_test.exs
defmodule Tinkex.Training.CustomLoss.IntegrationTest do
  use ExUnit.Case, async: false

  setup do
    # Start service client and create training client
    {:ok, service} = Tinkex.ServiceClient.start_link(...)
    {:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service, ...)

    on_exit(fn ->
      Tinkex.TrainingClient.unload_model(training)
    end)

    %{training: training}
  end

  describe "forward_backward_custom/4" do
    test "actually trains the model", %{training: training} do
      # Prepare training data
      data = [
        %Datum{
          model_input: ModelInput.from_ints([1, 2, 3, 4]),
          loss_fn_inputs: %{"target_tokens" => TensorData.from_list([2, 3, 4, 5])}
        }
      ]

      # Custom loss function (simple L2 loss)
      custom_loss_fn = fn _data, logprobs_list ->
        loss = logprobs_list
               |> Enum.map(&Nx.sum(Nx.pow(&1, 2)))
               |> Enum.reduce(&Nx.add/2)

        {loss, %{"l2_loss" => Nx.to_number(loss)}}
      end

      # Execute custom loss training
      {:ok, task} = TrainingClient.forward_backward_custom(
        training,
        data,
        custom_loss_fn
      )

      # Should return ForwardBackwardOutput (not CustomLossOutput!)
      assert {:ok, %ForwardBackwardOutput{} = fwdbwd_result} = Task.await(task)

      # Should have custom metrics
      assert Map.has_key?(fwdbwd_result.metrics, "l2_loss")

      # Should be usable with optim_step
      {:ok, optim_task} = TrainingClient.optim_step(
        training,
        %AdamParams{learning_rate: 1.0e-4}
      )

      assert {:ok, %OptimStepResponse{}} = Task.await(optim_task)

      # Verify model was actually updated
      # (Would need to check weights or run inference to confirm)
    end

    test "works with regularizers", %{training: training} do
      data = [...]

      base_loss = fn _data, logprobs ->
        {Nx.mean(logprobs), %{}}
      end

      l1_regularizer = %RegularizerSpec{
        fn: fn _data, logprobs -> {Nx.sum(Nx.abs(logprobs)), %{}} end,
        weight: 0.01,
        name: "l1"
      }

      {:ok, task} = TrainingClient.forward_backward_custom(
        training,
        data,
        base_loss,
        regularizers: [l1_regularizer]
      )

      assert {:ok, %ForwardBackwardOutput{} = result} = Task.await(task)

      # Should have combined loss from base + regularizer
      # Metrics should include regularizer contributions
    end
  end
end
```

#### Test 6: Metric Merging
```elixir
# File: test/tinkex/training/custom_loss/metric_merging_test.exs
defmodule Tinkex.Training.CustomLoss.MetricMergingTest do
  use ExUnit.Case, async: false

  describe "merge_custom_metrics/2" do
    test "merges user metrics into server response" do
      server_result = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [...],
        metrics: %{
          "loss" => 2.5,
          "perplexity" => 12.18
        }
      }

      custom_metrics = %{
        "custom_loss" => 3.14,
        "custom_metric" => 2.71
      }

      merged = CustomLoss.merge_custom_metrics(server_result, custom_metrics)

      assert merged.metrics == %{
        "loss" => 2.5,
        "perplexity" => 12.18,
        "custom_loss" => 3.14,
        "custom_metric" => 2.71
      }
    end

    test "custom metrics override server metrics on conflict" do
      server_result = %ForwardBackwardOutput{
        metrics: %{"loss" => 1.0}
      }

      custom_metrics = %{"loss" => 2.0}

      merged = CustomLoss.merge_custom_metrics(server_result, custom_metrics)

      assert merged.metrics["loss"] == 2.0
    end
  end
end
```

### 6.4 Phase 3: Implementation Steps

#### Step 1: Create CustomLoss Module
```elixir
# File: lib/tinkex/training/custom_loss.ex
defmodule Tinkex.Training.CustomLoss do
  @moduledoc """
  Custom loss training implementation that mirrors Python SDK behavior.

  Key differences from Regularizer.Pipeline:
  - Actually trains the model (sends gradients to server)
  - Returns ForwardBackwardOutput (compatible with optim_step)
  - Preserves per-datum tensor structure
  """

  alias Tinkex.Types.{Datum, ForwardBackwardOutput, TensorData}

  @doc """
  Extract logprobs from forward pass output as list of Nx tensors.

  Preserves per-datum structure (unlike current flatten approach).
  """
  @spec extract_gradients_from_logprobs(ForwardBackwardOutput.t()) ::
          {:ok, [Nx.Tensor.t()]} | {:error, term()}
  def extract_gradients_from_logprobs(forward_output) do
    # Implementation here
  end

  @doc """
  Execute custom loss function.

  Similar to Python's CustomLossFnV1 signature.
  """
  @spec execute_custom_loss(
          [Datum.t()],
          [Nx.Tensor.t()],
          loss_fn :: function()
        ) :: {:ok, %{loss: Nx.Tensor.t(), metrics: map()}} | {:error, term()}
  def execute_custom_loss(data, logprobs_list, loss_fn) do
    # Implementation here
  end

  @doc """
  Compute gradients using Nx.grad.

  Wraps loss function to enable gradient computation.
  """
  @spec compute_gradients(
          loss_fn :: (Nx.Tensor.t() | [Nx.Tensor.t()] -> Nx.Tensor.t()),
          Nx.Tensor.t() | [Nx.Tensor.t()]
        ) :: Nx.Tensor.t() | [Nx.Tensor.t()]
  def compute_gradients(loss_fn, logprobs) do
    # Implementation here
  end

  @doc """
  Build synthetic dataset with gradients as weights.

  Mirrors Python's linear_loss_data construction.
  """
  @spec build_linear_loss_data([Datum.t()], [Nx.Tensor.t()]) :: [Datum.t()]
  def build_linear_loss_data(original_data, gradients) do
    # Implementation here
  end

  @doc """
  Merge custom metrics into server's ForwardBackwardOutput.
  """
  @spec merge_custom_metrics(ForwardBackwardOutput.t(), map()) ::
          ForwardBackwardOutput.t()
  def merge_custom_metrics(server_result, custom_metrics) do
    # Implementation here
  end
end
```

#### Step 2: Update TrainingClient.handle_call
```elixir
# File: lib/tinkex/training_client.ex

@impl true
def handle_call({:forward_backward_custom, data, loss_fn, opts}, from, state) do
  start_background_task(
    fn ->
      reply =
        try do
          # NEW IMPLEMENTATION:
          # 1. Forward pass
          case do_forward_for_custom_loss(data, opts, state) do
            {:ok, forward_output} ->
              # 2. Extract logprobs as structured tensors
              {:ok, logprobs_list} = CustomLoss.extract_gradients_from_logprobs(forward_output)

              # 3. Execute user loss function
              {:ok, %{loss: loss, metrics: custom_metrics}} =
                CustomLoss.execute_custom_loss(data, logprobs_list, loss_fn)

              # 4. Compute gradients
              gradients = CustomLoss.compute_gradients(
                fn logprobs -> {loss_tensor, _} = loss_fn.(data, logprobs); loss_tensor end,
                logprobs_list
              )

              # 5. Build synthetic dataset
              linear_loss_data = CustomLoss.build_linear_loss_data(data, gradients)

              # 6. Send to server (THIS IS THE KEY STEP!)
              chunks = chunk_data(linear_loss_data)
              {seq_ids, _} = allocate_request_ids(length(chunks), state.request_id_counter)

              # Send forward_backward requests
              send_result = send_all_forward_backward_chunks(chunks, seq_ids, state)

              case send_result do
                {:ok, server_output} ->
                  # 7. Merge metrics
                  final_output = CustomLoss.merge_custom_metrics(server_output, custom_metrics)
                  {:ok, final_output}

                {:error, _} = error ->
                  error
              end

            {:error, _} = error ->
              error
          end
        rescue
          e -> {:error, Error.new(:request_failed, ...)}
        end

      safe_reply(from, reply)
    end,
    from
  )

  {:noreply, state}
end
```

#### Step 3: Fix do_forward_for_custom_loss
```elixir
# Current implementation flattens logprobs - need to preserve structure

defp do_forward_for_custom_loss(data, opts, state) do
  chunks = chunk_data(data)
  {seq_ids, _} = allocate_request_ids(length(chunks), state.request_id_counter)

  # ... same send/poll logic ...

  case await_forward_results_for_custom_loss(polling_tasks, state.future_module) do
    {:ok, outputs} ->
      # NEW: Return full ForwardBackwardOutput (don't extract/flatten)
      combined = Combiner.combine_forward_backward_results(outputs)
      {:ok, combined}

    {:error, _} = error ->
      error
  end
end
```

#### Step 4: Implement Nx Gradient Computation
```elixir
# File: lib/tinkex/training/custom_loss.ex

def compute_gradients(loss_fn, logprobs_list) when is_list(logprobs_list) do
  # Wrap loss function for Nx.grad
  grad_fn = fn logprobs ->
    loss_fn.(logprobs)
  end

  # Compute gradients for each tensor
  Enum.map(logprobs_list, fn logprobs ->
    single_grad_fn = Nx.Defn.grad(fn lp -> grad_fn.([lp]) end)
    single_grad_fn.(logprobs)
  end)
end
```

#### Step 5: Implement Synthetic Dataset Builder
```elixir
def build_linear_loss_data(original_data, gradients) do
  Enum.zip(original_data, gradients)
  |> Enum.map(fn {datum, grad_tensor} ->
    # Extract target_tokens from original
    target_tokens = datum.loss_fn_inputs["target_tokens"]

    # Create weights from negative gradient
    weights = TensorData.from_nx(Nx.negate(grad_tensor))

    # Build new Datum
    %Datum{
      model_input: datum.model_input,
      loss_fn_inputs: %{
        "target_tokens" => target_tokens,
        "weights" => weights
      }
    }
  end)
end
```

### 6.5 Phase 4: API Compatibility

#### Update Type Specs
```elixir
# File: lib/tinkex/training_client.ex

@doc """
Compute forward/backward pass with custom loss function.

NOW ACTUALLY TRAINS THE MODEL (matches Python SDK behavior).

Returns:
`{:ok, Task.t()}` that yields `{:ok, ForwardBackwardOutput.t()}` (changed!)
"""
@spec forward_backward_custom(
        t(),
        list(Datum.t()),
        loss_fn :: (list(Datum.t()), [Nx.Tensor.t()] -> {Nx.Tensor.t(), map()}),
        keyword()
      ) :: {:ok, Task.t()} | {:error, Error.t()}
def forward_backward_custom(client, data, loss_fn, opts \\ []) do
  # ... implementation ...
end
```

#### Backward Compatibility
```elixir
# Keep regularizer functionality separate

@spec forward_with_regularizers(
        t(),
        list(Datum.t()),
        loss_fn :: function(),
        keyword()
      ) :: {:ok, Task.t()} | {:error, Error.t()}
def forward_with_regularizers(client, data, loss_fn, opts \\ []) do
  # This is the OLD forward_backward_custom behavior
  # Returns CustomLossOutput for metrics/telemetry only
  # Does NOT train the model
end
```

### 6.6 Phase 5: Comprehensive Testing

#### Test Categories:
1. **Unit Tests** (as defined in 6.2)
2. **Integration Tests** (as defined in 6.3)
3. **Property Tests**
4. **Performance Tests**
5. **Compatibility Tests**

#### Property-Based Test Example:
```elixir
# File: test/tinkex/training/custom_loss/property_test.exs
defmodule Tinkex.Training.CustomLoss.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "gradient negation is reversible" do
    check all tensor_data <- tensor_generator() do
      tensor = Nx.tensor(tensor_data)
      negated = Nx.negate(tensor)
      restored = Nx.negate(negated)

      assert Nx.all_close(tensor, restored)
    end
  end

  property "synthetic dataset preserves data count" do
    check all data_count <- integer(1..100) do
      original_data = generate_data(data_count)
      gradients = Enum.map(original_data, fn _ -> Nx.tensor([1.0]) end)

      result = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(result) == data_count
    end
  end
end
```

---

## 7. Integration Considerations

### 7.1 Breaking Changes

**Current Users of forward_backward_custom:**
- Existing code expects `CustomLossOutput`
- Migration path needed

**Recommendation:**
1. Deprecate old `forward_backward_custom` → rename to `compute_custom_metrics`
2. Implement new `forward_backward_custom` with training
3. Add deprecation warnings for 2 releases
4. Remove old implementation

### 7.2 Server Compatibility

**Assumption:** Server already supports receiving gradients via `weights` field in `loss_fn_inputs`

**Verification needed:**
- Test that server accepts synthetic dataset format
- Confirm gradient application logic
- Validate loss computation with weights

### 7.3 Nx vs PyTorch Gradient Differences

| Aspect | PyTorch | Nx |
|--------|---------|-----|
| **API** | `.backward()`, `.grad` | `Nx.Defn.grad()` |
| **Execution** | Eager or graph | Defn compilation |
| **In-place** | Yes (`requires_grad_()`) | No (functional) |
| **Multiple outputs** | Supported | Need separate grad calls |

**Challenges:**
- Nx.grad returns gradients, doesn't store them
- Need to structure loss function properly for Nx.Defn
- May need JIT compilation for performance

### 7.4 Performance Considerations

**Python:** PyTorch is highly optimized for autograd
**Elixir:** Nx gradient computation may be slower

**Mitigations:**
1. Use Nx.Defn.jit for compilation
2. Batch gradient computations
3. Profile and optimize hot paths

### 7.5 Error Handling

**New Error Cases:**
1. Gradient computation fails
2. Loss function returns non-differentiable result
3. Shape mismatches in synthetic dataset
4. Server rejects gradient weights

**Error Messages:**
```elixir
defmodule Tinkex.Training.CustomLossError do
  defexception [:message, :type, :data]

  @type t :: %__MODULE__{
          message: String.t(),
          type: :gradient_computation_failed | :loss_non_differentiable | :shape_mismatch,
          data: map()
        }
end
```

---

## 8. Appendix: Code References

### 8.1 Python Files
- `tinker/src/tinker/lib/public_interfaces/training_client.py:330-412`
  - `forward_backward_custom()` and `forward_backward_custom_async()`
- `tinker/src/tinker/lib/api_future_impl.py:279-296`
  - `_CombinedAPIFuture` implementation
- `tinker/src/tinker/types/datum.py`
  - Automatic tensor conversion
- `tinker/src/tinker/types/forward_backward_output.py`
  - Output type definition

### 8.2 Elixir Files
- `tinkex/lib/tinkex/training_client.ex:360-421, 880-914, 1474-1555`
  - Current `forward_backward_custom()` implementation
- `tinkex/lib/tinkex/regularizer/pipeline.ex:82-148`
  - `Pipeline.compute()` - metrics-only computation
- `tinkex/lib/tinkex/types/custom_loss_output.ex`
  - Current output type (wrong for training)
- `tinkex/lib/tinkex/api/training.ex`
  - Training API endpoints

### 8.3 Key Implementation Differences Summary Table

| Component | Python | Elixir Current | Elixir Needed |
|-----------|--------|----------------|---------------|
| **Forward pass** | `forward_async(data, "cross_entropy")` | `send_forward_request(...)` | ✓ Same |
| **Logprobs extraction** | List of tensors per datum | Single flattened tensor | List of tensors |
| **Gradient tracking** | `requires_grad_(True)` | Not enabled | `Nx.Defn.grad()` setup |
| **Loss execution** | User fn returns (loss, metrics) | Same signature | ✓ Same |
| **Gradient computation** | `loss.backward()` | Not done | `Nx.Defn.grad()` call |
| **Gradient extraction** | `tensor.grad` attribute | N/A | Return from grad fn |
| **Synthetic dataset** | Build with -grad as weights | Not done | Implement |
| **Server call** | `forward_backward_async()` | **MISSING** | Add call |
| **Result merging** | `_CombinedAPIFuture` | Not done | Implement |
| **Return type** | `ForwardBackwardOutput` | `CustomLossOutput` | Change to `ForwardBackwardOutput` |
| **optim_step compat** | ✓ Yes | ✗ No | Fix |

---

## Conclusion

The Elixir SDK's `forward_backward_custom()` is **fundamentally incomplete**. It only computes metrics and gradient norms for telemetry, but **never actually trains the model** because it:

1. Never computes gradients for server consumption
2. Never builds synthetic dataset with gradient weights
3. Never calls `forward_backward` to send gradients to server
4. Returns wrong type (`CustomLossOutput` vs `ForwardBackwardOutput`)

**To fix this gap, the Elixir SDK must:**
1. Preserve per-datum logprobs structure (not flatten)
2. Use Nx.Defn.grad to compute gradients
3. Build synthetic dataset with negative gradients as weights
4. Call forward_backward with synthetic dataset
5. Merge custom metrics into server response
6. Return ForwardBackwardOutput (not CustomLossOutput)

This is a **high-priority fix** as custom loss training is a core feature for advanced ML workflows.
