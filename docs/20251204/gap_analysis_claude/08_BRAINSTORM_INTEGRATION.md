# Integration with NSAI Brainstorm Architecture

**Date**: December 4, 2025
**Source**: `/home/home/p/g/North-Shore-AI/tinkerer/brainstorm/`

---

## Overview

This document maps tinkex gaps to the broader NSAI architecture defined in the brainstorm documentation. The gaps identified in tinkex align with architectural decisions being made at the platform level.

---

## Key Brainstorm Specifications

### 1. TrainingIR (November 29, 2025)

**File**: `20251129/nsai_ir_specification/03_TRAINING_IR.md`

Defines the training job specification that tinkex should implement:

```elixir
defmodule TrainingIR.TrainingJob do
  defstruct [
    :job_id,
    :model_spec,        # Base model configuration
    :adapter_config,    # LoRA/QLoRA/prefix tuning
    :learning_config,   # Optimizer, scheduler
    :dataset_spec,      # Training data
    :checkpoint_policy, # When/how to save
    :validation_spec,   # Evaluation during training
    :resource_spec,     # GPU, memory requirements
    :metadata
  ]
end
```

**Checkpoint Policy Spec:**
```elixir
defmodule TrainingIR.CheckpointPolicy do
  defstruct [
    strategy: :steps,           # :steps | :epoch | :best | :last | :all
    save_every: 100,            # Steps/epochs between saves
    keep_last: 5,               # Retention limit
    save_best: true,            # Track best model
    best_metric: "loss",        # Metric for best selection
    best_mode: :min,            # :min | :max
    format: :safetensors,       # :safetensors | :pytorch | :gguf | :onnx
    push_to_hub: false,         # Push to HuggingFace Hub
    hub_repo: nil               # Hub repository name
  ]
end
```

**Relevance to tinkex**: This spec should inform our checkpoint management implementation. Currently tinkex has basic save/load but no scheduling or retention policies.

---

### 2. NSAI.Work (November 29, 2025)

**File**: `20251129/nsai_ir_specification/01_NSAI_WORK_IR.md`

Defines the unified work model for job submission:

```elixir
defmodule NSAI.Work.Job do
  defstruct [
    :id,
    :kind,              # :training_step | :inference | :experiment_step
    :priority,          # :realtime | :interactive | :batch | :offline
    :status,            # :pending | :running | :completed | :failed
    :payload,           # Kind-specific data
    :resources,         # CPU, memory, GPU, timeout
    :constraints,       # Retry policy, dependencies
    :tenant_id,
    :metadata
  ]
end

defmodule NSAI.Work.RetryPolicy do
  defstruct [
    max_attempts: 3,
    backoff_type: :exponential,    # :exponential | :linear | :constant
    initial_delay_ms: 1000,
    max_delay_ms: 60_000,
    retryable_errors: [:timeout, :backend_unavailable, :capacity]
  ]
end
```

**Relevance to tinkex**: Training jobs submitted through tinkex should eventually be wrapped in NSAI.Work jobs, inheriting retry policies and resource tracking.

---

### 3. CrucibleIR.Backend (November 29, 2025)

**File**: `20251129/nsai_ir_specification/02_CRUCIBLE_BACKEND_IR.md`

Defines the backend contract that tinkex should implement:

```elixir
defmodule Crucible.Backend do
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, term()}
  @callback complete(state :: term(), prompt :: Prompt.t()) ::
              {:ok, Completion.t()} | {:error, term()}
  @callback stream(state :: term(), prompt :: Prompt.t()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback capabilities(state :: term()) :: Capabilities.t()
  @callback health_check(state :: term()) :: :ok | {:error, term()}
  @callback metrics(state :: term()) :: map()
end

defmodule Crucible.Backend.Capabilities do
  defstruct [
    :backend_id,
    :provider,
    :models,                    # List of supported models
    :supports_streaming,
    :supports_tools,
    :supports_vision,
    :supports_training,         # ← tinkex-specific
    :max_context_length,
    :costs
  ]
end
```

**Relevance to tinkex**: Implement `Crucible.Backend` behaviour to integrate with the broader Crucible experiment framework.

---

### 4. LineageIR (November 29, 2025)

**File**: `20251129/nsai_ir_specification/04_LINEAGE_IR.md`

