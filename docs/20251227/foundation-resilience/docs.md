# Foundation Resilience Library Design (Backoff, Retry, Rate Limits, Circuit Breakers, Semaphores)

## Status
- Draft: 2025-12-27
- Target library: `foundation` (existing repo at `/home/home/p/g/n/foundation`)
- Source inventory: current Tinkex resilience plumbing

## Repository Notes
- Use the existing `foundation` repo; do not create a new repository.

## Recent Decisions (2025-12-27)
- Reset Foundation docs: remove outdated `docs/*` references from `mix.exs` and rebuild docs later.
- Remove legacy wrappers and dependencies (`:fuse`, `:hammer`, `:poolboy`) instead of deprecating them.
- Semaphore approach: use an ETS-based counting semaphore (patterned after the local `./semaphore` clone) and implement weighted semaphores inside Foundation; avoid adding an external `:semaphore` dependency. Linksafe/sweeper mode is deferred.
- Versioning: bump Foundation to 0.2.0 and add a 2025-12-27 CHANGELOG entry.

## Problem Statement
Tinkex implements retries, backoff policies, shared backoff windows, circuit breakers,
and multiple semaphore types across separate modules with inconsistent semantics.
These implementations are now duplicated (often with slightly different formulas),
which makes it harder to reason about correctness, tuning, and reuse. We want a
single, generic resilience library that provides these primitives in a consistent
API and can be reused across SDKs and services.

## Current State Inventory (Tinkex)
- `lib/tinkex/api/retry.ex`: HTTP retry loop, headers, jittered backoff, retry-after
- `lib/tinkex/api/retry_config.ex`: HTTP retry config and delay calculation
- `lib/tinkex/retry.ex` + `lib/tinkex/retry_handler.ex` + `lib/tinkex/retry_config.ex`:
  sampling retry loop with progress timeout and jitter
- `lib/tinkex/future.ex`: polling backoff policy (`:exponential`), no jitter
- `lib/tinkex/recovery/*`: recovery backoff policy for training workflows
- `lib/tinkex/telemetry/reporter.ex`: batch send retry with backoff
- `lib/tinkex/retry_semaphore.ex`: counting semaphore acquire with exponential backoff
- `lib/tinkex/sampling_dispatch.ex`: layered semaphores + backoff for contention
- `lib/tinkex/rate_limiter.ex`: shared backoff window per `{base_url, api_key}`
- `lib/tinkex/circuit_breaker.ex` + `lib/tinkex/circuit_breaker/registry.ex`:
  circuit breaker with ETS registry
- `lib/tinkex/bytes_semaphore.ex`: weighted (byte budget) semaphore

### Backoff Variants in Use Today
| Module | Strategy | Jitter | Notes |
| --- | --- | --- | --- |
| `Tinkex.API.Retry` | exponential, capped | random factor 0.75-1.0 | HTTP parity |
| `Tinkex.API.RetryConfig` | exponential, capped | random factor 0.75-1.0 | HTTP parity |
| `Tinkex.RetryHandler` | exponential, capped | +/- jitter_pct around base | progress timeout |
| `Tinkex.RetrySemaphore` | exponential, capped | factor (1-jitter .. 1) | contention backoff |
| `Tinkex.SamplingDispatch` | exponential, capped | factor (1-jitter .. 1) | layered semaphores |
| `Tinkex.Telemetry.Reporter` | exponential | additive jitter up to 10% | batch retries |
| `Tinkex.Future` | exponential, capped | none | polling backoff |
| `Tinkex.Recovery.Executor` | exponential, capped | none | recovery retries |

Result: inconsistent jitter semantics, attempt counting, and caps across the codebase.

## Goals
- Provide a single backoff and retry implementation with configurable strategies.
- Provide generic semaphore (counting + weighted) and circuit breaker primitives.
- Provide a shared backoff window ("rate limit") primitive usable across clients.
- Make testing deterministic by allowing injected RNG and sleep functions.
- Keep primitives lightweight and embeddable in different apps (not Tinkex-only).
- Provide optional :telemetry hooks for instrumentation.

## Non-Goals
- Distributed rate limiting across nodes or data centers.
- A full job scheduler or background worker system.
- A new logging/telemetry system; only minimal hooks.

## Requirements
### Functional
- Backoff strategies: exponential, linear, constant; allow caps and jitter.
- Retry loop with max attempts or max elapsed time, optional progress timeout.
- Retry-after override support (HTTP use case).
- Shared backoff window per key (rate-limit backoff), with wait and clear.
- Counting semaphore and weighted semaphore with blocking and non-blocking acquire.
- Circuit breaker with configurable thresholds and reset timing; optional registry.

### Non-Functional
- Deterministic tests: pluggable rand and sleep.
- No global name collisions by default; allow explicit registries/names.
- Minimal dependencies (stdlib + `:telemetry` only; no `:fuse`, `:hammer`, `:poolboy`, or `:semaphore`).

