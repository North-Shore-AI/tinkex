# ADR 004 – RetryHandler Parity

## Status
Proposed

## Context
- Current retries live inside `Tinkex.API.with_retries/5`; not reusable for sampling/training ops and emit limited telemetry.  
- Python `RetryHandler` supplies per-handler state (attempts, backoff, progress timeout), richer telemetry, and user-error awareness.

## Decision
Create functional retry handler + helper:
- `Tinkex.RetryHandler` struct + pure functions: `new/1`, `retry?/2`, `next_delay/1`, `record_progress/1`, `progress_timeout?/1`, `increment_attempt/1`, `elapsed_ms/1`.  
- `Tinkex.Retry.with_retry/3` helper to wrap ops (HTTP or client-level), emit retry telemetry, and honor handler decisions.
- Defaults: max_retries 3; base_delay_ms 500; max_delay_ms 8_000; jitter_pct 1.0; progress_timeout_ms 30_000; tracks `attempt`, `last_progress_at`, `start_time`.
- Classification: reuse `Tinkex.Error.retryable?/1`; stop when attempts >= max.

## Consequences
**Positive:** Reusable across HTTP/client ops; richer telemetry per attempt; progress-aware timeouts; matches Python semantics.  
**Negative:** Adds modules and learning surface; need to wire into clients.  
**Neutral:** Functional approach (no GenServer) differs from Python class but aligns with BEAM style.

## Integration
- Refactor API retries to use handler internally (backward compatible interface).  
- Use `with_retry` in Sampling/Training operations (polling, forward/backward, sampling) with telemetry metadata (operation, attempt, delay_ms, retryable?).  
- Keep queue/backpressure concerns separate (existing rate limiter).

## Tests
- Unit: delay growth, jitter bounds, retry? logic for user/system errors, progress timeout, increment attempts.  
- Integration with Bypass: retry on 500/408/429; stop on 400; emit telemetry events.

## Rollout
1) Ship `RetryHandler` + tests.  
2) Add `Retry.with_retry` helper with telemetry events.  
3) Wire API to handler; then Sampling/Training clients.  
4) Document telemetry events and examples.***
