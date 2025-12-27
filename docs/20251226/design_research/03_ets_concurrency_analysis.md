# ETS Concurrency Analysis Report

**Date**: 2025-12-26
**Status**: ISSUES FOUND - Multiple race conditions identified

## Executive Summary

The Tinkex SDK uses ETS tables for shared state management across processes. While the implementation shows awareness of concurrency (use of `read_concurrency: true`, `write_concurrency: true`), several race conditions exist that could manifest under high load, especially given the new test isolation improvements that may be exposing these issues.

## Critical Findings

### 1. SamplingRegistry: Multiple Monitors for Same Process (CRITICAL)

**File:** `lib/tinkex/sampling_registry.ex`
**Lines:** 31-47

**Race Condition:**
```elixir
def handle_call({:register, pid, config}, _from, state) do
  ref = Process.monitor(pid)
  :ets.insert(:tinkex_sampling_clients, {{:config, pid}, config})
  {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
end
```

**Problem:** If the same `pid` is registered concurrently:
- Both calls create different monitor refs (ref1, ref2)
- Both insert to ETS (second overwrites first - OK)
- Both add to monitors map with different refs
- When process dies, BOTH `:DOWN` messages fire
- Only first `:DOWN` cleans up ETS entry
- Second `:DOWN` has orphaned monitor ref

**Impact:** Monitor map grows unbounded with stale entries.

### 2. RateLimiter: insert_new/lookup Race (HIGH)

**File:** `lib/tinkex/rate_limiter.ex`
**Lines:** 14-33

**Race Condition:**
```elixir
case :ets.insert_new(:tinkex_rate_limiters, {key, limiter}) do
  true -> limiter
  false ->
    case :ets.lookup(:tinkex_rate_limiters, key) do
      [{^key, existing}] -> existing
      [] ->  # RACE: Entry was deleted between insert_new and lookup!
        :ets.insert(:tinkex_rate_limiters, {key, limiter})
        limiter
    end
end
```

**Problem:** If entry is deleted between `insert_new` failure and `lookup`:
- Creates NEW atomics ref instead of reusing existing
- Two different atomics refs for same `{base_url, api_key}` pair
- Rate limiting broken (different threads use different counters)

**Scenario:**
- Thread A sets backoff on atomics_ref1
- Thread B reads atomics_ref2 (sees no backoff)
- Rate limit bypass occurs

### 3. Tokenizer Cache: Duplicate Work Race (HIGH)

**File:** `lib/tinkex/tokenizer.ex`
**Lines:** 343-359

**Problem:** Same pattern as RateLimiter:
```elixir
case :ets.insert_new(table, {tokenizer_id, tokenizer}) do
  true -> {:ok, tokenizer}
  false ->
    case :ets.lookup(table, tokenizer_id) do
      [{^tokenizer_id, existing}] -> {:ok, existing}
      [] ->
        :ets.insert(table, {tokenizer_id, tokenizer})
        {:ok, tokenizer}
    end
end
```

**Impact:**
- Multiple threads could load expensive tokenizer objects
- Memory duplication (tokenizers are large NIFs)
- Cache inconsistency

### 4. CircuitBreaker: Lost Update Race (MEDIUM)

**File:** `lib/tinkex/circuit_breaker/registry.ex`
**Lines:** 73-81

**Problem:**
```elixir
def call(name, fun, opts \\ []) do
  cb = get_or_create(name, opts)  # Read
  {result, updated_cb} = CircuitBreaker.call(cb, fun, call_opts)  # Compute
  put(name, updated_cb)  # Write
  result
end
```

**Classic Read-Modify-Write Race:**
- Thread A reads CB (0 failures)
- Thread B reads CB (0 failures)
- Thread A increments: 1 failure, writes
- Thread B increments: 1 failure, writes
- **Result:** Should be 2 failures, but is 1 (lost update)

**Impact:** Circuit breaker might never open under high concurrency.

### 5. SessionManager: Orphaned Sessions During Init (MEDIUM)

**File:** `lib/tinkex/session_manager.ex`
**Lines:** 260-277

**Problem:**
```elixir
defp load_sessions_from_ets(table) do
  case :ets.whereis(table) do
    :undefined -> %{}
    _ ->
      :ets.foldl(fn {session_id, entry}, acc ->
        Map.put(acc, session_id, normalize_entry(entry))
      end, %{}, table)
  end
end
```

**Race:** Sessions inserted to ETS DURING foldl won't be loaded into state.sessions
**Impact:** Those sessions won't get heartbeats until next manager restart

## Why Tests Are Flaky

**Test Isolation Changes Exposed These Bugs:**

1. **Before v0.3.3:** Tests shared state, races were hidden by timing
2. **After v0.3.3:** Supertester 0.4.0 isolation → each test has clean ETS
3. **Result:** Races that were rare (1 in 1000 runs) now happen frequently

**Example:** RateLimiter race was masked when tests shared a global limiter. Now each test creates its own limiter, exposing the insert_new/lookup gap.

## Recommendations

1. **Use atomic ETS operations:** Replace check-then-act with single atomic op
2. **Add explicit locking:** Use GenServer serialization for critical sections
3. **Add stress tests:** 100+ concurrent operations to expose races
4. **Add assertions:** Verify ETS state matches expected invariants
5. **Document assumptions:** Make concurrent access patterns explicit

---

**Saved to:** `docs/20251226/design_research/03_ets_concurrency_analysis.md`
