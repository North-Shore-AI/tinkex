# Python SDK v0.7.0 (commit 5ad4282) – parity review for Elixir

## Context
- Pulled upstream `tinker` Python SDK (commit `5ad4282c9629be72959f25206a82d496115d2821`, version bump to `0.7.0`).
- Goal: capture deltas and outline required changes to keep `tinkex` aligned.

## Upstream changes (high-signal)
- **Queue state reason surfaced**: `QueueStateObserver.on_queue_state_change/2` now receives `(queue_state, queue_state_reason)` and `_APIFuture` propagates `queue_state_reason` from server error bodies when present (`tinker/src/tinker/lib/api_future_impl.py`).
- **Sampling dispatch throttling by size**: New `BytesSemaphore` and layered semaphores in `InternalClientHolder` to rate-limit sampling by estimated payload bytes + count; backoff uses monotonic time and scales with payload size (`tinker/src/tinker/lib/internal_client_holder.py`, `.../public_interfaces/sampling_client.py`).
- **Training chunking limits relaxed but byte-capped**: `MAX_CHUNK_LEN` raised 128 → 1024; chunk grouping now uses estimated bytes with a 5,000,000-byte cap (was count-based 500,000) and reuses holder byte estimators (`tinker/src/tinker/lib/public_interfaces/training_client.py`).
- **Optimizer params extended**: `AdamParams` adds `weight_decay` (decoupled) and `grad_clip_norm` (0 = disabled) (`tinker/src/tinker/types/optim_step_request.py`).
- **Queue-state logging UX**: Default reasons updated (“concurrent sampler weights limit hit”, “Tinker backend is running short on capacity”), with server-supplied reason preferred.
- **Exception picklability**: `_exceptions.py` adds `__reduce__` and positional init args for API errors (mainly Python threading/pickling resilience).

## Parity gaps & recommended Elixir updates
1) **Queue state reason propagation**
   - Today `Future` only forwards the queue_state atom + metadata map. Add support for optional `queue_state_reason` from server responses (429/503 or try-again envelopes), pass through to observers/logging, and keep backward compatibility with existing 1- and 2-arity callbacks.
   - Update `QueueStateLogger`/observer defaults to prefer server-provided reasons; align copy with Python defaults.

2) **Sampling dispatch rate limiting**
   - Python now guards sampling with byte-aware semaphores and more conservative backoff for large payloads. `tinkex` only uses a concurrency semaphore + retry-based backoff (already monotonic). Add a shared estimator for `ModelInput`/chunks (image bytes, asset pointers, token lengths * 10 bytes), then layer:
     - global per-session dispatch concurrency (existing),
     - throttled concurrency when a recent backoff was requested (need a “recent backoff” check; current `RateLimiter` clears state),
     - byte budget semaphore (baseline 5 MB; increase effective cost after backoff).

3) **Training chunking semantics**
   - `DataProcessor` (used by TrainingClient) still chunks on counts (128 items, 500k “numbers”). Raise limits to 1024 items with a byte cap (`@max_chunk_bytes_count` = 5_000_000).
   - Replace count-based estimation with byte estimation (reuse the sampling estimator). Include loss_fn_inputs with a *10 multiplier like Python.
   - Update chunking tests to assert new sizing behavior and guardrails.

4) **Optimizer config surface**
   - Extend `Tinkex.Types.AdamParams` + encoder to include `weight_decay` and `grad_clip_norm` (defaults 0.0). Validate > = 0. Wire through `OptimStepRequest` and any helpers so callers can set these fields; add tests/docs.

5) **Minor**
   - Logging message tweak in `ServiceClient` (info-level after TrainingClient init) is optional.
   - Python exception pickling changes have no direct Elixir analogue; no action unless we mirror error serialization elsewhere.

## Suggested implementation/test plan
- Add byte estimator utility (shared by TrainingClient and SamplingClient) with coverage for text/image/asset chunks and loss inputs.
- Adjust TrainingClient chunking constants + logic; refresh unit tests that assert chunk splitting.
- Extend AdamParams struct, validation, and JSON encoding; add tests for defaults and user-specified values; ensure `optim_step/2` integration.
- Enhance Future to plumb `queue_state_reason` into observer metadata; update QueueStateLogger strings and observer callbacks to accept/use it; add regression tests for debounce + reason propagation.
- Implement sampling dispatch throttling (concurrency + bytes + monotonic backoff) and tests that assert reduced throughput after backoff and recovery.***/
