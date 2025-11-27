# Training Persistence Implementation Specification

**Date:** 2025-11-26
**Status:** Complete Specification
**Target:** Elixir Tinkex SDK

## Overview

This document provides complete implementation specifications for closing the training persistence gap. All type signatures, function signatures, and implementation patterns are specified in detail.

---

## Phase 1: Fix LoadWeightsRequest Type (P0)

### File: `lib/tinkex/types/load_weights_request.ex`

**Changes Required:**

1. Change struct field name from `load_optimizer_state` to `optimizer`
2. Update @derive directive
3. Update type spec
4. Update constructor
5. Update documentation

**Complete Implementation:**

```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  Mirrors Python `tinker.types.LoadWeightsRequest`.

  ## Fields

  - `model_id` - The model/training run ID
  - `path` - Tinker URI for model weights (e.g., "tinker://run-id/weights/checkpoint-001")
  - `seq_id` - Sequence ID for request ordering (optional)
  - `optimizer` - Whether to also load optimizer state (default: false)
  - `type` - Request type, always "load_weights"

  ## Load Optimizer State

  When `optimizer` is true, the optimizer state (Adam moments, etc.) will be
  restored along with the model weights. This is useful when resuming training from a
  checkpoint to maintain training continuity.

  ## Wire Format

  ```json
  {
    "model_id": "run-123",
    "path": "tinker://run-123/weights/checkpoint-001",
    "seq_id": 1,
    "optimizer": true,
    "type": "load_weights"
  }
  ```
  """

  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :optimizer, :type]}
  defstruct [:model_id, :path, :seq_id, optimizer: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          optimizer: boolean(),
          type: String.t()
        }

  @doc """
  Create a new LoadWeightsRequest.

  ## Parameters

  - `model_id` - The model/training run ID
  - `path` - Tinker URI for model weights
  - `opts` - Optional keyword list:
    - `:seq_id` - Sequence ID for request ordering
    - `:optimizer` - Whether to load optimizer state (default: false)

  ## Examples

      iex> LoadWeightsRequest.new("run-123", "tinker://run-123/weights/001")
      %LoadWeightsRequest{model_id: "run-123", path: "tinker://run-123/weights/001", optimizer: false}

      iex> LoadWeightsRequest.new("run-123", "tinker://run-123/weights/001", optimizer: true)
      %LoadWeightsRequest{model_id: "run-123", path: "tinker://run-123/weights/001", optimizer: true}
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(model_id, path, opts \\ []) do
    %__MODULE__{
      model_id: model_id,
      path: path,
      seq_id: Keyword.get(opts, :seq_id),
      optimizer: Keyword.get(opts, :optimizer, false),
      type: "load_weights"
    }
  end
end
```

---

## Phase 2: Add TrainingClient.save_state/3

### File: `lib/tinkex/training_client.ex`

**Add Public Function:**

```elixir
@doc """
Save model weights to persistent storage as a checkpoint.

This method saves the current state of the model weights for later resumption
or transfer learning. The checkpoint can be loaded with `load_state/3` or
`load_state_with_optimizer/3`.

## Parameters

- `client` - TrainingClient pid
- `name` - Name for the checkpoint (will be saved as tinker://run-id/weights/{name})
- `opts` - Optional keyword list:
  - `:await_timeout` - Timeout for awaiting result (default: :infinity)
  - `:telemetry_metadata` - Additional telemetry metadata

## Returns

`{:ok, Task.t()}` that yields `{:ok, %SaveWeightsResponse{}}` or `{:error, %Error{}}`

## Examples

    {:ok, task} = TrainingClient.save_state(client, "checkpoint-001")
    {:ok, response} = Task.await(task)
    IO.puts("Saved to: #{response.path}")  # tinker://run-123/weights/checkpoint-001
"""
@spec save_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def save_state(client, name, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:save_state, name, opts}, :infinity)
   end)}
end
```

**Add GenServer Handler:**

```elixir
@impl true
def handle_call({:save_state, name, opts}, from, state) do
  seq_id = state.request_id_counter
  new_counter = seq_id + 1

  case send_save_state_request(name, seq_id, opts, state) do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, response} ->
      Task.start(fn ->
        reply =
          try do
            handle_save_state_response(response, state, opts)
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

**Add Request Builder:**

```elixir
defp send_save_state_request(name, seq_id, _opts, state) do
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
    {:ok, %{"request_id" => _} = future} ->
      {:ok, future}

    {:ok, %{request_id: _} = future} ->
      {:ok, future}

    {:ok, result} ->
      {:ok, result}

    {:error, %Error{} = error} ->
      {:error, error}

    other ->
      {:error, Error.new(:validation, "Invalid save_weights response: #{inspect(other)}")}
  end
end
```

**Add Response Handler:**

```elixir
defp handle_save_state_response(%{"request_id" => _} = future, state, opts) do
  poll_save_state_future(future, state, opts)
