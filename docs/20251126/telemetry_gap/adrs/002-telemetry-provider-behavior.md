# ADR 002 – Telemetry Provider Behaviour

## Status
Proposed

## Context
- Telemetry startup is embedded in `ServiceClient.maybe_start_telemetry_reporter/2`; no shared contract for other clients.
- Python exposes `TelemetryProvider` + `init_telemetry()` used by decorators.
- We need uniform access to reporter pids and a safe bootstrap helper.

## Decision
Introduce provider behaviour + init helper:
- `Tinkex.Telemetry.Provider` behaviour with callback `get_telemetry/0`.
- `__using__/1` macro provides default `get_telemetry/0` (overridable).
- `Tinkex.Telemetry.init/1` (or in provider) starts reporter with `session_id`, `config`, optional `enabled?`, `telemetry_opts`; returns `{:ok, pid} | :ignore | {:error, term}`.
- Respect env `TINKER_TELEMETRY`; treat `{:error, {:already_started, pid}}` as success.

## Consequences
**Positive:** Standard interface; reusable bootstrap; clearer lifecycle (start/stop); parity with Python provider.  
**Negative:** Migration work in clients; one more abstraction to document.  
**Neutral:** Reporter remains unchanged; opt-in per module.

## Implementation Notes
- Module layout: `lib/tinkex/telemetry/provider.ex`; helper near reporter.  
- Validation: ensure `:session_id` and `:config` present; boolean check for `enabled?`.  
- Clients (Service/Sampling/Training) store pid in state, expose `get_telemetry/0`, stop reporter in `terminate/2`.

## Tests
- Behaviour enforces callback; default returns nil when unset.  
- `init/1` returns :ignore when disabled; returns pid when enabled; passes opts; handles already_started; errors on missing required opts.  
- Client integration test: reporter stopped on terminate.

## Rollout
1) Add behaviour + helper + tests.  
2) Migrate ServiceClient to use helper; add terminate stop.  
3) Adopt in SamplingClient/TrainingClient.  
4) Update docs and examples.***
