# Critical Findings - Immediate Issues

**Date:** 2025-12-26
**Status:** URGENT - Potential Production Issues Identified

## 🔴 CRITICAL: Tight Loop in Future Polling (lib/tinkex/future.ex)

### The Problem

**Location:** `lib/tinkex/future.ex:213-227`

The Future polling loop will **spin without delay** when the server returns 408 or 5xx errors:

```elixir
# Line 213-217: 408 handling
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # No sleep - immediate retry like Python SDK
  poll_loop(%{state | last_failed_error: error}, iteration + 1)

# Line 219-227: 5xx handling
{:error, %Error{status: status} = error}
when is_integer(status) and status >= 500 and status < 600 ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # No sleep - immediate retry like Python SDK
  poll_loop(%{state | last_failed_error: error}, iteration + 1)
```

### Why This is Bad

1. **Resource Exhaustion:** Tight loop consumes CPU, hammers server, floods logs
2. **Network Amplification:** Could DoS your own backend during outages
3. **Test Instability:** Tests with short poll_timeout will spin hard until timeout
4. **Production Risk:** Server under load → more 5xx → tighter loop → more load

### Reproduction Scenario

```elixir
# Server returns 503 consistently:
Bypass.stub(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
  resp(conn, 503, %{"message" => "Service unavailable"})
end)

task = Future.poll("req-1", config: config, timeout: 100)
# This will spin in a tight loop for 100ms, making hundreds of requests
```

### Why Tests Became Unstable

**Before v0.3.3:**
- HTTP layer had retries with backoff
- Transient 5xx errors would sleep, giving server time to recover
- Tests had implicit delays from retry backoff

**After v0.3.3:**
- `max_retries: 0` on polling HTTP calls (line 197 in do_poll)
- Polling loop handles retries but **with no backoff for 408/5xx**
- Tests now hit tight loops, timeouts, and resource contention

### Impact on Test Suite

The test redesign for concurrency likely:
1. Reduced shared state (good)
2. Exposed the tight loop issue (was hidden by HTTP retry delays)
3. Made timing more sensitive (isolation = less buffering)

**This explains why tests got WORSE after the redesign** - they're now revealing a real bug.

## 🔴 CRITICAL: Missing Backoff on Connection Errors

**Location:** `lib/tinkex/future.ex:229-237`

Connection errors DO have backoff:
```elixir
{:error, %Error{type: :api_connection} = error} ->
  emit_error_telemetry(telemetry_event_for_error(error), error, iteration, state)
  sleep_and_continue(
    %{state | last_failed_error: error},
    calc_backoff(iteration),
    iteration
  )
```

But this creates **inconsistent behavior**:
- Connection error → backoff (good)
- Server 503 error → no backoff (bad)

Both should have backoff to avoid overwhelming the system.

## 🟡 MEDIUM: HTTP Timeout Changed Without Migration

**Location:** `lib/tinkex/future.ex:128`

```elixir
# Before v0.3.3:
http_timeout: Keyword.get(opts, :http_timeout, config.timeout)

# After v0.3.3:
http_timeout: Keyword.get(opts, :http_timeout, @default_polling_http_timeout)
```

**Impact:**
- Users who set `config.timeout` expecting it to apply to polling will be surprised
- Polling now always uses 45s unless explicitly overridden
- Not a bug, but a **breaking behavioral change**

## 🟡 MEDIUM: Backoff Iteration Capping

**Location:** `lib/tinkex/future.ex:327-333`

```elixir
defp calc_backoff(iteration) when is_integer(iteration) and iteration >= 0 do
  # Cap iteration to prevent math.pow overflow
  capped_iteration = min(iteration, 5)
  backoff = trunc(:math.pow(2, capped_iteration)) * @initial_backoff
  min(backoff, @max_backoff)
end
```

