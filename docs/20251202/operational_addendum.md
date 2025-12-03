# Operational Parity Addendum (post agent review)

This captures the few incremental points from the multi-agent findings that were not already in the ADRs.

## Retry behavior (cap vs. timeout)
- Python retries indefinitely until the 120m progress timeout (retry_handler.py:41, 124-145).
- Elixir caps retries (default `max_retries: 10` via `RetryConfig.new/1`, `RetryHandler.new/1`), so outages longer than ~55s with backoff can exhaust retries even if progress timeout were raised.
- Action: Decide whether to (a) remove the cap and use time-bounded retries like Python, or (b) raise the cap substantially (e.g., 100+) and document the behavior alongside ADR-005.

## Progress tracking instrumentation
- Python: automatic global tracking with a background monitor task.
- Elixir: progress timeout is driven by `record_progress/1` calls; core paths already call it, but new retry paths must remember to update progress.
- Action: Audit retry call sites to ensure `record_progress/1` is invoked on success paths; consider refactoring to automatic tracking to remove the manual requirement.

## Operational unknowns (speculative)
- Session lifecycle: Python’s session heartbeat model is not obvious from code; Elixir has an explicit SessionManager. No concrete bug found, but behavior may diverge on long runs.
- Telemetry batching: Python batches/flushes telemetry asynchronously; Elixir’s batching/backpressure story is less clear. No evidence of failure, but worth a targeted review or load test.
