# tinkex Gap Analysis - December 4, 2025

Comprehensive analysis of SDK parity between Python Tinker SDK and Elixir tinkex, with focus on checkpoint recovery and production readiness.

## Context

Backend incident revealed checkpoint recovery as critical production concern:
> "If you had ongoing training runs, you might be getting a message about your job being 'poisoned'. Unfortunately you'll need to restart your jobs from the latest checkpoint."

## Documents

| Document | Purpose |
|----------|---------|
| [00_EXECUTIVE_SUMMARY.md](00_EXECUTIVE_SUMMARY.md) | TL;DR of all gaps and recommendations |
| [01_PYTHON_SDK_API_INVENTORY.md](01_PYTHON_SDK_API_INVENTORY.md) | Complete Python SDK reference |
| [02_ELIXIR_SDK_CURRENT_STATE.md](02_ELIXIR_SDK_CURRENT_STATE.md) | Current Elixir implementation |
| [03_TYPE_PARITY_ANALYSIS.md](03_TYPE_PARITY_ANALYSIS.md) | Type-by-type comparison |
| [04_API_FUNCTION_GAPS.md](04_API_FUNCTION_GAPS.md) | Missing API functions |
| [05_CHECKPOINT_RECOVERY_GAPS.md](05_CHECKPOINT_RECOVERY_GAPS.md) | Recovery-specific gaps |
| [06_PRODUCTION_READINESS.md](06_PRODUCTION_READINESS.md) | Production requirements |
| [07_IMPLEMENTATION_ROADMAP.md](07_IMPLEMENTATION_ROADMAP.md) | Prioritized implementation |
| [08_BRAINSTORM_INTEGRATION.md](08_BRAINSTORM_INTEGRATION.md) | NSAI platform integration |

## Key Findings

### Overall Parity: ~97%

The Elixir SDK matches the Python SDK for all documented primitives, including optimizer-aware checkpoint load and corrupted-run detection. Remaining work is around automation and polish rather than missing functions.

| Category | Status |
|----------|--------|
| Training Operations | ✅ Full Parity |
| Sampling/Inference | ✅ Full Parity (includes `compute_logprobs/2`) |
| Checkpoint Save/Load | ✅ Full Parity (optimizer restore supported) |
| Error Recovery | ⚠️ Manual only (no automation layer) |
| Types | ⚠️ Minor normalization (e.g., checkpoint timestamps) |

### Critical Gaps (P0)

1. **No automated recovery** - SDK exposes primitives but lacks monitor/executor to restart poisoned runs

### Recommended Actions

**Immediate (1-2 days):**
- Add integration tests for `TrainingRun.corrupted` parsing and optimizer-state load paths
- Document manual recovery flow with optimizer restoration

**Short-term (1-2 weeks):**
- Implement Recovery.Monitor/Executor OTP layer (poll → detect corrupted → restart from checkpoint)
- Normalize `Checkpoint.time` to `DateTime.t()` for downstream consumers
- Add backpressure/queue-state alerting around recovery loop

**Medium-term (ongoing):**
- Integrate with NSAI.Work job orchestration
- Implement CheckpointPolicy from TrainingIR
- Add Crucible backend adapter

## Quick Reference

### Detecting Failed Jobs
```elixir
{:ok, run} = Tinkex.API.Rest.get_training_run(config, run_id)
if run.corrupted, do: IO.puts("Job is poisoned!")
```

### Manual Recovery (After Fixes)
```elixir
# Restore weights + optimizer in one call
{:ok, client} =
  Tinkex.ServiceClient.create_training_client_from_state_with_optimizer(
    service_pid,
    "tinker://run-id/weights/checkpoint-005"
  )
# Resume training...
```

## Related Documentation

- Python SDK: `./tinker/src/tinker/`
- Brainstorm specs: `../tinkerer/brainstorm/20251129/`
- TrainingIR: `03_TRAINING_IR.md`
- NSAI.Work: `01_NSAI_WORK_IR.md`
