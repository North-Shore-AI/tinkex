# Telemetry capture helpers (decorator/context parity)

Goal: provide Elixir ergonomics equivalent to tinker’s `capture_exceptions` / `acapture_exceptions` decorators and context managers so any module can opt‑in to telemetry exception logging without hand‑coding `try/rescue`.

## API surface
- `use Tinkex.Telemetry.Capture` (macro) injects:
  - `capture_exceptions(fun, opts \\ [])` macro to wrap arbitrary expressions.
  - `with_telemetry(fatal? \\ false, severity \\ :error, do: expr)` macro for block usage.
- Works for both sync and async code; accepts a pid (or lookup) for reporter.

## Implementation sketch
1. New module `Tinkex.Telemetry.Capture` (pure macros).
2. Macro options:
   - `:fatal?` (default false) -> call `Reporter.log_fatal_exception/3` else `log_exception/3`.
   - `:severity` (default :error).
   - `:reporter` (pid | {:via, module, term} | nil). If nil, no-op.
3. Macro expansion pattern (sync):
   ```elixir
   try do
     unquote(expr)
   rescue
     exception ->
       _ = reporter && if fatal?, do: Reporter.log_fatal_exception(reporter, exception, severity), else: Reporter.log_exception(reporter, exception, severity)
       reraise exception, __STACKTRACE__
   catch
     kind, reason ->
       ex = Exception.normalize(kind, reason, __STACKTRACE__)
       _ = reporter && (if fatal?, do: Reporter.log_fatal_exception(reporter, ex, severity), else: Reporter.log_exception(reporter, ex, severity))
       :erlang.raise(kind, reason, __STACKTRACE__)
   end
   ```
4. Async helper: `async_capture(fn -> ... end, opts)` returning task; wrapper attaches above try/rescue inside task.
5. Provide `@doc` describing parity with Python decorators; keep pure macros to remain guard-safe.

## Wiring into clients
- `ServiceClient`, `SamplingClient`, `TrainingClient` can `import Tinkex.Telemetry.Capture` and wrap risky boundaries (sampling calls, forward/backward, HTTP edges).
- Consider optional module attribute `@telemetry_reporter` for compile-time default; macro reads from caller env.

## Tests
- New `test/tinkex/telemetry_capture_test.exs`:
  - Capture nonfatal -> logs once, re-raises.
  - Capture fatal -> logs + session_end enqueued (Reporter mock via Mox).
  - Async variant propagates exceptions and logs.
  - No-op when reporter nil.
