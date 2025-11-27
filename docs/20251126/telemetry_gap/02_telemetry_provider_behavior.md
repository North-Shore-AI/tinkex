# TelemetryProvider behaviour + init helper

Goal: mirror tinker's  protocol +  helper so any client can expose a reporter uniformly and bootstrap it safely.

## API surface
- Behaviour  with callback .
- Helper :
  - Required: , .
  - Optional:  (env-aware),  (forwarded to Reporter).
  - Returns  or  (disabled) or .
- Convenience macro  to inject  and default .

## Implementation sketch
1. Create  with behaviour and .
2. Create init helper exposing :
   - Guard .
   - Start  with passed opts.
   - Trap  -> .
3. Update clients to use the provider.

## Tests
- New :
  - init returns :ignore when env disables telemetry.
  - init returns {:ok, pid} with valid config.
  - behaviour enforces .
