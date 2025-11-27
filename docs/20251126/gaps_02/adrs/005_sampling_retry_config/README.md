# ADR 005: Sampling Retry Configuration Gap Analysis

**Date:** 2025-11-26
**Status:** Analysis Complete
**Author:** Claude Code
**Priority:** HIGH

---

## Quick Links

- **[01_python_implementation.md](./01_python_implementation.md)** - Deep dive into Python retry system
- **[02_elixir_implementation.md](./02_elixir_implementation.md)** - Current Elixir implementation analysis
- **[03_gap_matrix.md](./03_gap_matrix.md)** - Feature-by-feature comparison
- **[04_implementation_spec.md](./04_implementation_spec.md)** - Detailed implementation plan
- **[05_test_plan.md](./05_test_plan.md)** - Comprehensive test strategy

---

## Executive Summary

### The Problem

The Elixir Tinkex SDK **lacks user-configurable retry configuration** for `SamplingClient`, despite having:
- ✅ Retry infrastructure (`Retry`, `RetryHandler` modules)
- ✅ Rate limiting (`RateLimiter`)
- ✅ Config struct with `max_retries` field

**Current state:** `Tinkex.API.Sampling` hardcodes `max_retries: 0` with a comment stating retry logic is "TODO"

### The Impact

**🔴 HIGH SEVERITY**

Without retry configuration:
- ❌ **No resilience** - Single network blip = failed request
- ❌ **No user control** - Cannot tune retry behavior per use case
- ❌ **No connection limiting** - Risk of pool exhaustion under load
- ❌ **No progress timeout** - Long requests can hang indefinitely
- 🔧 **Wrong defaults** - 100% jitter, 30-second timeout (should be 25%, 30 minutes)

### Compatibility Status

**45% feature parity** with Python SDK

| Category | Status |
|----------|--------|
| Core retry logic | ✅ Exists (but unused) |
| Rate limiting | ✅ Working |
| Retry configuration | ❌ Missing |
| Connection limiting | ❌ Missing |
| Progress watchdog | ❌ Missing |
| SamplingClient integration | ❌ Missing |

---

## Document Overview

### 01_python_implementation.md

**What it covers:**
- Complete analysis of Python's `RetryConfig` dataclass
- `RetryHandler` implementation with semaphore, progress watchdog
- Integration with `SamplingClient`
- Two-layer retry strategy (high-level + low-level)
- Exponential backoff with jitter formula
- LRU-cached handler construction

**Key findings:**
- Python uses **configurable retry** via `RetryConfig` parameter
- **No max attempts** - uses progress timeout instead (30 minutes)
- **Semaphore-based connection limiting** (max_connections=100)
- **Progress watchdog** in separate async task
- **Infinite retry with timeout** - more forgiving than hard limits

**Read time:** 15-20 minutes

---

### 02_elixir_implementation.md

**What it covers:**
- Current `SamplingClient` architecture (ETS-based lock-free pattern)
- `Tinkex.API.Sampling` hardcoded `max_retries: 0`
- Existing `Retry` and `RetryHandler` modules (unused)
- `RateLimiter` implementation for 429 backoff
- `Config` struct with unused `max_retries` field

**Key findings:**
- **Retry infrastructure exists** but not integrated
- **Intentional design:** HTTP layer retry disabled for "intelligent retry" at higher level
- **"Phase 4" never completed** - SamplingClient doesn't use retry handler
- **RateLimiter is better than Python** - shared per `{base_url, api_key}` instead of per client
- **Wrong defaults:** 100% jitter, 30-second timeout

**Read time:** 12-15 minutes

---

### 03_gap_matrix.md

**What it covers:**
- Side-by-side comparison of **every retry-related feature**
- Configuration defaults comparison
- Behavioral differences
- Missing functionality
- Bugs and wrong defaults
- Priority classification (Critical/High/Medium/Low)

**Key gaps identified:**

| Gap | Impact |
|-----|--------|
| SamplingClient retry integration | 🔴 **Critical** |
| retry_config parameter | 🔴 **Critical** |
| Connection semaphore | 🔴 **Critical** |
| Progress watchdog | 🔴 **Critical** |
| Jitter formula | 🔴 **Wrong formula** |
| Progress timeout default | 🔴 **30s vs 30min** |

**Read time:** 20-25 minutes

---

### 04_implementation_spec.md