end

defp handle_save_state_response(%{request_id: _} = future, state, opts) do
  poll_save_state_future(future, state, opts)
end

defp handle_save_state_response(%{"path" => _} = result, _state, _opts) do
  {:ok, SaveWeightsResponse.from_json(result)}
end

defp handle_save_state_response(result, _state, _opts), do: {:ok, result}

defp poll_save_state_future(future, state, opts) do
  task =
    state.future_module.poll(
      future,
      poll_opts_with_type(state, opts, "SaveWeights")
    )

  unlink_task(task)

  case safe_await(state.future_module, task, await_timeout(opts)) do
    {:ok, result} -> {:ok, SaveWeightsResponse.from_json(result)}
    {:error, _} = error -> error
  end
end
```

**Import Required Types (add to aliases at top of file):**

```elixir
alias Tinkex.Types.{
  # ... existing types ...
  SaveWeightsRequest,
  SaveWeightsResponse
}
```

---

## Phase 3: Add TrainingClient.load_state/3

### File: `lib/tinkex/training_client.ex`

**Add Public Function:**

```elixir
@doc """
Load model weights from a checkpoint WITHOUT optimizer state.

Loads only the model weights, creating a fresh optimizer state. Useful for
transfer learning or when you want to restart training with new hyperparameters.

## Parameters

- `client` - TrainingClient pid
- `path` - Tinker URI for saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
- `opts` - Optional keyword list:
  - `:await_timeout` - Timeout for awaiting result (default: :infinity)
  - `:telemetry_metadata` - Additional telemetry metadata

## Returns

`{:ok, Task.t()}` that yields `{:ok, %LoadWeightsResponse{}}` or `{:error, %Error{}}`

## Examples

    {:ok, task} = TrainingClient.load_state(client, "tinker://run-123/weights/checkpoint-001")
    {:ok, response} = Task.await(task)
    # Continue training with loaded weights
"""
@spec load_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def load_state(client, path, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:load_state, path, false, opts}, :infinity)
   end)}
end
```

---

## Phase 4: Add TrainingClient.load_state_with_optimizer/3

**Add Public Function:**

```elixir
@doc """
Load model weights from a checkpoint WITH optimizer state.

Loads both model weights and optimizer state (Adam moments, etc.). This preserves
training dynamics and is essential for resuming training from a checkpoint with
the same convergence characteristics.

## Parameters

- `client` - TrainingClient pid
- `path` - Tinker URI for saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
- `opts` - Optional keyword list:
  - `:await_timeout` - Timeout for awaiting result (default: :infinity)
  - `:telemetry_metadata` - Additional telemetry metadata

## Returns

`{:ok, Task.t()}` that yields `{:ok, %LoadWeightsResponse{}}` or `{:error, %Error{}}`

## Examples

    # Resume training with full state
    {:ok, task} = TrainingClient.load_state_with_optimizer(
      client,
      "tinker://run-123/weights/checkpoint-001"
    )
    {:ok, response} = Task.await(task)
    # Continue training with restored optimizer momentum
"""
@spec load_state_with_optimizer(t(), String.t(), keyword()) ::
        {:ok, Task.t()} | {:error, Error.t()}
def load_state_with_optimizer(client, path, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:load_state, path, true, opts}, :infinity)
   end)}
