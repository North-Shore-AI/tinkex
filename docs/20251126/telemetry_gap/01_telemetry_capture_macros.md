# Telemetry capture helpers (decorator/context parity)

Goal: provide Elixir ergonomics equivalent to tinker's  /  decorators and context managers so any module can opt-in to telemetry exception logging without hand-coding .

## API surface
-  (macro) injects:
  -  macro to wrap arbitrary expressions.
  -  macro for block usage.
- Works for both sync and async code; accepts a pid (or lookup) for reporter.

## Implementation sketch
1. New module  (pure macros).
2. Macro options:
   -  (default false) -> call  else .
   -  (default :error).
   -  (pid | {:via, module, term} | nil). If nil, no-op.
3. Async helper:  returning task; wrapper attaches above try/rescue inside task.

## Wiring into clients
- , ,  can  and wrap risky boundaries.
- Consider optional module attribute  for compile-time default.

## Tests
- New :
  - Capture nonfatal -> logs once, re-raises.
  - Capture fatal -> logs + session_end enqueued.
  - Async variant propagates exceptions and logs.
  - No-op when reporter nil.