**What it covers:**
- **Exact code changes** needed to implement retry config
- **4-phase implementation plan**:
  1. Fix existing modules (1-2 days)
  2. Create RetryConfig module (2-3 days)
  3. Integrate with SamplingClient (3-4 days)
  4. Add connection limiting (2-3 days, optional)
- Complete code examples for each phase
- Backward compatibility strategy
- Migration guide

**Deliverables:**

**New files:**
- `lib/tinkex/retry_config.ex`
- `lib/tinkex/retry_semaphore.ex` (optional)

**Modified files:**
- `lib/tinkex/retry_handler.ex` - Fix defaults, jitter, add from_config/1
- `lib/tinkex/rate_limiter.ex` - Fix wait_for_backoff/1
- `lib/tinkex/sampling_client.ex` - Add retry_config param, wrap do_sample
- `lib/tinkex/api/sampling.ex` - Use opts max_retries
- `mix.exs` - Add semaphore dependency (optional)

**Effort estimate:** 10-15 days (8-12 without semaphore)

**Read time:** 25-30 minutes

---

### 05_test_plan.md

**What it covers:**
- Unit tests for RetryConfig, RetryHandler, RateLimiter
- Integration tests for SamplingClient retry behavior
- Property-based tests for backoff calculation
- Load tests for connection limiting
- Edge case coverage
- Backward compatibility tests

**Test coverage targets:**
- Unit tests: 100%
- Integration: All critical paths
- Property: All math functions
- Load: Concurrency limits

**Read time:** 15-20 minutes

---

## Critical Findings

### 1. Wrong Defaults (Fix Immediately)

```elixir
# Current (WRONG)
@default_jitter_pct 1.0             # 100% jitter
@default_progress_timeout_ms 30_000 # 30 seconds

# Should be
@default_jitter_pct 0.25             # 25% jitter
@default_progress_timeout_ms 1_800_000 # 30 minutes
```

### 2. Wrong Jitter Formula (Fix Immediately)

```elixir
# Current (WRONG) - Range: 0% to 100% of delay
jitter = capped * handler.jitter_pct * :rand.uniform()

# Should be (CORRECT) - Range: ±25% of delay
jitter = capped * handler.jitter_pct * (2 * :rand.uniform() - 1)
final_delay = max(0, min(capped + jitter, handler.max_delay_ms))
```

### 3. Inefficient RateLimiter Wait (Fix Immediately)

```elixir
# Current (INEFFICIENT) - Polls every 100ms
def wait_for_backoff(limiter) do
  if should_backoff?(limiter) do
    Process.sleep(100)
    wait_for_backoff(limiter)  # Recursive
  else
    :ok
  end
end

# Should be (EFFICIENT) - Sleep exact duration once
def wait_for_backoff(limiter) do
  backoff_until = :atomics.get(limiter, 1)

  if backoff_until > 0 do
    now = System.monotonic_time(:millisecond)
    if backoff_until > now do
      wait_ms = backoff_until - now
      Process.sleep(wait_ms)
    end
  end

  :ok
end
```

---

## Implementation Roadmap

### Phase 1: Quick Wins (Week 1)

**Priority:** 🔴 **CRITICAL**
**Effort:** 1-2 days

- Fix RetryHandler defaults (jitter, timeout)
- Fix jitter calculation formula
- Fix RateLimiter wait loop

**Deliverable:** Existing retry logic works correctly (when used)

---

### Phase 2: Retry Configuration (Week 1-2)

**Priority:** 🔴 **CRITICAL**
**Effort:** 2-3 days

- Create `Tinkex.RetryConfig` module
- Match Python defaults
- Validation logic
- Documentation

**Deliverable:** User-facing retry configuration struct

---

### Phase 3: SamplingClient Integration (Week 2-3)

**Priority:** 🔴 **HIGH**
**Effort:** 3-4 days

- Add `retry_config` parameter to SamplingClient
- Wrap `do_sample/4` with `Retry.with_retry/2`
- Remove hardcoded `max_retries: 0`
- Backward compatibility testing

**Deliverable:** Full retry functionality for sampling

---

### Phase 4: Connection Limiting (Week 3-4)

**Priority:** 🟡 **MEDIUM** (optional but recommended)
**Effort:** 2-3 days

- Add `:semaphore` dependency
- Create `RetrySemaphore` manager
- Integrate with retry execution
- Load testing

**Deliverable:** Connection pool protection under load

---

### Phase 5: Testing (Ongoing)

**Priority:** 🔴 **HIGH**
**Effort:** 2-3 days

