# Test Instability Root Cause Investigation

**Date:** 2025-12-26
**Context:** Tests became less stable after v0.3.3 concurrency redesign
**Status:** Investigation Complete - 12 bugs identified

## Quick Navigation

| Document | Focus | Critical Findings |
|----------|-------|-------------------|
| [00_critical_findings.md](00_critical_findings.md) | Executive summary | Tight polling loops, test paradox explained |
| [01_initial_investigation.md](01_initial_investigation.md) | Git history | Recent commits, change analysis |
| [02_future_polling_analysis.md](02_future_polling_analysis.md) | Future.ex deep dive | 408/5xx immediate retry (CRITICAL) |
| [03_ets_concurrency_analysis.md](03_ets_concurrency_analysis.md) | ETS patterns | 9 race conditions in registries/caches |
| [04_test_suite_analysis.md](04_test_suite_analysis.md) | Test redesign | Supertester 0.4.0 migration, isolation benefits |
| [05_client_state_management.md](05_client_state_management.md) | GenServer bugs | 9 issues in client lifecycle |
| [99_synthesis_and_recommendations.md](99_synthesis_and_recommendations.md) | **START HERE** | Complete findings + prioritized fixes |

## The Paradox: Why Did Tests Get Worse?

**Short Answer:** Tests are now exposing real production bugs that were hidden by accidental timing and shared state.

**The Test Redesign Was Correct:**
- Moved from `async: false` to `async: true` ✅
- Added proper telemetry/logger/ETS isolation ✅
- Used `start_supervised!` for clean teardown ✅

**The Code Had Bugs:**
- Tight polling loops on 408/5xx (no backoff)
- ETS race conditions in registries
- Atomics lost-update bugs in rate limiter
- Memory leaks in persistent_term usage

**Conclusion:** Fix the code, not the tests.

## Critical Issues Found

### 🔴 CRITICAL (Fix Today)

1. **Tight Polling Loop** (`lib/tinkex/future.ex:217-229`)
   - 408/5xx retry immediately without backoff
   - Can generate 60,000+ requests in 60 seconds
   - **ROOT CAUSE of test timeouts**

2. **ETS Registration Race** (`lib/tinkex/sampling_client.ex:233`)
   - Client usable before ETS entry exists
   - Causes "not initialized" errors

### 🟠 HIGH (Fix This Week)

3. **RateLimiter TOCTOU Race** (`lib/tinkex/rate_limiter.ex:14-33`)
   - Duplicate atomics refs created
   - Rate limiting broken under concurrency

4. **Background Task Monitoring** (`lib/tinkex/training_client.ex:979-1021`)
   - Complex monitor-task-task pattern
   - Silent error suppression

### 🟡 MEDIUM (Fix Next Sprint)

5-9. Various ETS races, persistent term leaks, semaphore inefficiencies

## How to Use This Research

1. **Read:** Start with `99_synthesis_and_recommendations.md` for complete overview
2. **Understand:** Read `02_future_polling_analysis.md` for the main bug
3. **Fix:** Apply fixes in priority order from synthesis document
4. **Test:** Verify with reproduction scenarios from each analysis
5. **Deploy:** Update changelog, docs, and notify users

## Key Metrics

- **Investigation Time:** 4 hours (parallel agent analysis)
- **Documents Created:** 7 comprehensive analyses
- **Lines of Analysis:** ~5000
- **Bugs Found:** 12 (2 critical, 2 high, 5 medium, 3 low)
- **Estimated Fix Time:** 56 hours (~1.5 weeks)

## Next Steps

1. Apply P1 fixes (tight loop, registration race)
2. Re-run test suite
3. Apply P2 fixes (rate limiter, task monitoring)
4. Add regression tests
5. Deploy with changelog update

---

**Investigation Team:**
- Agent a0c2f77: Future polling analysis
- Agent ab2bc6b: ETS concurrency analysis
- Agent a8a3331: Test suite analysis
- Agent a0475be: Client state management analysis
- Primary Analysis: Critical findings and synthesis

**Status:** ✅ Investigation Complete, Ready for Implementation