Defines trace and artifact tracking:

```elixir
defmodule LineageIR.Trace do
  defstruct [
    :trace_id,
    :parent_id,
    :spans,             # List of execution spans
    :artifacts,         # Checkpoints, outputs, logs
    :metadata
  ]
end

defmodule LineageIR.Artifact do
  defstruct [
    :artifact_id,
    :type,              # :checkpoint | :model | :dataset | :log
    :uri,               # Storage location (tinker:// path)
    :size_bytes,
    :checksum,
    :metadata
  ]
end
```

**Relevance to tinkex**: Checkpoints should be registered as artifacts with lineage tracking.

---

## Architecture Integration Points

### Current tinkex → NSAI Platform

```
┌─────────────────────────────────────────────────────────────┐
│                    NSAI Platform                             │
├─────────────────────────────────────────────────────────────┤
│  NSAI.Work (Job Orchestration)                              │
│    ├── Job submission with retry policies                   │
│    ├── Resource allocation                                  │
│    └── Queue management                                     │
├─────────────────────────────────────────────────────────────┤
│  TrainingIR (Training Specification)                        │
│    ├── CheckpointPolicy                                     │
│    ├── ValidationSpec                                       │
│    └── AdapterConfig                                        │
├─────────────────────────────────────────────────────────────┤
│  CrucibleIR.Backend (Backend Contracts)                     │
│    ├── Prompt/Completion IR                                 │
│    └── Capabilities declaration                             │
├─────────────────────────────────────────────────────────────┤
│  LineageIR (Tracing)                                        │
│    ├── Execution traces                                     │
│    └── Artifact registration                                │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │
┌─────────────────────────────────────────────────────────────┐
│                        tinkex                                │
├─────────────────────────────────────────────────────────────┤
│  Training Client                                            │
│    ├── forward_backward()                                   │
│    ├── optim_step()                                         │
│    └── save/load_weights()                                  │
├─────────────────────────────────────────────────────────────┤
│  Sampling Client                                            │
│    └── sample()                                             │
├─────────────────────────────────────────────────────────────┤
│  Recovery Layer (TO BE BUILT)                               │
│    ├── Recovery.Monitor                                     │
│    └── Recovery.Executor                                    │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Tinker Backend                            │
│  (Remote training/inference service)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Mapping Gaps to Platform IRs

### Gap → TrainingIR Mapping

| tinkex Gap | TrainingIR Concept | Implementation |
|------------|-------------------|----------------|
| No checkpoint scheduling | CheckpointPolicy.strategy | Implement policy-based saves |
| No retention policy | CheckpointPolicy.keep_last | Implement auto-cleanup |
| No best model tracking | CheckpointPolicy.save_best | Track metrics, save best |
| No validation during training | ValidationSpec | Implement eval hooks |

### Gap → NSAI.Work Mapping

| tinkex Gap | NSAI.Work Concept | Implementation |
|------------|-------------------|----------------|
| No automated recovery | RetryPolicy | Wrap training in jobs |
| No resource tracking | Job.resources | Report GPU/memory usage |
| No job status | Job.status | Map to TrainingRun.corrupted |

### Gap → LineageIR Mapping

| tinkex Gap | LineageIR Concept | Implementation |
|------------|-------------------|----------------|
| No checkpoint lineage | Artifact registration | Register checkpoints as artifacts |
| No training traces | Trace spans | Emit training step spans |

---

## Implementation Phases for Integration

### Phase A: Standalone Improvements (Current Focus)

Hardening + recovery automation without platform dependencies:

1. Regression tests for `corrupted` parsing + optimizer-aware load
2. Recovery.Monitor/Executor + telemetry
3. Timestamp normalization for checkpoints/metadata

### Phase B: TrainingIR Adoption

Implement TrainingIR concepts in tinkex:

```elixir
# New module: lib/tinkex/checkpoint_policy.ex
defmodule Tinkex.CheckpointPolicy do
  defstruct [
    strategy: :steps,
    save_every: 100,
    keep_last: 5,
    save_best: true,
    best_metric: "loss",
    best_mode: :min
  ]

  def should_save?(policy, step, epoch, metrics) do
    case policy.strategy do
      :steps -> rem(step, policy.save_every) == 0
      :epoch -> rem(epoch, policy.save_every) == 0
      :best -> improved?(policy, metrics)
      :all -> true
      :last -> false
    end
  end
