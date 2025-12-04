# Implementation Roadmap

**Date**: December 4, 2025

---

## Overview

This roadmap addresses the gaps identified in the tinkex SDK analysis, prioritized by impact on production readiness.

---

## Phase 1: Critical SDK Parity (P0)

**Duration**: 1-2 days
**Goal**: Enable full training state recovery

### 1.1 Verify TrainingRun.corrupted Parsing

**File**: `lib/tinkex/types/training_run.ex`

**Task**: Ensure `corrupted` field is parsed from API response

```elixir
# Verify this exists in the struct
defstruct [
  :training_run_id,
  :base_model,
  :model_owner,
  :is_lora,
  :corrupted,  # ← Must be here
  :lora_rank,
  :last_request_time,
  :last_checkpoint,
  :last_sampler_checkpoint,
  :user_metadata
]

# Verify from_map/1 parses it
def from_map(map) do
  %__MODULE__{
    training_run_id: map["training_run_id"],
    corrupted: map["corrupted"] || false,  # ← Must parse
    # ...
  }
end
```

**Test**:
```elixir
test "parses corrupted field" do
  map = %{"training_run_id" => "run-1", "corrupted" => true}
  run = TrainingRun.from_map(map)
  assert run.corrupted == true
end
```

---

### 1.2 Add load_weights_with_optimizer/2

**File**: `lib/tinkex/training_client.ex`

**Task**: Add function to load weights with optimizer state

```elixir
@doc """
Load model weights AND optimizer state from a checkpoint.

This restores the exact training state, including Adam momentum.
Use this for exact resumption of training.
"""
@spec load_weights_with_optimizer(t(), String.t()) :: :ok | {:error, Error.t()}
def load_weights_with_optimizer(client, path) do
  request = %LoadWeightsRequest{
    model_id: client.model_id,
    path: path,
    optimizer: true,
    seq_id: next_seq_id(client)
  }

  case API.Weights.load_weights(request, client.config) do
    {:ok, _response} -> :ok
    error -> error
  end
end
```

**Test**:
```elixir
test "load_weights_with_optimizer sends optimizer: true" do
  # Mock or integration test
end
```

---

### 1.3 Add create_training_client_from_state_with_optimizer/3

**File**: `lib/tinkex/client.ex`

**Task**: Add factory function for full state recovery

```elixir
@doc """
Create a training client from a saved checkpoint, restoring optimizer state.

This enables exact resumption of training from any checkpoint.
"""
@spec create_training_client_from_state_with_optimizer(Config.t(), String.t(), keyword()) ::
        {:ok, TrainingClient.t()} | {:error, Error.t()}
def create_training_client_from_state_with_optimizer(config, path, opts \\ []) do
  with {:ok, info} <- API.Rest.get_weights_info_by_tinker_path(config, path),
       {:ok, client} <- create_training_client(config,
         base_model: info.base_model,
         lora_rank: info.lora_rank,
         user_metadata: opts[:user_metadata]
       ),
       :ok <- TrainingClient.load_weights_with_optimizer(client, path) do
    {:ok, client}
  end
end
```

---

## Phase 2: High Priority Features (P1)

**Duration**: 3-5 days
**Goal**: Complete API parity for common workflows

### 2.1 Add compute_logprobs/2

**File**: `lib/tinkex/sampling_client.ex`

```elixir
@doc """
Compute log probabilities for prompt tokens.

Returns the logprob for each token in the prompt.
"""
@spec compute_logprobs(t(), ModelInput.t()) :: {:ok, [float() | nil]} | {:error, Error.t()}
def compute_logprobs(client, prompt) do
  request = %SampleRequest{
    sampling_session_id: client.sampling_session_id,
    prompt: prompt,
    num_samples: 1,
    sampling_params: %SamplingParams{max_tokens: 1},
    prompt_logprobs: true,
    seq_id: next_seq_id(client)
  }

  case sample(client, request) do
    {:ok, %{prompt_logprobs: logprobs}} -> {:ok, logprobs}
    {:ok, _} -> {:error, %Error{type: :validation, message: "No logprobs returned"}}
    error -> error
  end
end
```

---

### 2.2 Add Missing Response Types

**Files**: `lib/tinkex/types/`

Create the following type modules:

```elixir
# lib/tinkex/types/get_session_response.ex
defmodule Tinkex.Types.GetSessionResponse do
  defstruct [:training_run_ids, :sampler_ids]

  def from_map(map) do
    %__MODULE__{
      training_run_ids: map["training_run_ids"] || [],
      sampler_ids: map["sampler_ids"] || []
    }
  end
end

# lib/tinkex/types/list_sessions_response.ex
defmodule Tinkex.Types.ListSessionsResponse do
  defstruct [:sessions, :cursor]

  def from_map(map) do
    %__MODULE__{
      sessions: Enum.map(map["sessions"] || [], &SessionInfo.from_map/1),
      cursor: Cursor.from_map(map["cursor"])
    }
  end
end

# lib/tinkex/types/training_runs_response.ex
defmodule Tinkex.Types.TrainingRunsResponse do
  defstruct [:training_runs, :cursor]

  def from_map(map) do
    %__MODULE__{
      training_runs: Enum.map(map["training_runs"] || [], &TrainingRun.from_map/1),
      cursor: Cursor.from_map(map["cursor"])
    }
  end
end
```

