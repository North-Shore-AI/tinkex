# Tinkex Gap Analysis: Executive Summary

**Date**: December 4, 2025
**Context**: Backend incident revealed checkpoint recovery as critical production concern
**Scope**: Full SDK parity analysis between Python Tinker SDK and Elixir tinkex

---

## TL;DR

The Elixir tinkex SDK now matches the Python SDK for all documented primitives (including `TrainingRun.corrupted`, `load_state_with_optimizer/3`, `create_training_client_from_state_with_optimizer/3`, `compute_logprobs/2`, and custom loss). Remaining work is around automation, normalization, and hardening rather than missing features.

1. **Recovery Automation** - SDK primitives exist, but no monitor/executor to restart corrupted runs
2. **Type Normalization** - Checkpoint timestamps remain strings; downstream code should normalize to `DateTime`
3. **Hardening** - Add integration tests for corrupted-run parsing and optimizer-state restoration paths

---

## Gap Summary by Category

### Critical (P0) - Blocks Production Use

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| Recovery orchestration | Manual (user responsibility) | **MISSING** | Requires bespoke monitor/executor to auto-restart |

### High Priority (P1) - Limits Functionality

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| Checkpoint time parsing | datetime | String passthrough | Needs normalization for time math |
| Recovery telemetry | Minimal | Missing | Hard to observe recovery attempts/failures |
| Test coverage | Integration tests | Missing | Corrupted-run + optimizer-load paths unvalidated |

### Medium Priority (P2) - Reduces Parity

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| Checkpoint validation | None | None | Integrity not checked pre-load |
| Auto-checkpoint policy | None | None | No retention/scheduling helper |

---

## What Works Well (Parity Achieved)

| Category | Status | Notes |
|----------|--------|-------|
| Training operations | FULL PARITY | forward, forward_backward, optim_step, custom loss |
| Weight save/load | FULL PARITY | includes optimizer-state restore |
| Sampling | FULL PARITY | sample + `compute_logprobs/2` with backpressure |
| REST endpoints | FULL PARITY | All checkpoint/session operations |
| HTTP retry logic | FULL PARITY | Exponential backoff, jitter, progress timeout |
| Connection pooling | FULL PARITY | Separate pools per operation type |
| Session heartbeats | FULL PARITY | 10s interval, failure detection |

---

## Quantitative Summary

```
API Functions: Full coverage of documented Python surface; Elixir adds typed + sync helpers.
Types: All documented Python types present; only notable difference is checkpoint timestamps remain strings on ingest.
```

---

## Root Cause Analysis

The backend incident message:
> "If you had ongoing training runs, you might be getting a message about your job being 'poisoned'. Unfortunately you'll need to restart your jobs from the latest checkpoint."

This reveals:
1. **Jobs can become "corrupted/poisoned"** during backend failures
2. **Recovery is manual** - users must restart from checkpoints themselves
3. **The Python SDK provides tools** (`corrupted` flag, `load_state_with_optimizer`) but no automation

**Current Elixir gaps:**
- Cannot query `TrainingRun.corrupted` status
- Cannot use `load_state_with_optimizer` for full state restore
- No recovery orchestration layer

---

## Recommended Action Plan

### Phase 1: SDK Parity (1-2 weeks)
1. Add integration tests for `TrainingRun.corrupted` and optimizer-state restores
2. Normalize checkpoint timestamps to `DateTime.t()`
3. Document manual recovery recipes (weights-only vs optimizer)

### Phase 2: Recovery Layer (2-3 weeks)
1. Create `RecoveryPolicy` configuration struct
2. Build `TrainingRecovery` GenServer for monitoring
3. Implement automatic checkpoint-based restart
4. Add recovery telemetry events

### Phase 3: Integration (1-2 weeks)
1. Connect to NSAI.Work job orchestration (per brainstorm specs)
2. Integrate with Crucible experiment management
3. Add CheckpointPolicy from TrainingIR spec

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [01_PYTHON_SDK_API_INVENTORY.md](01_PYTHON_SDK_API_INVENTORY.md) | Complete Python API reference |
| [02_ELIXIR_SDK_CURRENT_STATE.md](02_ELIXIR_SDK_CURRENT_STATE.md) | Current Elixir implementation |
| [03_TYPE_PARITY_ANALYSIS.md](03_TYPE_PARITY_ANALYSIS.md) | Type-by-type comparison |
| [04_API_FUNCTION_GAPS.md](04_API_FUNCTION_GAPS.md) | Missing API functions |
| [05_CHECKPOINT_RECOVERY_GAPS.md](05_CHECKPOINT_RECOVERY_GAPS.md) | Recovery-specific gaps |
| [06_PRODUCTION_READINESS.md](06_PRODUCTION_READINESS.md) | Production requirements |
| [07_IMPLEMENTATION_ROADMAP.md](07_IMPLEMENTATION_ROADMAP.md) | Prioritized implementation |

---

## Appendix: Broader Context

This analysis connects to the broader NSAI ecosystem documented in `tinkerer/brainstorm/`:

- **TrainingIR** (Nov 29) - Defines CheckpointPolicy, ValidationSpec
- **NSAI.Work** (Nov 29) - Unified job orchestration with retry policies
- **CrucibleIR.Backend** (Nov 29) - Backend contracts for training
- **Crucible Framework** (Nov 22) - Experiment management behaviours

The checkpoint recovery gap is not unique to tinkex - it's a fundamental architectural concern that the broader NSAI platform will need to address through the TrainingIR and NSAI.Work specifications.
