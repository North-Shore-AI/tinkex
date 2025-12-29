# Generic Telemetry Reporter Library Design (Pachka-Based)

## Status
- Draft: 2025-12-27
- Target repo: `/home/home/p/g/n/telemetry_reporter`
- Source inventory: `lib/tinkex/telemetry.ex` and `lib/tinkex/telemetry/reporter.ex`
- Batching engine: `pachka` (~> 1.0.0)

## Repository and Branding Requirements
- Create repo via GitHub CLI under `nshkrdotcom` (user account, not org).
- Use a long, multi-sentence description (GitHub + `mix.exs`).
- Max out GitHub topics; the last topic must be `nshkr-observability`.
- Place hexagonal logo at `assets/telemetry_reporter.svg`.
- Add the logo at the top of `README.md` and wire it into `mix.exs` docs.

### Topics (maxed, last required)
```
elixir,erlang,beam,telemetry,observability,logging,metrics,events,batching,backoff,retry,queue,monitoring,instrumentation,sinks,http,sdk,client-side,pachka,nshkr-observability
```

### README + Docs Branding
- `README.md` top: `![TelemetryReporter](assets/telemetry_reporter.svg)`
- `mix.exs` docs:
  - `logo: "assets/telemetry_reporter.svg"`
  - `assets: %{"assets" => "assets"}`

## Problem Statement (Reporter Gap)
`:telemetry` standardizes emission, but handlers run synchronously in the
emitting process. Any blocking work (I/O, encoding, network) degrades request
latency. The ecosystem lacks a generic, vendor-agnostic reporter that buffers,
batches, and ships events to arbitrary backends while protecting the runtime
from overload and memory pressure. This is the "Reporter Gap."

## Current State Inventory (Tinkex)
- `lib/tinkex/telemetry.ex`: helper for attaching loggers and starting reporters.
- `lib/tinkex/telemetry/reporter.ex`: queue, batching, retry/backoff, session
  lifecycle events, and optional `:telemetry` event forwarding.
- `lib/tinkex/telemetry/reporter/backoff.ex`: unused duplicate of retry/backoff
  logic (likely cruft).
- `lib/tinkex/types/telemetry/*`: typed event structs, conversion to wire format.
- `Tinkex.API.Telemetry` transport used for sending.

## Core Engineering Constraints (from analysis)
- **Synchronous dispatch**: telemetry handlers must complete in microseconds.
- **Batching**: size + time dual-trigger is required for throughput and latency.
- **Memory pressure**: unbounded queues cause large mailboxes and GC overhead.
- **Load shedding**: backpressure is unacceptable; drop data instead.
- **Graceful shutdown**: drain buffers on exit to preserve last events.
- **Poison pills**: malformed events must be isolated, not crash the batch.

## Library Choice
### Pachka (selected)
- Purpose-built for message batching with time/size triggers.
- Built-in retries and overflow protection (`{:error, :overloaded}`).
- Clean Sink abstraction for transport-agnostic delivery.

### Broadway / GenBatchServer (not chosen)
- Broadway: useful for heavy transforms or partitioning; too heavy for the
  default reporter path and assumes backpressure.
- GenBatchServer: dynamic batch sizing is interesting but not needed for v1.

Decision: build `telemetry_reporter` on Pachka and expose opt-in hooks for
custom processing if needed later.

## Proposed Architecture (Pachka Pattern)
### Modules
- `TelemetryReporter`
  - Thin wrapper around `Pachka`.
  - API: `start_link/1`, `log/4`, `log_exception/3`, `flush/2`,
    `stop/2`, `wait_until_drained/2`.
  - All `:telemetry` handlers call `Pachka.send_message/2` only.

- `TelemetryReporter.Sink` (implements `Pachka.Sink`)
  - `send_batch/2` delegates to a transport module.
  - Uses `event_encoder` to map structs to wire maps.
  - Drops/isolates events that fail encoding (poison pill safety).

- `TelemetryReporter.Transport` (behaviour)
  - `send_batch(events, opts) :: :ok | {:error, term}`
  - HTTP transport in Tinkex implements `/api/v1/telemetry`.

- `TelemetryReporter.Event`
  - Minimal event struct or map with reserved fields:
    `id`, `timestamp`, `name`, `severity`, `data`, `metadata`.

- `TelemetryReporter.TelemetryAdapter`
  - Optional adapter for `:telemetry.attach_many`.
  - Filters and normalizes metadata; never blocks.

### Batching and Queue Behavior
- Dual triggers: `max_batch_size` and `max_batch_delay` (Pachka).
- Overflow: Pachka drops new messages once `critical_queue_size` is reached.
  Expose counters for dropped events and surface warnings via `:telemetry`.
- Do not apply backpressure to producers.

### Encoding Strategy
- Default to JSON with safe encoding (trap errors per event).
- Optional encoder for BERT (Erlang Term format) if backend is BEAM-native.
- Never crash a batch due to a single malformed event.

### Shutdown Semantics
- Ensure reporter starts before producers in supervision tree.
- On shutdown, rely on Pachka draining and a final flush.

## Tinkex Integration Plan
1. Extract reporter into `telemetry_reporter` with no Tinkex dependencies.
2. Implement `Tinkex.Telemetry.Transport` for `/api/v1/telemetry`.
3. Map Tinkex typed event structs to event maps via `event_encoder`.
4. Move session start/end logic into Tinkex wrapper or a session adapter.
5. Delete `Tinkex.Telemetry.Reporter.Backoff` and custom queueing code.

## Testing Plan
- Unit tests for Sink encoding, poison-pill handling, and transport failures.
- Pachka integration tests for batch size/time triggers and overflow behavior.
- Deterministic retry tests using Pachka backoff config.
- `:telemetry` handler attach/detach correctness.
- Drain semantics for `stop/2` and `wait_until_drained/2`.

## Risks and Mitigations
- **Drop policy mismatch**: Pachka drops new events; document this and expose
  counters so users see sampling loss.
- **Memory spikes**: enforce `critical_queue_size` and avoid large binary copies.
- **Schema drift**: keep schema at edge (Tinkex), use encoder hooks.

## Open Questions
- Should we offer a ring-buffer mode for drop-old semantics (v2)?
- Do we want an optional pre-aggregation layer for metrics-only pipelines?
- Should we ship a default HTTP transport or keep it as an example?