---

### 2.3 Fix ImageChunk Type

**File**: `lib/tinkex/types/image_chunk.ex`

```elixir
defmodule Tinkex.Types.ImageChunk do
  @moduledoc """
  Image input chunk for multimodal models.
  """

  defstruct [
    :data,             # Base64-encoded image data
    :format,           # :png | :jpeg
    :height,           # Image height in pixels (REQUIRED)
    :width,            # Image width in pixels (REQUIRED)
    :tokens,           # Token count (REQUIRED)
    :expected_tokens,  # Expected token count (optional)
    type: "image"
  ]

  @type t :: %__MODULE__{
    data: String.t(),
    format: :png | :jpeg,
    height: non_neg_integer(),
    width: non_neg_integer(),
    tokens: non_neg_integer(),
    expected_tokens: non_neg_integer() | nil,
    type: String.t()
  }

  def to_map(%__MODULE__{} = chunk) do
    %{
      "data" => chunk.data,
      "format" => Atom.to_string(chunk.format),
      "height" => chunk.height,
      "width" => chunk.width,
      "tokens" => chunk.tokens,
      "expected_tokens" => chunk.expected_tokens,
      "type" => chunk.type
    }
  end
end
```

---

## Phase 3: Recovery Layer (P2)

**Duration**: 1-2 weeks
**Goal**: Automated checkpoint recovery

### 3.1 Recovery Policy Configuration

**File**: `lib/tinkex/recovery/policy.ex`

```elixir
defmodule Tinkex.Recovery.Policy do
  @moduledoc """
  Configuration for automatic recovery from failed training jobs.
  """

  defstruct [
    enabled: false,
    max_attempts: 3,
    backoff_ms: 5_000,
    max_backoff_ms: 60_000,
    checkpoint_strategy: :latest,
    restore_optimizer: true,
    poll_interval_ms: 30_000,
    on_recovery: nil,
    on_failure: nil
  ]

  @type checkpoint_strategy :: :latest | :best_loss | {:specific, String.t()}

  @type t :: %__MODULE__{
    enabled: boolean(),
    max_attempts: pos_integer(),
    backoff_ms: pos_integer(),
    max_backoff_ms: pos_integer(),
    checkpoint_strategy: checkpoint_strategy(),
    restore_optimizer: boolean(),
    poll_interval_ms: pos_integer(),
    on_recovery: (TrainingClient.t(), TrainingClient.t(), Checkpoint.t() -> :ok) | nil,
    on_failure: (String.t(), term() -> :ok) | nil
  }
end
```

---

### 3.2 Recovery Monitor GenServer

**File**: `lib/tinkex/recovery/monitor.ex`

```elixir
defmodule Tinkex.Recovery.Monitor do
  @moduledoc """
  Monitors training jobs and triggers recovery on failure.
  """
  use GenServer

  defstruct [:config, :policy, :monitored_runs, :executor]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def monitor_run(monitor, run_id, training_client) do
    GenServer.call(monitor, {:monitor, run_id, training_client})
  end

  def stop_monitoring(monitor, run_id) do
    GenServer.call(monitor, {:stop_monitoring, run_id})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      config: opts[:config],
      policy: opts[:policy] || %Tinkex.Recovery.Policy{},
      monitored_runs: %{},
      executor: opts[:executor]
    }

    if state.policy.enabled do
      schedule_poll(state.policy.poll_interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = poll_monitored_runs(state)
    schedule_poll(state.policy.poll_interval_ms)
    {:noreply, state}
  end

  defp poll_monitored_runs(state) do
    Enum.reduce(state.monitored_runs, state, fn {run_id, info}, acc ->
      case check_run_status(acc.config, run_id) do
        {:ok, %{corrupted: true}} ->
          trigger_recovery(acc, run_id, info)

        {:ok, _} ->
          acc

        {:error, _} ->
          acc
      end
    end)
  end

  defp trigger_recovery(state, run_id, info) do
    :telemetry.execute(
      [:tinkex, :recovery, :detected],
      %{},
      %{run_id: run_id}
    )

    GenServer.cast(state.executor, {:recover, run_id, info, state.policy})
    %{state | monitored_runs: Map.delete(state.monitored_runs, run_id)}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
```

---

### 3.3 Recovery Executor GenServer

**File**: `lib/tinkex/recovery/executor.ex`