**Analysis:**
- Caps at iteration 5 → max backoff ~30s (with cap)
- **Question:** What happens after iteration 5? Backoff stays constant.
- **Concern:** If tight loop runs 1000 iterations, they'll all use the same 30s backoff after iteration 5
- **Mitigation:** The cap prevents overflow (good) but doesn't prevent long-running loops

## Root Cause Hypothesis

### Why Tests Are Flaky Now

**Theory:** The v0.3.3 changes created a **tight retry loop** that:
1. Spins rapidly on 408/5xx errors
2. Consumes resources (CPU, network, file descriptors)
3. Causes timeouts in tests that expect bounded behavior
4. Makes tests race-sensitive (whoever hits the loop first affects others)

**Evidence:**
- User says tests were MORE stable before the redesign
- The redesign improved isolation (should help) but tests got worse (reveals bug)
- The 408/5xx handling has **no backoff** unlike connection errors
- HTTP layer retries were disabled (`max_retries: 0`)

### Why This is Hard to Test

The code is **fundamentally hard to test** because:
1. **Tight coupling:** Polling behavior depends on server response patterns
2. **Non-deterministic timing:** No backoff = races everywhere
3. **Resource sharing:** ETS, processes, ports all shared across tests
4. **Missing invariants:** No maximum iteration count, no rate limiting on polling

## Recommended Fixes

### Fix 1: Add Minimum Backoff to 408/5xx Retries

```elixir
# In lib/tinkex/future.ex:213
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # Add small delay to prevent tight loop
  sleep_and_continue(
    %{state | last_failed_error: error},
    100,  # Minimum 100ms backoff
    iteration
  )

# Similar for 5xx
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
defp poll_loop(state, iteration) when iteration > 1000 do
  {:error, Error.new(
    :api_timeout,
    "Polling exceeded maximum iterations (1000)",
    data: %{iterations: iteration, request_id: state.request_id}
  )}
end

defp poll_loop(state, iteration) do
  # ... existing logic
end
```

### Fix 3: Add Circuit Breaker to Polling

The codebase has `CircuitBreaker` but it's not applied to the polling loop itself. Consider adding:

```elixir
# Wrap Futures.retrieve call in circuit breaker per request_id or endpoint
```

## Test Impact Analysis

### Why HuggingFace 403s Appear Now

The tokenizer tests are marked `@tag :network` and hit HuggingFace APIs. The 403s are likely:
1. **Rate limiting** from HuggingFace (GitHub CI IP shared across many projects)
2. **Auth changes** at HuggingFace (recent policy update?)
3. **Timing:** Tests run faster now → hit rate limit sooner

**Recommendation:** Mock tokenizer downloads in tests, only test network I/O in dedicated suite.

### Why Other Tests Might Be Failing

If the tight loop issue exists, tests could fail due to:
1. **Timeouts:** Test finishes before tight loop completes
2. **Resource exhaustion:** Too many processes/connections spawned
3. **Interference:** Multiple tests hit same tight loop simultaneously
4. **Non-deterministic timing:** Race to who times out first

## Action Items

1. **URGENT:** Add backoff to 408/5xx retry paths in Future.poll_loop
2. **HIGH:** Add maximum iteration guard to prevent runaway loops
3. **MEDIUM:** Review all tests for timing assumptions
4. **MEDIUM:** Mock external network calls (HuggingFace)
5. **LOW:** Document the HTTP timeout change as breaking

## Testing the Fix

Create a test that verifies backoff exists:

```elixir
test "polling adds delay on 408 errors" do
  delays = :counters.new(1, [:atomics])

  sleep_fun = fn ms ->
    :counters.add(delays, 1, ms)
  end

  # Stub server returning 408 twice, then success
  # ...

  task = Future.poll("req", config: config, sleep_fun: sleep_fun)
  assert {:ok, _} = Task.await(task)

  # Should have slept at least once
  assert :counters.get(delays, 1) > 0
end
```

---

**Status:** Waiting for agent analysis to confirm/refute these findings.
