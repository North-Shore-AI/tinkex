# RetryHandler parity (sampling/training retry semantics)

Goal: port tinker’s `RetryHandler` to Elixir so sampling/training calls get structured retry/backoff + telemetry hooks instead of ad-hoc per-call options.

## Reference behavior (tinker `lib/retry_handler.py`)
- Per-handler state: max retries, backoff with jitter, progress tracking, queue-state awareness.
- Retryable errors: HTTP 5xx, 408, some 429; non-retryable for user errors (4xx except 408/429).
- Emits telemetry on each attempt/failure with timing metadata.

## Proposed Elixir shape
- New module `Tinkex.RetryHandler` (pure struct + functions).
  - Fields: `max_retries`, `base_delay_ms`, `jitter_pct`, `max_delay_ms`, `progress_timeout_ms`, `attempt`, `last_progress_at`, optional `queue_state_observer`.
  - `new/1`, `next_delay/1`, `retry?/2` (consumes `Tinkex.Error` or status/int), `record_progress/1`.
- Integrate with clients:
  - `SamplingClient` operations (sample, complete) call through a helper `with_retry(fun, opts, retry_handler)` that loops attempts until success or terminal error; apply delay via `Process.sleep/1`.
  - `TrainingClient` forward/backward/optim/save_weights use same helper.
  - Pass telemetry metadata per attempt (attempt number, delay, error info) to Reporter when available.

## Implementation steps
1. Add `lib/tinkex/retry_handler.ex` with public API:
   - `new(opts)` -> struct.
   - `should_retry?(handler, error_or_status)` -> {boolean, handler}.
   - `backoff(handler)` -> {delay_ms, updated_handler}.
   - `record_progress/1` to reset progress timer.
2. Add `Tinkex.Retry.with_retry/3` helper:
   - Accept `fun` returning `{:ok, result} | {:error, reason}`.
   - Loop attempts: on retryable error, sleep `delay`, emit telemetry event (`tinkex.retry.attempt`), continue.
   - Stop on user error or max attempts; return last error.
3. Wire into `SamplingClient` and `TrainingClient`:
   - Initialize handler from config/opts (defaults mirroring Python).
   - Replace direct API calls with `Retry.with_retry(fn -> call_api(...) end, handler, telemetry)`.
4. Telemetry integration:
   - Emit generic event with fields: `attempt`, `max_retries`, `delay_ms`, `error_type`, `status_code`, `retryable?`.
   - Keep existing Reporter pipeline; ensure metadata uses current session_id.

## Tests
- `test/tinkex/retry_handler_test.exs`: unit tests for delay growth, jitter bounds, progress reset.
- Client integration tests (sampling/training) using Bypass to simulate retryable/non-retryable statuses and assert retry counts and telemetry events.