- Unit tests (100% coverage)
- Integration tests (critical paths)
- Property tests (math correctness)
- Load tests (concurrency)
- Backward compatibility

**Deliverable:** Comprehensive test suite

---

## Migration Strategy

### Zero Breaking Changes

All changes are **additive and opt-in**:

```elixir
# Still works (uses default retry config)
{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "meta-llama/Llama-3.2-1B"
)

# New usage (custom retry config)
retry_config = Tinkex.RetryConfig.new(max_retries: 5, max_connections: 50)

{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "meta-llama/Llama-3.2-1B",
  retry_config: retry_config  # NEW optional parameter
)
```

---

## Success Criteria

### Definition of Done

- [ ] RetryConfig module created with all fields from Python
- [ ] RetryHandler defaults match Python
- [ ] Jitter calculation matches Python formula
- [ ] RateLimiter wait is efficient
- [ ] SamplingClient accepts retry_config parameter
- [ ] API.Sampling uses configurable max_retries
- [ ] All unit tests pass (100% coverage)
- [ ] All integration tests pass
- [ ] Property tests verify math correctness
- [ ] Load tests verify connection limiting
- [ ] Backward compatibility maintained
- [ ] Documentation updated

### Metrics

**Target compatibility:** 95%+ feature parity with Python

**Current:** 45%
**After Phase 1:** 55%
**After Phase 2:** 70%
**After Phase 3:** 90%
**After Phase 4:** 95%

---

## Risk Assessment

### Low Risk (Green Light)

✅ **Backward compatible** - No breaking changes
✅ **Well-defined scope** - Clear requirements from Python
✅ **Modular changes** - Can be implemented incrementally
✅ **Infrastructure exists** - Retry modules already built

### Medium Risk (Monitor)

⚠️ **Testing effort** - Need comprehensive test coverage
⚠️ **Performance** - Connection limiting adds overhead
⚠️ **Elixir semantics** - Some patterns differ from Python async

### Mitigation

- **Phased rollout** - Fix bugs first, add features later
- **Feature flags** - Can disable retry if issues arise
- **Thorough testing** - Property tests for correctness
- **Load testing** - Verify no performance regression

---

## Related Work

### Dependencies

- **tinkex** - Core SDK (this repository)
- **semaphore** - Connection limiting (new dependency, optional)

### Follow-up Work

After this implementation:

1. **TrainingClient retry** - Apply same pattern to training API
2. **ServiceClient retry** - Apply same pattern to service API
3. **Progress watchdog** - Advanced feature for stuck request detection
4. **Retry metrics** - Telemetry dashboards for retry behavior

---

## References

### External Documentation

- [Python httpx Retry Documentation](https://www.python-httpx.org/)
- [Elixir Retry Library](https://hex.pm/packages/retry)
- [Semaphore Library](https://hex.pm/packages/semaphore)
- [Exponential Backoff - AWS Best Practices](https://aws.amazon.com/architecture/well-architected/)

### Internal Documentation

- Tinkex Architecture Overview
- Phase 4 Planning (incomplete)
- API Design Principles

---

## Appendix: Quick Reference

### Python Defaults

```python
max_connections = 100
progress_timeout = 1800.0  # 30 minutes
retry_delay_base = 0.5
retry_delay_max = 10.0
jitter_factor = 0.25  # ±25%
enable_retry_logic = True
```

### Elixir Current Defaults

```elixir
@default_max_retries 3
@default_base_delay_ms 500
@default_max_delay_ms 8_000
@default_jitter_pct 1.0  # WRONG: 100%
@default_progress_timeout_ms 30_000  # WRONG: 30 seconds
```

### Elixir Target Defaults

```elixir
@default_max_retries 10
@default_base_delay_ms 500
@default_max_delay_ms 10_000
@default_jitter_pct 0.25
@default_progress_timeout_ms 1_800_000
@default_max_connections 100
@default_enable_retry_logic true
```

---

## Document Metadata

| Property | Value |
|----------|-------|
| **Total Pages** | 5 documents + README |
| **Total Words** | ~25,000 |
| **Read Time** | 90-120 minutes (full deep dive) |
| **Implementation Time** | 10-15 days |
| **Test Coverage Target** | 95%+ |
| **Backward Compatibility** | 100% (zero breaking changes) |

---

**Status:** Ready for development
**Next Steps:** Begin Phase 1 (fix existing bugs)
**Owner:** TBD
**Due Date:** TBD
