# Initial Investigation: Test Instability Analysis

**Date:** 2025-12-26
**Investigator:** Claude (Automated Analysis)
**Context:** Test suite became less stable after v0.3.3 release despite attempt to fix concurrency issues

## Executive Summary

Investigating potential root cause issues in the Tinkex codebase following test instability reports. Tests were redesigned to fix concurrency issues but paradoxically became MORE unstable. This suggests either:
1. Tests are now revealing real flakiness in the code
2. Fundamental design issues make the code hard to test reliably
3. Recent changes introduced new race conditions

## Error Summary

### GitHub CI Failures
- **Status:** 2 test failures, both network-related HuggingFace tokenizer downloads (403 errors)
- **Impact:** Not code-related, likely API rate limiting or auth issues
- **Tests Affected:**
  - `Tinkex.Tokenizer.EncodeTest` - "encode caches tokenizer by resolved id"
  - `Tinkex.Types.ModelInputFromTextTest` - "encodes text into an encoded_text chunk"
- **Root Cause:** HuggingFace API returning 403 during tokenizer download
- **Severity:** LOW - Environmental issue, not code bug

### Local Failures
- **Status:** User reports "gone" - resolved
- **No details provided**

## Recent Commit Analysis

### Commit 1: `15fe376` - "refactor: relax table identifier validation" (Dec 26)
**Files Changed:** `lib/tinkex/tokenizer.ex`
**Purpose:** Fix dialyzer error occurring only on GitHub CI due to OTP version differences
**Change Details:**
```elixir
# Before:
defp ensure_table_for(table) when is_reference(table) do
  validate_table_reference!(table)
  table
end

defp ensure_table_for(table) when is_atom(table) do
  ensure_named_table!(table)
end

# After:
defp ensure_table_for(table) when is_atom(table) do
  ensure_named_table!(table)
end

defp ensure_table_for(table) do
  validate_table_reference!(table)
  table
end
```

**Analysis:**
- Removed `is_reference(table)` guard
- Changed clause order to check atoms first, then fall through to validate_table_reference!
- This allows any valid ETS table identifier (not just references and atoms)
- **RISK ASSESSMENT:** LOW - This is a type widening that should not affect runtime behavior
- **POTENTIAL ISSUE:** Could accept invalid table types that later fail in :ets.info/1, but that would raise immediately, not cause flakiness

### Commit 2: `e0dbacb` - "Release v0.3.3" (Dec 25)
**Major Changes:**
1. **Future Polling Refactor** - CRITICAL CHANGES
2. Streaming sampling (new feature)
3. OpenTelemetry integration (opt-in)
4. Circuit breaker pattern (new feature)
5. Test isolation improvements via Supertester 0.4.0

## Critical Code Changes in v0.3.3

### 1. Future Polling Logic (`lib/tinkex/future.ex`)

#### Change: Infinite Retry on 408/5xx Without Backoff
```elixir
# NEW: Immediate retry on 408 (no sleep)
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  poll_loop(%{state | last_failed_error: error}, iteration + 1)

# NEW: Immediate retry on 5xx (no sleep)
{:error, %Error{status: status} = error}
when is_integer(status) and status >= 500 and status < 600 ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  poll_loop(%{state | last_failed_error: error}, iteration + 1)
```

**RISK ASSESSMENT:** **CRITICAL**
- **Potential Issue:** Tight loop when server consistently returns 408 or 5xx
- **Impact:** Could hammer server/network, exhaust resources
- **Python SDK Comparison:** Python has `continue` but within a while loop that has implicit delays
- **Mitigation:** Only `poll_timeout` prevents infinite loop
- **Reproduction Scenario:** Server under load returns 503 repeatedly → client spins in tight loop

#### Change: HTTP Timeout Default
```elixir
# Before:
http_timeout: Keyword.get(opts, :http_timeout, config.timeout)

# After:
http_timeout: Keyword.get(opts, :http_timeout, @default_polling_http_timeout)
```

**RISK ASSESSMENT:** MEDIUM
- Changed from user-configured timeout to hardcoded 45s
- Could cause unexpected behavior if users relied on config.timeout
- Not directly related to flakiness but changes timeout semantics

#### Change: Disabled HTTP Retries During Polling
```elixir
# NEW:
case Futures.retrieve(state.request_payload,
       config: state.config,
       timeout: state.http_timeout,
       max_retries: 0,  # <-- ADDED
       ...
```

