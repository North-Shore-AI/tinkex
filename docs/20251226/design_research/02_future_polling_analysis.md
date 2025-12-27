# Future Polling Implementation Analysis: Tight Retry Loops and Race Conditions

**Date**: 2025-12-26
**File**: `/lib/tinkex/future.ex`
**Status**: ISSUES FOUND - Critical tight loops identified

## Executive Summary

The `Tinkex.Future` polling implementation contains **critical tight retry loops** on HTTP 408 and 5xx status codes that can cause CPU exhaustion, stack overflow, and server load amplification. Unlike connection errors which apply exponential backoff, these transient HTTP errors are retried **immediately without any sleep**, creating potential for thousands of requests per second to a struggling server.

## Issue 1: Immediate Retry Without Backoff for 408 Status (CRITICAL)

**Location**: Lines 217-220

**Code**:
```elixir
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # No sleep - immediate retry like Python SDK
  poll_loop(%{state | last_failed_error: error}, iteration + 1)
```

**Problem**:
- HTTP 408 (Request Timeout) triggers immediate recursive call to `poll_loop/2`
- No `sleep_and_continue` helper is used
- No backoff delay is applied
- Creates tight loop if server consistently returns 408

**Worst Case Scenario**:
- Server under load returns 408
- Client recurses immediately, 1000+ times per second
- All pending HTTP requests complete in milliseconds
- CPU core pinned at 100% until poll_timeout expires
- With `poll_timeout: 60_000` (60 seconds), 60,000+ requests generated from single client
- With 1000 concurrent polling tasks, 60 million requests to server in 60 seconds

## Issue 2: Immediate Retry Without Backoff for 5xx Status (CRITICAL)

**Location**: Lines 225-229

**Code**:
```elixir
{:error, %Error{status: status} = error}
when is_integer(status) and status >= 500 and status < 600 ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # No sleep - immediate retry like Python SDK
  poll_loop(%{state | last_failed_error: error}, iteration + 1)
```

**Problem**:
- HTTP 5xx (Server Errors: 500, 502, 503, etc.) trigger immediate recursive call
- All server error responses retry with zero delay
- Violates established backoff pattern used for connection errors (lines 231-239)
- 503 Service Unavailable from an overloaded server gets hammered with no backoff

**Scenario**:
```
Server: "I'm overloaded, 503 Service Unavailable"
Client: "OK, let me retry immediately"
Server: "Still overloaded, 503"
Client: "Retry immediately again"
[Repeats thousands of times per second]
Server: "Actually goes down under the load"
```

## Issue 3: Stack Overflow Risk from Unbounded Recursion

**Location**: Lines 171, 190, 196, 220, 229, 303

**Code Path**:
```
poll_loop(state, 0)
  → do_poll(state, 0)
    → [if 408] poll_loop(state, 1)
      → do_poll(state, 1)
        → [if 408] poll_loop(state, 2)
          ...continues...
```

**Problem**:
- Each 408/5xx retry adds a stack frame via recursive call
- No tail call optimization prevents stack buildup
- After N iterations, stack contains N frames
- Stack exhaustion possible after 10,000+ iterations

## Issue 4: Unbounded Iteration Counter

**Location**: Lines 329-335, telemetry at 181, 201, 446

**Problem**:
- Iteration counter increments infinitely
- No maximum iteration guard
- Telemetry pollution with large iteration numbers
- No circuit breaker for runaway loops

## Root Cause

**Why This Bug Exists**:
1. Comments cite "Python SDK parity" for 408/5xx retry-without-backoff (lines 214-216, 222-224)
2. Assumption that immediate retry is correct may be mistaken
3. Inconsistent with connection error handling (which DOES use backoff)

## Recommended Fixes

### Fix 1: Add Minimum Backoff to 408/5xx Retries

```elixir
# Line 217:
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  sleep_and_continue(
    %{state | last_failed_error: error},
    max(100, calc_backoff(iteration)),  # Minimum 100ms backoff
    iteration
  )

# Line 225:
{:error, %Error{status: status} = error}
when is_integer(status) and status >= 500 and status < 600 ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  sleep_and_continue(
    %{state | last_failed_error: error},
    calc_backoff(iteration),  # Use exponential backoff
    iteration
  )
```

### Fix 2: Add Maximum Iteration Guard

```elixir
# At start of poll_loop:
defp poll_loop(_state, iteration) when iteration > 1000 do
  {:error, Error.new(
    :api_timeout,
    "Polling exceeded maximum iterations (1000)",
    data: %{iterations: iteration}
  )}
end
```

### Fix 3: Use Tail Recursion or Trampoline

Convert to tail-recursive form or use trampoline pattern to avoid stack buildup.

## Impact on Test Stability

**Why Tests Became Unstable After v0.3.3**:

1. **Before:** HTTP layer had retries with backoff → implicit delays buffered timing issues
2. **After:** `max_retries: 0` on polling + no backoff on 408/5xx → tight loops exposed
3. **Test isolation improvements** removed shared state buffering → races more visible
4. **Tests now reveal the real bug** that was hidden before

**Conclusion**: The test suite redesign was CORRECT. Tests are unstable because they're exposing a real production bug (tight retry loops).

---

**Findings saved to**: `docs/20251226/design_research/02_future_polling_analysis.md`
