# Sampling retry/backoff configuration

**Gap:** Python lets callers supply a `RetryConfig` to SamplingClient; Elixir hardcodes sampling retry/backpressure behavior and ignores caller configs.

- **Python feature set**
  - `SamplingClient.create(..., retry_config=RetryConfig)` with per-call `retry_handler` for asample retries/backoff (`sampling_client.py`, `retry_handler.py`).
  - Allows tuning max attempts, jitter, backoff windows for sampling requests separately from HTTP retries.
- **Elixir port status**
  - `Tinkex.SamplingClient` always uses shared `RateLimiter` and sets `max_retries: 0` at HTTP layer (`lib/tinkex/api/sampling.ex`).
  - `ServiceClient.create_sampling_client/2` and `SamplingClient.create_async/2` discard any retry configuration; no hook to control sampling retries beyond rate limiter backoff.
- **Impact**
  - Callers cannot tune sampling reliability vs. latency; parity with Python’s retry semantics is missing.
- **Suggested alignment**
  1) Add a `RetryConfig` type/struct to mirror Python’s parameters.
  2) Thread an optional `retry_config` through `ServiceClient.create_sampling_client[_async]` into `SamplingClient` state.
  3) Implement a retry handler around `do_sample` (or underlying HTTP call) similar to Python’s `_get_retry_handler` behavior.
