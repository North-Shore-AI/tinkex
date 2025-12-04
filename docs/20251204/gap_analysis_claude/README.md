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

### Overall Parity: ~85%

The Elixir SDK achieves good parity for core operations but has critical gaps in recovery:

| Category | Status |
|----------|--------|
| Training Operations | ✅ Full Parity |
| Sampling/Inference | ✅ Full Parity |
| Checkpoint Save/Load | ⚠️ Missing optimizer restore |
| Error Recovery | ❌ Not Production Ready |
| Types | ⚠️ 8 missing categories |

### Critical Gaps (P0)

1. **Cannot detect poisoned jobs** - `TrainingRun.corrupted` parsing needs verification
2. **Cannot fully restore training** - `load_state_with_optimizer()` missing
3. **No automated recovery** - Users must manually restart

### Recommended Actions

**Immediate (1-2 days):**
- Verify `TrainingRun.corrupted` field parsing
- Add `load_state_with_optimizer/2`
- Add `create_training_client_from_state_with_optimizer/3`

**Short-term (1-2 weeks):**
- Add `compute_logprobs/2`
- Fix `ImageChunk` type (if using images)
- Add missing response types
- Implement Recovery.Monitor/Executor

**Medium-term (ongoing):**
- Integrate with NSAI.Work job orchestration
- Implement CheckpointPolicy from TrainingIR
- Add Crucible backend adapter

## Quick Reference

### Detecting Failed Jobs
```elixir
{:ok, run} = Tinkex.API.Rest.get_training_run(config, run_id)
if run.corrupted do
  IO.puts("Job is poisoned!")
end
```

### Manual Recovery (After Fixes)
```elixir
# With optimizer state restored
{:ok, client} = Tinkex.Client.create_training_client_from_state_with_optimizer(
  config,
  "tinker://run-id/weights/checkpoint-005"
)
# Resume training...
```

## Related Documentation

- Python SDK: `./tinker/src/tinker/`
- Brainstorm specs: `../tinkerer/brainstorm/20251129/`
- TrainingIR: `03_TRAINING_IR.md`
- NSAI.Work: `01_NSAI_WORK_IR.md`