**RISK ASSESSMENT:** MEDIUM
- HTTP layer no longer retries on transient failures
- Polling loop must handle ALL retry logic
- If polling loop has bugs, failures surface immediately

#### Change: Backoff Overflow Prevention
```elixir
defp calc_backoff(iteration) when is_integer(iteration) and iteration >= 0 do
  # Cap iteration to prevent math.pow overflow
  capped_iteration = min(iteration, 5)
  backoff = trunc(:math.pow(2, capped_iteration)) * @initial_backoff
  min(backoff, @max_backoff)
end
```

**RISK ASSESSMENT:** LOW
- Prevents overflow in backoff calculation
- Good defensive programming
- Should improve stability, not hurt it

### 2. Metadata Merging Changes

```elixir
# Added user_metadata merging into telemetry
metadata:
  opts[:telemetry_metadata]
  |> build_metadata(request_id)
  |> merge_user_metadata(config)
```

**RISK ASSESSMENT:** LOW
- Purely additive for observability
- No behavioral change

## Potential Root Causes

### Issue 1: Tight Polling Loop on Server Errors ⚠️ CRITICAL

**Symptom:** Tests may timeout or overwhelm server
**Location:** `lib/tinkex/future.ex:213-227`
**Root Cause:**
```elixir
# This creates a tight loop:
{:error, %Error{status: 408}} -> poll_loop(state, iteration + 1)
{:error, %Error{status: 5xx}} -> poll_loop(state, iteration + 1)
```

**Why This is Hard to Test:**
- If server returns consistent 408/5xx, polling spins without backoff
- Only `poll_timeout` prevents infinite loop
- Tests with short timeouts may hit this
- Real production scenario: Server under load → cascading failures

**Evidence:**
- Python SDK does `continue` but has rate limiting elsewhere
- No rate limiting added to Elixir implementation
- No circuit breaker applied to polling itself

**Recommendation:**
Add minimum backoff even for 408/5xx:
```elixir
{:error, %Error{status: 408} = error} ->
  emit_error_telemetry(@telemetry_api_error, error, iteration, state)
  # Add small delay to prevent tight loop
  state.sleep_fun.(100)  # 100ms minimum
  poll_loop(%{state | last_failed_error: error}, iteration + 1)
```

### Issue 2: max_retries: 0 on Polling Requests

**Location:** `lib/tinkex/future.ex:197`
**Analysis:**
- HTTP layer no longer retries connection failures
- Polling loop must catch ALL transient errors
- If polling loop misses an error case → immediate failure

**Test Impact:**
- Network blips surface immediately
- Tests more sensitive to timing
- Could explain increased flakiness

**Recommendation:**
- Keep `max_retries: 0` BUT ensure polling loop handles ALL error cases
- Add comprehensive error case coverage tests

### Issue 3: Test Isolation via Supertester

**Change:** Upgraded to Supertester 0.4.0 with ETS/telemetry/logger isolation
**Impact:** Tests now run in isolated environments

**Paradox:**
- Better isolation should reduce flakiness
- User reports tests got WORSE
- **Hypothesis:** Tests were accidentally hiding concurrency bugs via shared state
- Now that isolation is proper, real race conditions are exposed

**Evidence Needed:**
- Compare test failure patterns before/after isolation
- Check if failures involve ETS operations
- Look for Process.sleep or timing dependencies

## Next Steps

1. **Code Review:** Deep dive into Future.poll_loop for race conditions
2. **ETS Analysis:** Check SamplingRegistry, tokenizer cache for concurrent access bugs
3. **Test Pattern Analysis:** Review Supertester migration for timing assumptions
4. **Spawn Investigation Agents:**
   - Agent 1: Future polling and retry logic
   - Agent 2: ETS/shared state concurrency
   - Agent 3: Test suite patterns and timing
   - Agent 4: SamplingClient/TrainingClient GenServer state management

## Open Questions

1. What were the specific local errors that are now "gone"?
2. Are test failures consistent or random?
3. Do failures correlate with specific test files or patterns?
4. Is there a pattern to GitHub CI failures vs local?

## Investigation Status

- [x] Git log reviewed
- [x] Major changes identified
- [x] Critical risks catalogued
- [ ] Deep code review of polling logic
- [ ] ETS concurrency analysis
- [ ] Test pattern analysis
- [ ] Recommendations document

---

**Next Document:** `02_future_polling_deep_dive.md`
