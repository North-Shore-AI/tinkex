# ADR 0002: Wrap client operations with telemetry exception capture

## Context
- Python client methods are decorated with `@capture_exceptions`, logging both fatal and nonfatal exceptions to backend telemetry.
- Elixir port ships `Tinkex.Telemetry.Capture`, but Service/Training/Sampling clients do not wrap calls, so crashes/raises are invisible to telemetry.

## Decision
- Add exception-capture wrappers around public client entrypoints (e.g., GenServer call boundaries in ServiceClient/TrainingClient/SamplingClient) using the existing `Tinkex.Telemetry.Capture` helpers and per-session reporter.
- Ensure fatal paths emit session-end events before shutdown, matching Python semantics.

## Consequences
- Exceptions surfaced to callers will now also emit telemetry; useful for reliability analysis and parity.
- Slight overhead per call; acceptable given parity and observability benefits.
- Tests need deterministic coverage to avoid noisy telemetry in failure cases.