```elixir
defmodule Tinkex.Recovery.Executor do
  @moduledoc """
  Executes recovery operations for failed training jobs.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    {:ok, %{config: opts[:config]}}
  end

  @impl true
  def handle_cast({:recover, run_id, info, policy}, state) do
    :telemetry.execute([:tinkex, :recovery, :started], %{}, %{run_id: run_id})

    result = attempt_recovery(state.config, run_id, info, policy, 0)

    case result do
      {:ok, new_client, checkpoint} ->
        :telemetry.execute([:tinkex, :recovery, :completed], %{}, %{
          run_id: run_id,
          checkpoint: checkpoint.tinker_path
        })

        if policy.on_recovery do
          policy.on_recovery.(info.client, new_client, checkpoint)
        end

      {:error, reason} ->
        :telemetry.execute([:tinkex, :recovery, :failed], %{}, %{
          run_id: run_id,
          reason: reason
        })

        if policy.on_failure do
          policy.on_failure.(run_id, reason)
        end
    end

    {:noreply, state}
  end

  defp attempt_recovery(config, run_id, info, policy, attempt) when attempt < policy.max_attempts do
    with {:ok, checkpoint} <- select_checkpoint(config, run_id, policy.checkpoint_strategy),
         {:ok, new_client} <- create_recovered_client(config, checkpoint, policy) do
      {:ok, new_client, checkpoint}
    else
      {:error, reason} ->
        backoff = min(policy.backoff_ms * :math.pow(2, attempt), policy.max_backoff_ms)
        :timer.sleep(round(backoff))
        attempt_recovery(config, run_id, info, policy, attempt + 1)
    end
  end

  defp attempt_recovery(_config, run_id, _info, _policy, _attempt) do
    {:error, :max_attempts_exceeded}
  end

  defp select_checkpoint(config, run_id, :latest) do
    case Tinkex.API.Rest.get_training_run(config, run_id) do
      {:ok, %{last_checkpoint: nil}} -> {:error, :no_checkpoint}
      {:ok, %{last_checkpoint: cp}} -> {:ok, cp}
      error -> error
    end
  end

  defp create_recovered_client(config, checkpoint, policy) do
    if policy.restore_optimizer do
      Tinkex.Client.create_training_client_from_state_with_optimizer(
        config,
        checkpoint.tinker_path
      )
    else
      Tinkex.Client.create_training_client_from_state(
        config,
        checkpoint.tinker_path
      )
    end
  end
end
```

---

## Phase 4: Integration (P3)

**Duration**: Ongoing
**Goal**: Connect to broader NSAI ecosystem

### 4.1 NSAI.Work Integration

Connect training jobs to the unified work model:

```elixir
# Submit training as NSAI.Work job
job = %NSAI.Work.Job{
  kind: :training_step,
  payload: %{
    base_model: "llama-3.2-1b",
    checkpoint_policy: %CheckpointPolicy{
      strategy: :steps,
      save_every: 100
    }
  },
  retry_policy: %RetryPolicy{
    max_attempts: 3,
    backoff_type: :exponential
  }
}
```

### 4.2 Crucible Backend Adapter

Implement `Crucible.Backend` behaviour for tinkex:

```elixir
defmodule Crucible.Backend.Tinkex do
  @behaviour Crucible.Backend

  def capabilities(_state) do
    %Capabilities{
      backend_id: :tinkex,
      provider: "tinkex",
      models: ["llama-3.2-1b", "llama-3.2-3b", "qwen/qwen2.5-7b"],
      supports_streaming: true,
      supports_training: true
    }
  end

  def complete(state, prompt) do
    # Translate Prompt IR to Tinkex format
    # Execute via sampling client
    # Return Completion IR
  end
end
```

---

## Timeline Summary

```
Week 1:
├── Day 1-2: Phase 1 (P0 - Critical)
│   ├── Verify TrainingRun.corrupted
│   ├── Add load_weights_with_optimizer
│   └── Add create_training_client_from_state_with_optimizer
│
├── Day 3-5: Phase 2 (P1 - High)
│   ├── Add compute_logprobs
│   ├── Add missing response types
│   └── Fix ImageChunk type

Week 2-3:
└── Phase 3 (P2 - Recovery)
    ├── Recovery.Policy struct
    ├── Recovery.Monitor GenServer
    ├── Recovery.Executor GenServer
    └── Integration tests

Week 4+:
└── Phase 4 (P3 - Integration)
    ├── NSAI.Work integration
    ├── Crucible backend adapter
    └── Documentation
```

---

## Testing Strategy

### Unit Tests

```elixir
# test/tinkex/training_client_test.exs
describe "load_weights_with_optimizer/2" do
  test "sends optimizer: true in request" do
    # Test request formation
  end

  test "returns :ok on success" do
    # Mock successful response
  end

  test "returns error on failure" do
    # Mock error response
  end
end
```

### Integration Tests

```elixir
# test/integration/recovery_test.exs
@tag :integration
describe "recovery flow" do
  test "detects corrupted job and recovers" do
    # Create training client
    # Simulate corruption
    # Verify recovery triggers
    # Verify new client works
  end
end
```

### Property Tests

```elixir
# test/tinkex/types/training_run_test.exs
property "from_map/1 handles all field combinations" do
  check all map <- training_run_map_generator() do
    run = TrainingRun.from_map(map)
    assert is_boolean(run.corrupted)
  end
end
```
