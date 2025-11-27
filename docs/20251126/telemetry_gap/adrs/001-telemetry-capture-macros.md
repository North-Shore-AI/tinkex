# ADR 001 – Telemetry Capture Macros

## Status
Proposed

## Context
- Tinkex requires manual `try/rescue` + reporter calls; Python has `@capture_exceptions` / `acapture_exceptions`.
- Boilerplate leads to missed telemetry and inconsistent severity/fatal handling.
- Async tasks also need consistent capture.

## Decision
Add `Tinkex.Telemetry.Capture` (macro-only, no runtime deps):
- `capture_exceptions/2`, `with_telemetry/2` block macros, `async_capture/2` helper.
- Options: `:reporter` (pid | via | nil → no-op), `:fatal?` (default false), `:severity` (default `:error`).
- Expansion wraps block in `try/rescue/catch`, calls `Reporter.log_exception/3` or `log_fatal_exception/3`, then re-raises with `__STACKTRACE__`.

## Consequences
**Positive:** Boilerplate removal; parity with Python ergonomics; safe no-op when telemetry disabled; works for Tasks.  
**Negative:** Macro debugging noise in stacks; still must pass reporter pid explicitly.  
**Neutral:** Not a function decorator; explicit opt-in per module.

## Implementation Notes
- Pure macros (`__using__` imports only).  
- Hygiene: unique vars, `Macro.escape/1` for opts; preserve `__STACKTRACE__`.  
- `async_capture/2` wraps `Task.async` with same logging/re-raise behavior.

## Tests
- Unit: nonfatal logs + re-raises; fatal logs + enqueues SESSION_END; async variant logs; nil reporter is no-op.  
- Macro-expansion smoke test ensures `try/rescue` shape.

## Rollout
1) Ship module + tests.  
2) Wire into SamplingClient/TrainingClient hot paths where exceptions were manually logged.  
3) Add docs examples and migrate high-traffic call sites.  
4) Optional follow-up: module attribute default reporter.***
