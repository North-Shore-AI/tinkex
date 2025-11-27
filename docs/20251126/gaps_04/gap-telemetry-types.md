# GAP: Telemetry Type Parity (Python → Elixir)

## Status
- **Python (tinker/src/tinker/types/…)**: `GenericEvent`, `SessionStartEvent`, `SessionEndEvent`, `UnhandledExceptionEvent`, `TelemetryEvent` union, `TelemetryBatch`, `TelemetrySendRequest`, `EventType` (`SESSION_START | SESSION_END | UNHANDLED_EXCEPTION | GENERIC_EVENT`), `Severity` (`DEBUG|INFO|WARNING|ERROR|CRITICAL`).
- **Elixir (lib/tinkex/types/…)**: None of the above structs or enums exist; telemetry payloads are anonymous maps built in `Tinkex.Telemetry.Reporter` (e.g., `build_generic_event/4` at reporter.ex) and sent as untyped maps via `Tinkex.API.Telemetry`.

## Why It Matters
- **Parity/Schema Drift**: Without typed structs, SDK users cannot construct or pattern-match telemetry events consistently with Python. Cross-language docs/examples referencing `GenericEvent`/`TelemetryEvent` cannot be mirrored.
- **Validation & Encoding**: Structs would provide compile-time shape guarantees and centralized encoding/redaction logic (e.g., masking fields) instead of ad-hoc map building.
- **Testing & Tooling**: Missing types make it hard to unit-test telemetry payload conformance or to generate docs automatically.

## Evidence
- Absence in Elixir: `rg "GenericEvent" lib/tinkex` → no hits.
- Python definitions: `tinker/src/tinker/types/generic_event.py:1-28`, `event_type.py:1-7`, `severity.py:1-5`, `telemetry_event.py:5-13`, plus session events/unhandled_exception event types.
- Reporter emits raw maps: `lib/tinkex/telemetry/reporter.ex` (`build_generic_event/4`, `build_unhandled_exception/3`, `build_session_start_event/1`, etc.) return bare maps without typed wrappers.

## Proposed Solution (Elixir)
1. **Add Types** under `lib/tinkex/types/`:
   - `generic_event.ex`, `session_start_event.ex`, `session_end_event.ex`, `unhandled_exception_event.ex`, `event_type.ex` (atom/string union), `severity.ex` (atom/string union), `telemetry_event.ex` (sum type), `telemetry_batch.ex` (list + metadata), `telemetry_send_request.ex`.
   - Include `from_map/1` / `to_map/1` helpers and `@type t` specs.
2. **Reporter Refactor**:
   - Replace ad-hoc maps with typed structs and call `to_map/1` before POST.
   - Centralize redaction/sanitization in type modules where needed.
3. **API Layer**:
   - Update `Tinkex.API.Telemetry.send*/2` to accept structs or maps; normalize via `TelemetrySendRequest.to_map/1`.
4. **Tests**:
   - Add unit tests validating `from_map/1`/`to_map/1` round-trips and reporter emission shapes (e.g., `test/tinkex/telemetry_types_test.exs`).
   - Ensure new severity/event enums match Python literals.
5. **Docs**:
   - Document the types and how to emit custom `GenericEvent`s from user code (if exposed).

## Effort
- Estimated 3–4 hours including tests and reporter refactor.