## Proposed Architecture
### Module Map (Draft)
- `Foundation.Backoff`
  - Pure delay calculation and jitter strategies.
  - `Backoff.policy()` struct with `strategy`, `base_ms`, `max_ms`, `jitter`,
    `jitter_strategy`, `rand_fun`.
  - `Backoff.delay(policy, attempt)` -> ms.
  - `Backoff.sleep(policy, attempt, sleep_fun \\ &Process.sleep/1)`.

- `Foundation.Retry`
  - Retry orchestration; separates policy and state.
  - `Retry.Policy`: `max_attempts`, `max_elapsed_ms`, `backoff`, `retry_on`,
    `progress_timeout_ms`, `retry_after_ms_fun`.
  - `Retry.State`: `attempt`, `start_time_ms`, `last_progress_ms`.
  - `Retry.run(fun, policy, opts)` for sync retries.
  - `Retry.step(state, policy, result)` for manual loops.

- `Foundation.RateLimit.BackoffWindow`
  - Shared backoff window per key using ETS + :atomics.
  - `for_key/1`, `set/2`, `clear/1`, `should_backoff?/1`, `wait/2`.
  - Generic naming (no Tinkex-specific keying).

- `Foundation.Semaphore`
  - `Semaphore.Counting` (ETS counter, internal; inspired by `./semaphore` clone)
  - `Semaphore.Weighted` (byte/weight budget with blocking + non-blocking acquire)
  - `acquire/2`, `try_acquire/2`, `release/2`, `with_acquire/3`.
  - Optional backoff-based acquire helper that uses `Foundation.Backoff`.

- `Foundation.CircuitBreaker`
  - Core state machine with configurable thresholds and timing.
  - Optional `CircuitBreaker.Registry` with ETS CAS updates.
  - Emits :telemetry events on state transitions.

### Backoff Policy Design
`Foundation.Backoff` should cover current variants and allow precise parity when
needed. Example policy struct:

```elixir
%Foundation.Backoff.Policy{
  strategy: :exponential,
  base_ms: 500,
  max_ms: 10_000,
  jitter_strategy: :factor,   # :factor | :additive | :none
  jitter: 0.25,
  rand_fun: &:rand.uniform/0
}
```

- `:factor` jitter uses `delay * (1 - jitter + rand * jitter)` (current RetrySemaphore style).
- `:additive` jitter uses `delay + rand * (delay * jitter)` (current telemetry style).
- `:range` jitter uses `[min_factor, max_factor]` for exact Python parity (0.75-1.0).

### Retry Policy Design
- `retry_on` is a function `(result_or_error -> boolean)`.
- `retry_after_ms_fun` supports HTTP Retry-After or server-provided backoff.
- `progress_timeout_ms` optional; `Retry.record_progress/1` updates state.

### Circuit Breaker Design
- Keep a state struct similar to `Tinkex.CircuitBreaker`.
- Add optional rolling window mode later (out of scope for first pass).
- Registry should allow custom table name and ownership model.

### Semaphore Design
- Counting semaphore: ETS-based, keyed by name; non-blocking acquire with optional backoff helpers.
- Weighted semaphore: `acquire(weight)` and `release(weight)` with Tinkex parity by allowing the budget
  to go negative for in-flight work, blocking new acquires until the budget is non-negative.
- Provide `with_acquire/3` helper and optional blocking with backoff.

### Rate Limit / Backoff Window
- Keep current monotonic-time semantics.
- Provide `wait/2` with optional sleep function to avoid direct `Process.sleep`.

## Integration Plan for Tinkex (High-Level)
0. Remove legacy Foundation wrappers and dependencies (`:fuse`, `:hammer`, `:poolboy`).
1. Implement `foundation` primitives + tests.
2. Wrap Tinkex retry modules to delegate to foundation policy/state (preserve API).
3. Replace `Tinkex.RateLimiter` with `Foundation.RateLimit.BackoffWindow`.
4. Replace `Tinkex.BytesSemaphore` + `Tinkex.RetrySemaphore` with `Foundation.Semaphore`.
5. Replace `Tinkex.CircuitBreaker` and registry with foundation equivalent.
6. Update `Tinkex.Future`, `Tinkex.Recovery`, and telemetry backoff to reuse `Foundation.Backoff`.
7. Remove duplicated backoff utilities and harmonize jitter semantics.

## Testing Plan
- Property tests for backoff ranges and monotonic cap behavior.
- Deterministic tests using injected `rand_fun` and `sleep_fun`.
- Concurrency tests for semaphores (no leaks, no deadlocks).
- Circuit breaker transitions, including half-open gating.
- Rate limiter wait logic across keys; ETS registry correctness.

## Risks and Mitigations
- Behavior drift from Python parity: preserve parity via explicit policy options.
- Global ETS table collisions: allow explicit registry names and initialization.
- Performance regressions: keep backoff calculations pure and cheap; avoid GenServer
  for single-threaded operations.

## Open Questions
- Should weighted semaphores expose both "allow negative budget" and "strict" modes?
- Should `Foundation.Retry` support jitter range natively or via strategy plugins?
- Should the retry policy include `max_elapsed_ms` by default, or be opt-in?
- How much HTTP-specific parsing (Retry-After) belongs in foundation vs app layer?
