# Checkpoint Recovery Gap Analysis

**Date**: December 4, 2025
**Context**: Backend incident - "poisoned" jobs require manual restart from checkpoint

---

## The Problem

When a backend failure occurs, training jobs can become "poisoned" (corrupted). The current recovery model:

```
Backend Failure
      ↓
Job becomes "corrupted" (flag set server-side)
      ↓
User polls job status, sees corrupted=true
      ↓
User queries for last good checkpoint
      ↓
User manually creates new training client
      ↓
User loads checkpoint (with or without optimizer state)
      ↓
Training resumes
```

**Key Issue**: This is entirely manual. Users must:
1. Monitor for failures
2. Query status
3. Find checkpoints
4. Restart manually

---

## Current Python SDK Capabilities

### 1. Detecting Corrupted Jobs

```python
# Query training run status
rest_client = service_client.create_rest_client()
run = rest_client.get_training_run("run-id").result()

if run.corrupted:
    print("Job is poisoned!")
    print(f"Last checkpoint: {run.last_checkpoint.tinker_path}")
```

**TrainingRun Fields:**
- `corrupted: bool` - True if job failed
- `last_checkpoint: Checkpoint | None` - Last training checkpoint
- `last_sampler_checkpoint: Checkpoint | None` - Last sampler checkpoint

### 2. Checkpoint Discovery

```python
# List all checkpoints for a run
checkpoints = rest_client.list_checkpoints("run-id").result()
for cp in checkpoints.checkpoints:
    print(f"{cp.checkpoint_id}: {cp.tinker_path} ({cp.time})")

# Get specific checkpoint info
archive_url = rest_client.get_checkpoint_archive_url("run-id", "checkpoint-id").result()
```

### 3. Recovery Options

**Option A: Weights Only (Fresh Optimizer)**
```python
training_client = service_client.create_training_client_from_state(
    "tinker://run-id/weights/checkpoint-005"
)
# Optimizer state is reset - starts fresh
```

**Option B: Full State (Optimizer Preserved)**
```python
training_client = service_client.create_training_client_from_state_with_optimizer(
    "tinker://run-id/weights/checkpoint-005"
)
# Optimizer momentum/Adam state restored
```

---

## Current Elixir SDK Gaps

### Gap 1: Cannot Detect Corrupted Jobs

**Status**: ⚠️ Partial - Need to verify `corrupted` field parsing

```elixir
# Current Elixir
{:ok, run} = Tinkex.API.Rest.get_training_run(config, "run-id")

# Does run.corrupted exist and parse correctly?
# Need to verify TrainingRun.from_map/1 handles this
```

**Fix Required**: Ensure `TrainingRun` type includes and parses `corrupted` field

---

### Gap 2: Cannot Load State With Optimizer

**Status**: ❌ MISSING

```elixir
# Python equivalent
training_client = service_client.create_training_client_from_state_with_optimizer(path)

# Elixir - NOT AVAILABLE
# Only have:
Tinkex.TrainingClient.load_weights(client, path)  # Weights only, no optimizer
```

**Fix Required**: Add `load_weights_with_optimizer/2` function

```elixir
# In Tinkex.TrainingClient
def load_weights_with_optimizer(client, path) do
  request = %LoadWeightsRequest{
    model_id: client.model_id,
    path: path,
    optimizer: true,  # ← This parameter exists in the type
    seq_id: next_seq_id(client)
  }

  API.Weights.load_weights(request, client.config)
end
```

---

### Gap 3: No Recovery Orchestration

**Status**: ❌ NOT IMPLEMENTED

Neither Python nor Elixir SDK provides automated recovery. However, Elixir's OTP model is ideal for this:

**Proposed Architecture:**

```elixir
defmodule Tinkex.Recovery.Supervisor do
  use Supervisor

  def init(opts) do
    children = [
      {Tinkex.Recovery.Monitor, opts},
      {Tinkex.Recovery.Executor, opts}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule Tinkex.Recovery.Monitor do
  use GenServer

  # Periodically poll training run status
  # Detect corrupted jobs
  # Trigger recovery via Executor
end

defmodule Tinkex.Recovery.Executor do
  use GenServer

  # Receive recovery requests
  # Query last checkpoint
  # Create new training client from checkpoint
  # Resume training loop
  # Emit telemetry
end
```

---

## Recovery Policy Configuration

**Proposed Configuration Struct:**

```elixir
defmodule Tinkex.Recovery.Policy do
  defstruct [
    # Whether to auto-recover
    enabled: false,

    # Max recovery attempts
    max_attempts: 3,

    # Backoff between attempts
    backoff_ms: 5_000,
    max_backoff_ms: 60_000,

    # Checkpoint selection strategy
    checkpoint_strategy: :latest,  # :latest | :best_loss | :specific

    # Whether to restore optimizer state
    restore_optimizer: true,

    # Callback on recovery
    on_recovery: nil,  # fn(old_client, new_client, checkpoint) -> :ok

    # Callback on failure
    on_failure: nil    # fn(run_id, error) -> :ok
  ]
end
```

---

## Checkpoint Lifecycle Management Gaps

