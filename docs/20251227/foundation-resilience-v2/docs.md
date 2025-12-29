# Foundation Resilience Library v2 Draft

## Status
- Draft: 2025-12-27
- Target repo: `/home/home/p/g/n/foundation`
- This draft supersedes `foundation-resilience/docs.md` for scope and decisions.

## Goals
- Provide a single, generic resilience primitives library for backoff, retry, shared backoff windows, circuit breakers, and semaphores.
- Preserve behavioral parity with Tinkex where required (jitter ranges, retry-after, progress timeouts).
- Make tests deterministic via injectable RNG and sleep functions.
- Keep dependencies minimal and avoid runtime global name collisions by default.

## Non-Goals
- Distributed rate limiting or multi-node coordination.
- Connection pooling or request scheduling.
- New telemetry/logging systems beyond opt-in hooks.

## Decisions (Committed)
- Remove legacy wrappers and dependencies: `:fuse`, Hammer, and Poolboy are removed (no deprecations).
- Counting semaphores are implemented internally using ETS counters (patterned after the local `./semaphore` clone).
- Weighted semaphores are implemented inside Foundation (no external dependency).
- No linksafe/sweeper mode for counting semaphores in v1; use `with_acquire/3` to avoid leaks.
- No external `:semaphore` dependency.
- Release target: bump Foundation to 0.2.0 and add a 2025-12-27 changelog entry.

## Module Map (Proposed)
- `Foundation.Backoff`
  - Pure delay calculation and jitter strategies.
  - `Backoff.Policy` struct: `strategy`, `base_ms`, `max_ms`, `jitter`, `jitter_strategy`, `rand_fun`.
  - `delay(policy, attempt)` and `sleep(policy, attempt, sleep_fun \\ &Process.sleep/1)`.

- `Foundation.Retry`
  - `Retry.Policy`: `max_attempts`, `max_elapsed_ms`, `backoff`, `retry_on`, `progress_timeout_ms`, `retry_after_ms_fun`.
  - `Retry.State`: `attempt`, `start_time_ms`, `last_progress_ms`.
  - `run(fun, policy, opts)` and `step(state, policy, result)`; `record_progress/1`.

- `Foundation.RateLimit.BackoffWindow`
  - ETS + `:atomics` per key: `for_key/1`, `set/2`, `clear/1`, `should_backoff?/1`, `wait/2`.
  - Optional `sleep_fun` for deterministic tests.

- `Foundation.Semaphore`
  - `Semaphore.Counting`: ETS counter; `acquire/2`, `try_acquire/2`, `release/1`, `with_acquire/3`.
  - `Semaphore.Weighted`: budget-based semaphore (bytes/weight), blocking + non-blocking acquire.
  - Optional backoff-based acquisition using `Foundation.Backoff`.

- `Foundation.CircuitBreaker`
  - State machine mirroring Tinkex semantics (closed/open/half_open).
  - Optional ETS registry with CAS updates (`CircuitBreaker.Registry`).
  - Telemetry hooks on state transitions.

## Backoff Design
- Strategies: `:exponential`, `:linear`, `:constant`.
- Jitter strategies:
  - `:factor` -> `delay * (1 - jitter + rand * jitter)`
  - `:additive` -> `delay + rand * (delay * jitter)`
  - `:range` -> factor in `[min_factor, max_factor]` for Python parity (0.75..1.0)
  - `:none`
- Attempts are 0-based; caps are applied before jitter unless `:range` is requested.

## Retry Design
- `retry_on` is a predicate `(result -> boolean)`.
- `retry_after_ms_fun` allows HTTP retry-after overrides.
- `progress_timeout_ms` halts retries when no progress is recorded.
- `max_attempts` and `max_elapsed_ms` are independent limits.

## Semaphore Design
- Counting semaphore: ETS counter, no GenServer; `acquire` is non-blocking, `with_acquire` wraps release in `after`.
- Weighted semaphore: GenServer-backed queue that allows the budget to go negative for in-flight work (Tinkex parity).
- Blocking acquire optionally uses backoff to avoid tight loops.
- V1 does not include linksafe sweeper; revisit if leak reports appear.

## Circuit Breaker Design
- State machine consistent with `Tinkex.CircuitBreaker` (failure threshold, reset timeout, half-open gating).
- Registry uses ETS CAS updates to avoid lost updates under concurrency.

## Determinism and Telemetry
- All backoff/reties accept `rand_fun` and `sleep_fun`.
- Telemetry events are optional and non-blocking.

## Migration From Tinkex (Behavior Parity)
- `Tinkex.API.Retry` -> `Foundation.Backoff` + `Foundation.Retry` with `:range` jitter (0.75..1.0).
- `Tinkex.RetryHandler` -> `Foundation.Backoff` with +/- jitter around base (custom strategy).
- `Tinkex.RateLimiter` -> `Foundation.RateLimit.BackoffWindow`.
- `Tinkex.RetrySemaphore` and `Tinkex.BytesSemaphore` -> `Foundation.Semaphore`.
- `Tinkex.CircuitBreaker` + registry -> `Foundation.CircuitBreaker`.
- `Tinkex.Future`, `Tinkex.Recovery`, telemetry retry -> `Foundation.Backoff`.

## Testing Plan
- Property tests for backoff ranges and cap behavior.
- Deterministic tests with `rand_fun`/`sleep_fun`.
- Concurrency tests for semaphore acquisition + release ordering.
- Circuit breaker transitions (closed/open/half_open) and registry CAS behavior.
- Backoff window correctness across keys and wait semantics.

## Open Questions
- Should weighted semaphores expose both "allow negative budget" and "strict" modes?
- Should `Foundation.Retry` include `max_elapsed_ms` by default or opt-in?
- Should retry-after parsing stay in app layer or be offered as a helper in foundation?