end
```

**Add Shared GenServer Handler:**

```elixir
@impl true
def handle_call({:load_state, path, optimizer, opts}, from, state) do
  seq_id = state.request_id_counter
  new_counter = seq_id + 1

  case send_load_state_request(path, optimizer, seq_id, opts, state) do
    {:error, reason} ->
      {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

    {:ok, response} ->
      Task.start(fn ->
        reply =
          try do
            handle_load_state_response(response, state, opts)
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

**Add Request Builder:**

```elixir
defp send_load_state_request(path, optimizer, seq_id, _opts, state) do
  request = %LoadWeightsRequest{
    model_id: state.model_id,
    path: path,
    seq_id: seq_id,
    optimizer: optimizer  # ← Boolean flag
  }

  case state.weights_api.load_weights(request,
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
      {:error, Error.new(:validation, "Invalid load_weights response: #{inspect(other)}")}
  end
end
```

**Add Response Handler:**

```elixir
defp handle_load_state_response(%{"request_id" => _} = future, state, opts) do
  poll_load_state_future(future, state, opts)
end

defp handle_load_state_response(%{request_id: _} = future, state, opts) do
  poll_load_state_future(future, state, opts)
end

defp handle_load_state_response(%{"path" => _} = result, _state, _opts) do
  {:ok, LoadWeightsResponse.from_json(result)}
end

defp handle_load_state_response(result, _state, _opts), do: {:ok, result}

defp poll_load_state_future(future, state, opts) do
  task =
    state.future_module.poll(
      future,
      poll_opts_with_type(state, opts, "LoadWeights")
    )

  unlink_task(task)

  case safe_await(state.future_module, task, await_timeout(opts)) do
    {:ok, result} -> {:ok, LoadWeightsResponse.from_json(result)}
    {:error, _} = error -> error
  end
end
```

**Import Required Types:**

```elixir
alias Tinkex.Types.{
  # ... existing types ...
  LoadWeightsRequest,
  LoadWeightsResponse
}
```

---

## Phase 5: Add ServiceClient.create_training_client_from_state/3

### File: `lib/tinkex/service_client.ex`

**Add Public Function:**

```elixir
@doc """
Create a TrainingClient from a saved checkpoint.

Queries the checkpoint metadata to extract the base model and LoRA configuration,
creates a new TrainingClient with the same architecture, then loads the weights.

## Parameters

- `service_client` - ServiceClient pid
- `path` - Tinker URI for saved weights (e.g., "tinker://run-id/weights/checkpoint-001")
- `opts` - Optional keyword list:
  - `:user_metadata` - Metadata to attach to the new training run
  - `:load_optimizer` - Whether to load optimizer state (default: false)

## Returns

`{:ok, TrainingClient.t()}` or `{:error, term()}`

## Examples

    # Create client from checkpoint (weights only)
    {:ok, training_client} = ServiceClient.create_training_client_from_state(
      service,
      "tinker://run-123/weights/checkpoint-001"
    )

    # Create client with optimizer state
    {:ok, training_client} = ServiceClient.create_training_client_from_state(
      service,
      "tinker://run-123/weights/checkpoint-001",
      load_optimizer: true
    )
"""
@spec create_training_client_from_state(t(), String.t(), keyword()) ::
        {:ok, pid()} | {:error, term()}
def create_training_client_from_state(service_client, path, opts \\ []) do
  GenServer.call(service_client, {:create_training_client_from_state, path, opts})
end
```

**Add GenServer Handler:**

```elixir
@impl true
def handle_call({:create_training_client_from_state, path, opts}, _from, state) do
  # 1. Create REST client to query metadata
  rest_client = Tinkex.RestClient.new(state.session_id, state.config)

  case Tinkex.RestClient.get_weights_info_by_tinker_path(rest_client, path) do
    {:ok, weights_info} ->
      # 2. Create new training client with same architecture
      training_opts =
        opts
        |> Keyword.put(:base_model, weights_info.base_model)
        |> Keyword.put(:lora_config, %LoraConfig{rank: weights_info.lora_rank})

      case create_lora_training_client(self(), training_opts) do
        {:ok, training_client} ->
          # 3. Load weights into client
          load_fn =
            if Keyword.get(opts, :load_optimizer, false) do
              &Tinkex.TrainingClient.load_state_with_optimizer/2
            else
              &Tinkex.TrainingClient.load_state/2
            end

          case load_fn.(training_client, path) do
            {:ok, task} ->
              case Task.await(task, :infinity) do
                {:ok, _response} ->
                  {:reply, {:ok, training_client}, state}

                {:error, reason} ->
                  # Kill the client since load failed
                  Process.exit(training_client, :kill)
                  {:reply, {:error, reason}, state}
              end

            {:error, reason} ->
              Process.exit(training_client, :kill)
              {:reply, {:error, reason}, state}
          end

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end

    {:error, reason} ->
      {:reply, {:error, reason}, state}
  end
end
```

**Import Required Module:**

```elixir
alias Tinkex.Types.LoraConfig
```

---

## Summary of Changes

### Files to Modify

1. **lib/tinkex/types/load_weights_request.ex**
   - Change field name: `load_optimizer_state` → `optimizer`
   - Update documentation

2. **lib/tinkex/training_client.ex**
   - Add `save_state/3` public function
   - Add `load_state/3` public function
   - Add `load_state_with_optimizer/3` public function
   - Add GenServer handlers for all three
   - Add request builders
   - Add response handlers
   - Add type imports

3. **lib/tinkex/service_client.ex**
   - Add `create_training_client_from_state/3` public function
   - Add GenServer handler
   - Add LoraConfig import

### Total Lines of Code

- Type fix: ~20 lines changed
- TrainingClient additions: ~200 lines added
- ServiceClient additions: ~50 lines added
- **Total: ~270 lines**

### Estimated Effort

- Phase 1 (Type fix): 2 hours
- Phase 2 (save_state): 4 hours
- Phase 3 (load_state): 3 hours
- Phase 4 (load_state_with_optimizer): 1 hour (reuses Phase 3)
- Phase 5 (create_from_state): 4 hours
- Testing: 8 hours
- **Total: ~22 hours (3 days)**

---

## Testing Requirements

Each phase requires unit tests before proceeding to the next phase. See `06_test_plan.md` for complete test specifications.