### Current State

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Save checkpoint | ✅ | ✅ | Parity |
| Load checkpoint (weights) | ✅ | ✅ | Parity |
| Load checkpoint (full) | ✅ | ❌ | **MISSING** |
| List checkpoints | ✅ | ✅ | Parity |
| Delete checkpoint | ✅ | ✅ | Parity |
| Publish/unpublish | ✅ | ✅ | Parity |
| Download archive | ✅ | ✅ | Parity |
| Checkpoint validation | ❌ | ❌ | Neither |
| Auto-checkpoint schedule | ❌ | ❌ | Neither |
| Retention policy | ❌ | ❌ | Neither |

### Missing from Both SDKs

1. **Checkpoint Validation**
   - Verify checkpoint integrity before load
   - Detect corrupted checkpoint files

2. **Auto-Checkpoint Scheduling**
   - Save every N steps
   - Save on epoch boundary
   - Save on loss improvement

3. **Retention Policies**
   - Keep last N checkpoints
   - Keep best M by metric
   - Auto-delete old checkpoints

---

## Integration with Broader Architecture

### From tinkerer/brainstorm/20251129/nsai_ir_specification/03_TRAINING_IR.md

The TrainingIR specification defines comprehensive checkpoint policies:

```elixir
defmodule TrainingIR.CheckpointPolicy do
  defstruct [
    strategy: :steps,      # :steps | :epoch | :best | :last | :all
    save_every: 100,       # Save every N steps/epochs
    keep_last: 5,          # Retention limit
    save_best: true,       # Track best model
    best_metric: "loss",   # Metric for best selection
    best_mode: :min,       # :min | :max
    format: :safetensors,  # :safetensors | :pytorch | :gguf
    push_to_hub: false     # Push to HuggingFace Hub
  ]
end
```

### From NSAI.Work Job Model

Jobs can specify retry policies:

```elixir
defmodule NSAI.Work.RetryPolicy do
  defstruct [
    max_attempts: 3,
    backoff_type: :exponential,
    initial_delay_ms: 1000,
    max_delay_ms: 60_000,
    retryable_errors: [:timeout, :backend_unavailable]
  ]
end
```

---

## Recommended Implementation Roadmap

### Phase 1: SDK Parity (Immediate)

1. **Verify TrainingRun.corrupted parsing**
   - Check `lib/tinkex/types/training_run.ex`
   - Ensure `from_map/1` handles `corrupted` field
   - Add test case

2. **Add load_weights_with_optimizer/2**
   - Modify `LoadWeightsRequest` if needed
   - Add function to `TrainingClient`
   - Add test case

3. **Add create_training_client_from_state_with_optimizer/3**
   - Combine existing functions
   - Test end-to-end recovery

### Phase 2: Recovery Layer (Short-term)

4. **Create Recovery.Policy struct**
   - Define configuration options
   - Add to Tinkex.Config

5. **Create Recovery.Monitor GenServer**
   - Poll training run status at intervals
   - Detect corrupted status
   - Emit telemetry events

6. **Create Recovery.Executor GenServer**
   - Handle recovery requests
   - Implement checkpoint selection
   - Create new training client
   - Support callbacks

### Phase 3: Integration (Medium-term)

7. **Integrate with NSAI.Work**
   - Submit training as jobs
   - Use job retry policies
   - Track via lineage

8. **Implement CheckpointPolicy from TrainingIR**
   - Auto-checkpoint scheduling
   - Retention management
   - Best model tracking

---

## Telemetry Events for Recovery

```elixir
# Proposed telemetry events
[:tinkex, :recovery, :detected]     # Corrupted job detected
[:tinkex, :recovery, :started]      # Recovery attempt started
[:tinkex, :recovery, :checkpoint_selected]  # Checkpoint chosen
[:tinkex, :recovery, :client_created]       # New client ready
[:tinkex, :recovery, :completed]    # Recovery successful
[:tinkex, :recovery, :failed]       # Recovery failed
[:tinkex, :recovery, :exhausted]    # Max attempts reached
```

---

## Example Recovery Flow

```elixir
# With automated recovery enabled
config = %Tinkex.Config{
  recovery: %Tinkex.Recovery.Policy{
    enabled: true,
    max_attempts: 3,
    restore_optimizer: true,
    on_recovery: fn _old, new, checkpoint ->
      Logger.info("Recovered from #{checkpoint.tinker_path}")
      :ok
    end
  }
}

# Training loop with automatic recovery
{:ok, client} = Tinkex.Client.create_training_client(config, base_model: "llama-3.2-1b")

# If job becomes corrupted during training...
# 1. Monitor detects corrupted=true
# 2. Executor queries last checkpoint
# 3. Executor creates new client with optimizer state
# 4. Callback notified
# 5. Training can resume

# User can also manually check and recover
{:ok, run} = Tinkex.API.Rest.get_training_run(config, run_id)
if run.corrupted do
  {:ok, new_client} = Tinkex.Recovery.recover_from_checkpoint(
    config,
    run.last_checkpoint.tinker_path,
    restore_optimizer: true
  )
end
```
