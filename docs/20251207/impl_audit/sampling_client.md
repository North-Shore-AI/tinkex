# Sampling Client Implementation Audit

**Date**: 2025-12-07  
**Python SDK Commit**: 5ad4282c (`./tinker`)  
**Elixir Port**: Current uncommitted workspace

---

## Overview

Core sampling behavior in the Elixir port matches the current Python SDK: three-layer rate limiting (count/throttled/bytes), backoff on 429 with 1s/5s delays, queue-state debouncing, and retry logic with exponential backoff and progress timeouts. The earlier draft incorrectly flagged missing progress-timeout tracking and max-retry limits—both SDKs implement these today.

---

## Architecture Check

- **Python**  
  - `SamplingClient.sample_async` → `_sample_async_impl` guarded by `_sample_dispatch_semaphore` (400), `_sample_dispatch_throttled_semaphore` (10 during backoff), and a 5 MB `BytesSemaphore` in `InternalClientHolder`.  
  - Backoff stored in `_sample_backoff_until` using `time.monotonic()`.  
  - Retries handled by `RetryHandler` (progress_timeout=120m, max_delay=10s, jitter=0.25, max_connections default 1000).  
  - Queue-state observer logs with 60s debounce and includes `queue_state_reason` when available.

- **Elixir**  
  - `SamplingDispatch` mirrors the same semaphore layers and byte penalty multiplier during backoff.  
  - Backoff tracked with monotonic timestamps and a 10s “recent backoff” window.  
  - Retries via `Tinkex.Retry` + `RetryConfig` (defaults: progress_timeout_ms=120m, max_delay_ms=10s, jitter=0.25, max_retries=:infinity, max_connections=1000).  
  - Queue-state observer (`QueueStateLogger` + `:persistent_term` debounce) logs reasons, preferring server-supplied `queue_state_reason`.

---

## Notable Differences

- **Async API surface**: Python exposes `sample_async`; Elixir’s `sample/4` already returns a `Task` and can be wrapped in `Task.async/await`, but there is no separate `_async`-named helper.
- **Retry semaphore scoping**: Python’s `RetryHandler` semaphore is per handler (cached per sampling session). Elixir’s `RetrySemaphore` is keyed only by `max_connections`, so different clients with the same limit share capacity. This could introduce cross-client coupling under heavy load.
- **Feature gates**: Python reads `TINKER_FEATURE_GATES` (currently unused). Elixir surfaces feature gates via `Tinkex.Config`/`Tinkex.Env`, but `SamplingClient` does not consume them either, so behavior is effectively aligned.
- **Queue-state debounce storage**: Elixir uses `:persistent_term` entries per sampling session without cleanup; Python stores the timestamp on the client instance. Long-lived nodes with many sessions could accumulate persistent terms.

---

## Recommendations

1. **Optional retry semaphore scoping**: Allow a caller-provided semaphore key (e.g., `{session_id, max_connections}`) to match Python’s per-client isolation when needed.
2. **Housekeeping for queue-state debounce**: Add a teardown hook or ETS-backed TTL to avoid unbounded `:persistent_term` growth if thousands of sampling sessions are created.
3. **API symmetry (low priority)**: Provide a `sample_async/4` wrapper for API familiarity, even though `sample/4` already returns a `Task`.

---

## Conclusion

Sampling parity is strong. The remaining differences are operational (semaphore scoping and debounce storage) rather than correctness gaps. Progress timeouts, retry limits, byte-aware throttling, and backoff handling are already present in the Elixir port.
