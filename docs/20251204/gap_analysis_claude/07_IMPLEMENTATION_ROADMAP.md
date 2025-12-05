# Implementation Roadmap

**Date**: December 4, 2025

---

## Overview

This roadmap addresses the gaps identified in the tinkex SDK analysis, prioritized by impact on production readiness.

---

## Phase 1: SDK Hardening (P0)

**Duration**: 1-2 days
**Goal**: Lock in existing recovery primitives and make them regression-proof

### 1.1 Regression Tests for Recovery Primitives

- `TrainingRun.from_map/1` parses `corrupted`
- `load_state_with_optimizer/3` sends `optimizer: true` and succeeds end-to-end
- `create_training_client_from_state_with_optimizer/3` rebuilds a client from a checkpoint

### 1.2 Timestamp Normalization

- Parse `Checkpoint.time` (and related fields) to `DateTime.t()` with graceful fallback
- Document serialization expectations for downstream consumers

### 1.3 Recovery Runbook

- Add docs for weights-only vs optimizer-aware recovery flows
- Include queue-state/backpressure guidance

---

## Phase 2: Recovery Automation (P1)

**Duration**: 3-5 days  
**Goal**: Ship an OTP-native recovery loop that restarts corrupted runs automatically

### 2.1 Recovery Policy
- Define `Tinkex.Recovery.Policy` (enabled flag, backoff, checkpoint strategy, restore_optimizer flag)
- Wire optional policy into `Tinkex.Config`

### 2.2 Recovery Monitor
- Poll `Rest.get_training_run/2` for monitored run_ids
- Emit telemetry on detection (`[:tinkex, :recovery, :detected]`)
- Dispatch recovery work to executor

### 2.3 Recovery Executor
- Select checkpoint (latest/best/custom)
- Recreate client via `create_training_client_from_state_with_optimizer/3`
- Emit telemetry for start/success/failure/exhausted

---

## Recovery Layer Design (for Phase 2)

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

  defp attempt_recovery(config, run_id, %{service_client: service} = info, policy, attempt)
       when attempt < policy.max_attempts do
    with {:ok, checkpoint} <- select_checkpoint(config, run_id, policy.checkpoint_strategy),
         {:ok, new_client} <- create_recovered_client(service, checkpoint, policy) do
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

  defp create_recovered_client(service, checkpoint, policy) do
    if policy.restore_optimizer do
      Tinkex.ServiceClient.create_training_client_from_state_with_optimizer(
        service,
        checkpoint.tinker_path
      )
    else
      Tinkex.ServiceClient.create_training_client_from_state(
        service,
        checkpoint.tinker_path
      )
    end
  end
end
```

---

## Phase 3: Integration (P2)

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
├── Day 1-2: Phase 1 (P0 - Hardening)
│   ├── Regression tests for corrupted + optimizer restore
│   ├── Timestamp normalization
│   └── Recovery runbook/docs
│
├── Day 3-5: Phase 2 (P1 - Recovery Automation)
│   ├── Recovery.Policy struct
│   ├── Recovery.Monitor GenServer
│   ├── Recovery.Executor GenServer
│   └── Recovery telemetry

Week 2-3:
└── Stabilize recovery
    ├── Integration tests
    ├── Backpressure/queue-state alerts
    └── Tune backoff + selection strategy

Week 4+:
└── Phase 3 (P2 - Integration)
    ├── NSAI.Work integration
    ├── Crucible backend adapter
    └── Documentation
```

---

## Testing Strategy

### Unit Tests

```elixir
# test/tinkex/training_client_test.exs
describe "load_state_with_optimizer/3" do
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
