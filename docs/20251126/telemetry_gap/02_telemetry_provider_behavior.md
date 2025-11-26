# TelemetryProvider behaviour + init helper

Goal: mirror tinker’s `TelemetryProvider` protocol + `init_telemetry` helper so any client can expose a reporter uniformly and bootstrap it safely.

## API surface
- Behaviour `Tinkex.Telemetry.Provider` with callback `get_telemetry() :: pid() | nil`.
- Helper `Tinkex.Telemetry.init(opts)`:
  - Required: `:session_id`, `:config`.
  - Optional: `:enabled?` (env-aware), `:telemetry_opts` (forwarded to Reporter).
  - Returns `{:ok, pid}` or `:ignore` (disabled) or `{:error, reason}`.
- Convenience macro `use Tinkex.Telemetry.Provider` to inject `@behaviour` and default `get_telemetry/0` using a struct field.

## Implementation sketch
1. Create `lib/tinkex/telemetry/provider.ex` with behaviour and `__using__/1`.
2. Create `lib/tinkex/telemetry/init.ex` (or add to provider) exposing `init/1`:
   - Guard `telemetry_enabled?/0` (reuse reporter util).
   - Start `Reporter.start_link/1` with passed opts.
   - Trap `{:error, {:already_started, pid}}` -> `{:ok, pid}`.
3. Update clients (`ServiceClient`, `SamplingClient`, `TrainingClient`) to:
   - `use Tinkex.Telemetry.Provider`.
   - Store `telemetry` pid in state; expose `get_telemetry/0`.
   - Call `Telemetry.init/1` during init with session_id/config; respect `enabled?`.
   - Stop reporter on terminate.

## Tests
- New `test/tinkex/telemetry_provider_test.exs`:
  - init returns :ignore when env disables telemetry.
  - init returns {:ok, pid} with valid config.
  - behaviour enforces `get_telemetry/0`.
  - Clients using `use Tinkex.Telemetry.Provider` expose the pid and stop reporter on terminate (use a test GenServer implementing behaviour).
