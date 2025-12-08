# Python SDK v0.7.0 Port Implementation Guide

## Overview

This directory contains detailed technical specifications for porting Python SDK v0.7.0 (commit `5ad4282c9629be72959f25206a82d496115d2821`) changes to the Elixir `tinkex` client.

## Specifications Index

| # | Specification | Priority | Complexity | Dependencies |
|---|---------------|----------|------------|--------------|
| 01 | [AdamParams Extension](./01_adam_params_extension.md) | High | Low | None |
| 02 | [Queue State Reason Propagation](./02_queue_state_reason_propagation.md) | Medium | Medium | None |
| 03 | [Byte Estimation Utility](./03_byte_estimation.md) | High | Low | None |
| 04 | [Training Chunking Changes](./04_training_chunking_changes.md) | High | Medium | 03 |
| 05 | [Sampling Dispatch Throttling](./05_sampling_dispatch_throttling.md) | Medium | High | 03 |

## Recommended Implementation Order

### Phase 1: Foundation (No Dependencies)

```
┌─────────────────────────────────────────────────────────────┐
│  01_adam_params_extension.md       03_byte_estimation.md    │
│  ├─ AdamParams struct              ├─ ByteEstimator module  │
│  ├─ weight_decay field             ├─ estimate_chunk_bytes  │
│  ├─ grad_clip_norm field           ├─ estimate_datum_bytes  │
│  └─ Validation + tests             └─ Unit tests            │
└─────────────────────────────────────────────────────────────┘
                              ↓
```

**Why first**: These are isolated changes with no cross-dependencies. ByteEstimator is a foundation for Phase 2.

### Phase 2: Training Changes (Depends on 03)

```
┌─────────────────────────────────────────────────────────────┐
│  04_training_chunking_changes.md                            │
│  ├─ Update @max_chunk_len (128 → 1024)                      │
│  ├─ Update @max_chunk_bytes_count (500K → 5M)               │
│  ├─ Integrate ByteEstimator in DataProcessor                │
│  └─ Update chunking tests                                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
```

**Why second**: Depends on ByteEstimator. High impact on training API behavior.

### Phase 3: Queue State Improvements (Independent)

```
┌─────────────────────────────────────────────────────────────┐
│  02_queue_state_reason_propagation.md                       │
│  ├─ TryAgainResponse.queue_state_reason                     │
│  ├─ Future.poll reason handling                             │
│  ├─ QueueStateLogger.resolve_reason/3                       │
│  └─ Observer metadata updates                               │
└─────────────────────────────────────────────────────────────┘
                              ↓
```

**Why third**: Observability improvement, no blocking dependencies. Can be parallelized with Phase 2.

### Phase 4: Sampling Throttling (Depends on 03)

```
┌─────────────────────────────────────────────────────────────┐
│  05_sampling_dispatch_throttling.md                         │
│  ├─ BytesSemaphore module                                   │
│  ├─ SamplingDispatch module                                 │
│  ├─ RateLimiter monotonic time                              │
│  └─ SamplingClient integration                              │
└─────────────────────────────────────────────────────────────┘
```

**Why last**: Most complex change. Depends on ByteEstimator. Lower priority since existing throttling works.

## Implementation Effort Estimates

| Specification | Files Modified | Files Created | Test Coverage |
|---------------|----------------|---------------|---------------|
| 01 AdamParams | 1 | 0 | ~5 tests |
| 02 Queue State | 6 | 0 | ~10 tests |
| 03 ByteEstimator | 2 | 1 | ~15 tests |
| 04 Chunking | 2 | 0 | ~10 tests |
| 05 Dispatch | 2 | 2 | ~15 tests |
| **Total** | **13** | **3** | **~55 tests** |

## Files Changed Summary

### New Files

```
lib/tinkex/byte_estimator.ex           # Spec 03
lib/tinkex/bytes_semaphore.ex          # Spec 05
lib/tinkex/sampling_dispatch.ex        # Spec 05
test/tinkex/byte_estimator_test.exs    # Spec 03
test/tinkex/bytes_semaphore_test.exs   # Spec 05
test/tinkex/sampling_dispatch_test.exs # Spec 05
```

### Modified Files

```
lib/tinkex/types/adam_params.ex              # Spec 01
lib/tinkex/types/try_again_response.ex       # Spec 02
lib/tinkex/future.ex                         # Spec 02
lib/tinkex/queue_state_observer.ex           # Spec 02
lib/tinkex/queue_state_logger.ex             # Spec 02
lib/tinkex/sampling_client.ex                # Spec 02, 05
lib/tinkex/training_client.ex                # Spec 02
lib/tinkex/training_client/data_processor.ex # Spec 04
```

## Backward Compatibility Notes

### Breaking Changes

**None** - All changes are additive or relax existing limits:
- AdamParams: New optional fields with defaults matching previous behavior
- Queue state: New metadata field, existing observers unaffected
- Chunking: Larger limits allow more data per chunk
- Throttling: Additional rate limiting layers

### Deprecations

- `estimate_number_count/1` in DataProcessor → use `ByteEstimator.estimate_datum_bytes/1`
- `@max_chunk_number_count` → renamed to `@max_chunk_bytes_count`

## Testing Strategy

### Unit Tests

Each spec includes detailed test cases. Run individually:

```bash
mix test test/tinkex/types/adam_params_test.exs
mix test test/tinkex/byte_estimator_test.exs
mix test test/tinkex/training_client/data_processor_test.exs
```

### Integration Tests

Verify end-to-end behavior:

```bash
mix test test/tinkex/training_client_test.exs
mix test test/tinkex/sampling_client_test.exs
```

### Regression Tests

Ensure existing functionality is preserved:

```bash
mix test --only existing_behavior
```

## Verification Checklist

After implementation, verify parity with Python SDK:

- [ ] `AdamParams` JSON output matches Python schema
- [ ] `TryAgainResponse` parses `queue_state_reason` from server
- [ ] Training chunks respect 1024 item / 5MB limits
- [ ] Queue state observer receives server-supplied reasons
- [ ] Sampling dispatch throttles during backoff (20× byte penalty)
- [ ] Backoff timestamps use monotonic time

## Related Documentation

- [Original notes](./notes.md) - Initial analysis and gap summary
- Python SDK source: `tinker/src/tinker/lib/`
- Elixir source: `lib/tinkex/`

## Change Log

| Date | Change |
|------|--------|
| 2025-12-07 | Initial specification documents created |
