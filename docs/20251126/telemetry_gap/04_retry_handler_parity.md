# RetryHandler parity (sampling/training retry semantics)

Goal: port tinker's  to Elixir so sampling/training calls get structured retry/backoff + telemetry hooks.

## Reference behavior (tinker lib/retry_handler.py)
- Per-handler state: max retries, backoff with jitter, progress tracking, queue-state awareness.
- Retryable errors: HTTP 5xx, 408, some 429; non-retryable for user errors (4xx except 408/429).
- Emits telemetry on each attempt/failure with timing metadata.

## Proposed Elixir shape
- New module  (pure struct + functions).
  - Fields: , , , , , , .
  - , , , .
- Integrate with clients via  helper.

## Implementation steps
1. Add  with public API.
2. Add  helper.
3. Wire into  and .
4. Telemetry integration.

## Tests
- : unit tests for delay growth, jitter bounds, progress reset.
- Client integration tests using Bypass.
