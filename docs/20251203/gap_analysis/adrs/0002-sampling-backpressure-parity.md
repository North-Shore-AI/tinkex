# ADR 0002: Match Python sampling backpressure and 429 handling

Status: Proposed  
Date: 2025-12-03

## Context
- Python sampling client enforces a dispatch semaphore and backs off for one second when `/asample` returns 429 without `Retry-After` (`tinker/src/tinker/lib/public_interfaces/sampling_client.py:158-179`).
- Elixir `Tinkex.SamplingClient` only backs off when `retry_after_ms` is present and lacks a dispatch semaphore (`lib/tinkex/sampling_client.ex:392-445`).
- This leads to immediate replays and potential hammering under rate limits, diverging from Python behavior.

## Decision
- Introduce a dispatch semaphore in Elixir sampling (configurable, default aligned with Python) to gate concurrent `_sample_async` dispatches.
- Add a fallback backoff (e.g., 1s) on 429 responses even when `retry_after_ms` is absent, mirroring Python’s behavior.
- Keep existing `RetryConfig`-driven retry flow; integrate the new backoff so it cooperates with RateLimiter and RetrySemaphore.

## Consequences
- Improved rate-limit friendliness and behavioral parity; fewer rapid replays on 429s.
- Slight increase in latency under heavy load but predictable and consistent with Python SDK expectations.

## Alternatives considered
- Rely solely on server-provided `Retry-After`: rejected because many 429s omit it and Python already handles that case client-side.
