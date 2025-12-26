# Tinkex Test Infrastructure Overhaul

## Executive Summary

This document specifies a comprehensive refactoring of Tinkex's test infrastructure to eliminate all sources of test flakiness. The changes leverage Supertester v0.4.0's new global state isolation features.

---

## Problem Statement

The Tinkex test suite exhibits intermittent failures when run with `async: true`. Three distinct flakiness patterns have been identified:

| Test File | Failure Type | Root Cause |
|-----------|--------------|------------|
| `test/tinkex/future/poll_test.exs` | Wrong telemetry metadata | Telemetry cross-talk between async tests |
| `test/tinkex/tokenizer/encode_test.exs` | Agent cleanup crash | Race condition in linked process cleanup |
| `test/tinkex/api/api_test.exs` | Missing log content | Global Logger level mutation |

Additionally, `test/tinkex/future_test.exs` was recently modified with an ad-hoc `MockHTTPClient` pattern that is inconsistent with the codebase's established patterns (HTTPCase + Bypass).

---

## Solution Overview

### Dependencies

- **Supertester v0.4.0**: Provides TelemetryHelpers, LoggerIsolation, and ETSIsolation modules
- **Existing Infrastructure**: HTTPCase, Bypass, start_supervised!

### Changes Required

| File | Change Type | Description |
|------|-------------|-------------|
| `mix.exs` | Dependency | Upgrade supertester to ~> 0.4.0 |
| `test/support/http_case.ex` | Refactor | Use TelemetryHelpers instead of manual attach |
| `test/tinkex/future_test.exs` | Rewrite | Replace MockHTTPClient with HTTPCase + Bypass |
| `test/tinkex/future/poll_test.exs` | Refactor | Use TelemetryHelpers.assert_telemetry |
| `test/tinkex/tokenizer/encode_test.exs` | Refactor | Use start_supervised!, ETSIsolation |
| `test/tinkex/api/api_test.exs` | Refactor | Use LoggerIsolation.capture_isolated! |
| `lib/tinkex/tokenizer.ex` | Minor | Support table injection for testing |

### Non-Goals

- No changes to production code behavior
- No changes to public API
- No removal of existing test coverage

---

## Architecture

### Before

```
┌─────────────────────────────────────────────────────────────────┐
│                    Test Infrastructure                           │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   HTTPCase    │     │  ExUnit.Case  │     │  ExUnit.Case  │
│  (Bypass)     │     │  (ad-hoc)     │     │  (ad-hoc)     │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
  poll_test.exs        future_test.exs      encode_test.exs
                       (MockHTTPClient)      api_test.exs
```

**Problems**:
- Inconsistent patterns across test files
- Manual telemetry handler management
- Global state mutations (Logger, ETS)
- Ad-hoc mocking approaches

### After

```
┌─────────────────────────────────────────────────────────────────┐
│                 Supertester.ExUnitFoundation                     │
│   isolation: :full_isolation                                     │
│   telemetry_isolation: true                                      │
│   logger_isolation: true                                         │
│   ets_isolation: [:tinkex_tokenizers]                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Tinkex.HTTPCase                               │
│   (extends ExUnitFoundation with Bypass)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
  All test files use consistent HTTPCase or ExUnitFoundation
  All use TelemetryHelpers for telemetry testing
  All use LoggerIsolation for log capture
  All use ETSIsolation for cache testing
```

**Benefits**:
- Consistent patterns everywhere
- Automatic isolation and cleanup
- No manual handler management
- Zero global state mutation

---

## Document Index

| Document | Description |
|----------|-------------|
| [01-root-cause-analysis.md](./01-root-cause-analysis.md) | Detailed analysis of each failure |
| [02-future-test-refactor.md](./02-future-test-refactor.md) | Refactoring future_test.exs |
| [03-poll-test-refactor.md](./03-poll-test-refactor.md) | Refactoring poll_test.exs |
| [04-encode-test-refactor.md](./04-encode-test-refactor.md) | Refactoring encode_test.exs |
| [05-api-test-refactor.md](./05-api-test-refactor.md) | Refactoring api_test.exs |
| [06-http-case-refactor.md](./06-http-case-refactor.md) | Updating http_case.ex |
| [07-verification-plan.md](./07-verification-plan.md) | How to verify the fixes |

---

## Success Criteria

1. **Zero flaky tests**: 100 consecutive `mix test` runs with different seeds, all pass
2. **All tests async**: Every test file uses `async: true`
3. **Consistent patterns**: All tests use HTTPCase or ExUnitFoundation
4. **No global mutations**: No calls to `Logger.configure/1` or `:ets.delete_all_objects` on shared tables
5. **Automatic cleanup**: No manual `on_exit` for process/table cleanup

---

## Implementation Order

Execute in this order to minimize risk:

1. **Upgrade Supertester** (`mix.exs`)
2. **Update HTTPCase** (`test/support/http_case.ex`)
3. **Fix poll_test.exs** (telemetry assertions)
4. **Fix encode_test.exs** (Agent cleanup, ETS isolation)
5. **Fix api_test.exs** (Logger isolation)
6. **Rewrite future_test.exs** (replace MockHTTPClient)
7. **Verification** (100-run flakiness check)

Each step is independent and can be verified before proceeding.

---

## Timeline

No time estimates provided per project standards. Each step is a discrete unit of work that can be completed and verified independently.