end
```

### Phase C: NSAI.Work Integration

Wrap tinkex operations in NSAI.Work jobs:

```elixir
# Submit training as NSAI.Work job
defmodule Tinkex.Integration.Work do
  def submit_training_job(config, training_spec) do
    job = %NSAI.Work.Job{
      kind: :training_step,
      payload: training_spec,
      retry_policy: %NSAI.Work.RetryPolicy{
        max_attempts: 3,
        retryable_errors: [:timeout, :backend_unavailable]
      },
      resources: %NSAI.Work.Resources{
        gpu: 1,
        timeout_ms: :timer.hours(24)
      }
    }

    NSAI.Work.Scheduler.submit(job)
  end
end
```

### Phase D: Crucible Backend Implementation

Implement backend behaviour:

```elixir
defmodule Crucible.Backend.Tinkex do
  @behaviour Crucible.Backend

  def init(config) do
    {:ok, %{client: Tinkex.Client.new(config)}}
  end

  def capabilities(_state) do
    %Crucible.Backend.Capabilities{
      backend_id: :tinkex,
      provider: "tinker",
      models: ["llama-3.2-1b", "llama-3.2-3b", "qwen/qwen2.5-7b"],
      supports_streaming: true,
      supports_training: true,
      max_context_length: 8192
    }
  end

  def complete(state, %Crucible.IR.Prompt{} = prompt) do
    # Translate Prompt IR to Tinkex format
    tinkex_request = translate_prompt(prompt)

    case Tinkex.SamplingClient.sample(state.client, tinkex_request) do
      {:ok, response} ->
        {:ok, translate_to_completion(response)}
      error ->
        error
    end
  end

  def health_check(state) do
    case Tinkex.API.Service.health_check(state.client.config) do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
```

### Phase E: LineageIR Integration

Register checkpoints as artifacts:

```elixir
defmodule Tinkex.Integration.Lineage do
  def register_checkpoint(trace_id, checkpoint) do
    artifact = %LineageIR.Artifact{
      artifact_id: checkpoint.checkpoint_id,
      type: :checkpoint,
      uri: checkpoint.tinker_path,
      size_bytes: checkpoint.size_bytes,
      metadata: %{
        checkpoint_type: checkpoint.checkpoint_type,
        created_at: checkpoint.time
      }
    }

    LineageIR.register_artifact(trace_id, artifact)
  end
end
```

---

## Documentation Index (Brainstorm)

| Date | Document | Relevance |
|------|----------|-----------|
| 20251129 | 03_TRAINING_IR.md | CheckpointPolicy, ValidationSpec |
| 20251129 | 01_NSAI_WORK_IR.md | Job orchestration, RetryPolicy |
| 20251129 | 02_CRUCIBLE_BACKEND_IR.md | Backend contracts |
| 20251129 | 04_LINEAGE_IR.md | Trace and artifact tracking |
| 20251129 | 06_IMPLEMENTATION_GUIDE.md | 12-week roadmap |
| 20251122 | ROADMAP.md | Long-term Crucible/CNS vision |
| 20251122 | crucible_framework_architecture.md | Four behaviours pattern |
| 20251123 | tinkex-crucible-integration.md | Integration analysis |
| 20251121 | 01_JacobianMasteryForTinkerAndCNS.md | Gradient analysis features |

---

## Conclusion

The tinkex SDK gaps identified in this analysis are not isolated issues - they represent missing connections to a broader platform architecture being designed in the brainstorm specifications.

**Short-term**: Fix SDK parity (Phases 1-3 of roadmap)
**Medium-term**: Adopt TrainingIR concepts (CheckpointPolicy, ValidationSpec)
**Long-term**: Full NSAI platform integration (Work, Backend, Lineage IRs)

The recovery gap is particularly significant because it spans multiple platform concerns:
- **tinkex**: Detect and recover from failures
- **TrainingIR**: Define checkpoint policies
- **NSAI.Work**: Provide retry infrastructure
- **LineageIR**: Track recovery as lineage events

Solving this properly requires coordination across these layers, which is why the brainstorm specs are essential context for tinkex development.
