# Tinkex Gap Analysis: Executive Summary

**Date**: December 4, 2025
**Context**: Backend incident revealed checkpoint recovery as critical production concern
**Scope**: Full SDK parity analysis between Python Tinker SDK and Elixir tinkex

---

## TL;DR

The Elixir tinkex SDK achieves **~85% feature parity** with the Python SDK for core operations. However, critical gaps exist in:

1. **Checkpoint Recovery** - No automated recovery from "poisoned" jobs
2. **Training Run Status** - Missing `corrupted` flag detection
3. **Type Completeness** - 8 missing type categories
4. **Telemetry Batch** - Cannot send batched telemetry events

---

## Gap Summary by Category

### Critical (P0) - Blocks Production Use

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| TrainingRun.corrupted | `corrupted: bool` field | **MISSING** | Cannot detect poisoned jobs |
| load_state_with_optimizer | Full optimizer state restore | **MISSING** | Cannot fully resume training |
| Recovery orchestration | Manual (user responsibility) | **MISSING** | No automated checkpoint recovery |

### High Priority (P1) - Limits Functionality

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| compute_logprobs() | Dedicated method | **MISSING** | Cannot compute prompt logprobs |
| Session query types | GetSessionResponse, ListSessionsResponse | **MISSING** | Limited session introspection |
| Telemetry batch types | TelemetryBatch, TelemetrySendRequest | **MISSING** | Cannot batch telemetry |
| ImageChunk fields | height, width, tokens (required) | **MISSING** | Cannot use image inputs |

### Medium Priority (P2) - Reduces Parity

| Gap | Python SDK | Elixir Status | Impact |
|-----|-----------|---------------|--------|
| Checkpoint archive types | CheckpointArchiveUrlResponse | Partial | Limited archive metadata |
| Future polling types | FutureRetrieveRequest/Response | **MISSING** | Limited async control |
| Datetime handling | Python datetime | String (ISO) | Type conversion needed |

---

## What Works Well (Parity Achieved)

| Category | Status | Notes |
|----------|--------|-------|
| Training operations | FULL PARITY | forward, forward_backward, optim_step |
| Weight save/load | FULL PARITY | save_weights, load_weights (basic) |
| Sampling | FULL PARITY | sample_async with backpressure |
| REST endpoints | FULL PARITY | All checkpoint/session REST operations |
| HTTP retry logic | FULL PARITY | Exponential backoff, jitter, progress timeout |
| Connection pooling | FULL PARITY | Separate pools per operation type |
| Session heartbeats | FULL PARITY | 10s interval, failure detection |

---

## Quantitative Summary

```
                    Python SDK    Elixir tinkex    Parity %
─────────────────────────────────────────────────────────────
API Functions            33            46          139% (enhanced)
Type Definitions         71            69           97%
  - Full Parity          -             42           59%
  - Compatible           -             15           21%
  - Mismatches           -              3            4%
  - Missing              -              8           11%
REST Endpoints           26            26          100%
Training Ops              3             6          200% (future variants)
Weight Ops                3             6          200% (typed variants)
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
1. Add `TrainingRun` type with `corrupted` field
2. Add `get_training_run/2` and `list_training_runs/1` to API
3. Implement `load_state_with_optimizer/2` in TrainingClient
4. Add missing telemetry types

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
