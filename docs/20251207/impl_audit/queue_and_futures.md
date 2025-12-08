# Queue State & Future Management Audit

**Date**: 2025-12-07  
**Python SDK Commit**: 5ad4282c (`./tinker`)  
**Scope**: Queue-state handling, polling futures, observer/telemetry behavior

---

## Overview

Both SDKs implement retry/backoff polling for server-side promises and surface queue-state transitions. The earlier draft incorrectly stated that Python lacked queue-state reasons and that Elixir missed progress/timeout telemetry already present upstream. The real gaps are narrower: Elixir omits several telemetry events and does not special-case HTTP 410 responses.

---

## Parity Highlights

- **Queue-state propagation**:  
  - Python `_APIFuture` forwards `queue_state` **and `queue_state_reason`** from 408 responses to the observer (`on_queue_state_change(queue_state, queue_state_reason)` in both sampling and training clients).  
  - Elixir `Future.poll/2` emits telemetry and observer callbacks with `queue_state` and `queue_state_reason` from `TryAgainResponse`.

- **Backoff behavior**:  
  - Python retries pending/5xx/408 responses with exponential backoff capped at 30s; respects server hints via HTTP status (429 handled in client-specific code).  
  - Elixir uses exponential backoff up to 30s and honors `retry_after_ms` from `TryAgainResponse` when present.

- **Debounced logging**: Both clients debounce queue-state logs to ~60s; Elixir centralizes this in `QueueStateLogger`, Python keeps per-client timestamps.

---

## Key Differences

- **HTTP 410 (expired promise)**: Python raises `RetryableException` for 410 in `_APIFuture`, allowing callers to resubmit. Elixir treats 410 as a generic error (no retryable classification), so long-lived polls will fail without guidance to recreate the request.

- **Telemetry coverage**:  
  - Python emits structured telemetry for timeouts, API status errors, connection errors, application errors, and validation errors.  
  - Elixir only emits `[:tinkex, :queue, :state_change]` events; failures/timeouts/retries are silent unless callers log them.

- **Result caching**: Python caches `_cached_result` in `_APIFuture.result_async` for repeat calls. Elixir returns bare `Task` results; multiple `Task.await` calls on the same task process are not supported once it exits.

- **Observer signatures**: Python observers always receive `(queue_state, queue_state_reason)`. Elixir observers may implement arity-1 or arity-2 callbacks; metadata includes `request_id` and `queue_state_reason`.

---

## Recommendations

1. **Handle HTTP 410**: Map 410 to a retryable error type (or a documented error atom) in `Future.poll_loop/2`, guiding callers to recreate the request when the promise has expired.
2. **Telemetry parity**: Emit telemetry for timeouts, API/connection errors, and validation failures to match Python’s observability surface.
3. **Optional result caching**: Cache decoded future results to make repeated polls idempotent (low priority).

---

## Status

Operational parity is mostly solid (queue-state reasons, backoff, debounce). The main gaps are missing 410 handling and reduced telemetry, which affect recoverability and observability rather than core functionality.
