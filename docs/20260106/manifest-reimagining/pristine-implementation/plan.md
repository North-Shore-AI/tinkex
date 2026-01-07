# Pristine Review → Full Implementation Plan

This plan is based on reviewing `~/p/g/n/pristine` and mapping it to the Tinker/Tinkex manifest‑driven requirements. It lists what Pristine already provides, the gaps against the Tinker SDK surface, and a phased implementation plan to reach full parity with a manifest‑defined SDK.

## Required Reading

Pristine (current state):
- `~/p/g/n/pristine/lib/pristine/manifest/schema.ex`
- `~/p/g/n/pristine/lib/pristine/manifest.ex`
- `~/p/g/n/pristine/lib/pristine/manifest/endpoint.ex`
- `~/p/g/n/pristine/lib/pristine/core/pipeline.ex`
- `~/p/g/n/pristine/lib/pristine/core/context.ex`
- `~/p/g/n/pristine/lib/pristine/codegen/*.ex`
- `~/p/g/n/pristine/lib/pristine/adapters/future/polling.ex`
- `~/p/g/n/pristine/lib/pristine/adapters/transport/finch.ex`
- `~/p/g/n/pristine/lib/pristine/adapters/transport/finch_stream.ex`
- `~/p/g/n/pristine/lib/pristine/ports/*`

Tinker Python SDK (source of truth):
- `~/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_base_client.py`
- `~/p/g/North-Shore-AI/tinkex/tinker/src/tinker/_client.py`
- `~/p/g/North-Shore-AI/tinkex/tinker/src/tinker/resources/*.py`
- `~/p/g/North-Shore-AI/tinkex/tinker/src/tinker/lib/*`
- `~/p/g/North-Shore-AI/tinkex/tinker/docs/api/*.md`

Examples:
- `~/p/g/North-Shore-AI/tinkex/examples/README.md`
- `~/p/g/North-Shore-AI/tinkex/examples/*.exs`

## Current Pristine Capabilities (Summary)

Manifest:
- Sinter‑validated schema with `endpoints`, `types`, `retry_policies`, `rate_limits`, `auth`, `defaults`, `middleware`.
- Endpoints are list‑based; each endpoint supports fields like `resource`, `retry`, `streaming`, `poll_endpoint`, `response_unwrap`, `transform`, `headers`, `query`, etc.

Core pipeline:
- Executes endpoints through transport + retry + rate limit + circuit breaker.
- Encodes payloads via serializer; supports JSON and multipart.
- Supports streaming execution (SSE) via `stream_transport`.
- Supports future polling via `Ports.Future` + `execute_future/5`.
- Handles redirect responses, response unwrapping, and error modules.

Ports/Adapters:
- Transport (Finch), Streaming (FinchStream), Multipart (multipart_ex), Retry (Foundation), Rate Limit (Foundation), Circuit Breaker (Foundation).
- Future polling adapter with retry/backoff + 408 queue state handling.
- Telemetry adapters for generic :telemetry events.
- Bytes semaphore and semaphore adapters exist but are not wired into pipeline.

Codegen:
- Generates client + resources + types.
- Uses `endpoint.async` → `execute_future/5`, `endpoint.streaming` → `execute_stream/5`.
- Lacks flow/composite method generation; no explicit surface naming control beyond namespace.

## Gaps vs Tinker/Tinkex Requirements

1. Manifest expressiveness
- No explicit `features` or `flows` sections.
- No per‑client module naming or surface mapping (e.g., ServiceClient vs SamplingClient).
- Limited env/config defaults (no env‑driven header sources baked in).

2. Composite flows
- No manifest support for multi‑step flows (e.g., create training client from state).
- No way to model post‑endpoint logic like building client structs or sequencing calls.

3. Futures
- Current future polling expects generic “type” status fields, not the Tinker `retrieve_future` semantics end‑to‑end (RequestFailedError category mapping, try_again, queue_state_reason handling, telemetry headers).
- No manifest‑level mapping for future resolution types or error category extraction.

4. Sampling backpressure and dispatch throttling
- Tinker requires sampling backpressure handling (429 -> retry with backoff), byte‑budget semaphores, and dispatch throttling.
- Pristine has bytes semaphore but it’s not integrated with pipeline or manifest.

5. Session lifecycle + heartbeat
- Tinker requires automatic session creation + heartbeat task.
- Pristine has no built‑in session manager feature.

6. Telemetry reporting
- Tinker telemetry requires batching and sending to `/api/v1/telemetry` with event schemas.
- Pristine telemetry ports are for local :telemetry emission; no backend batch uploader feature.

7. Error taxonomy
- Tinker error types (APIStatusError, RequestFailedError, category mapping) are not encoded in manifest or pipeline.

8. Client surface parity
- No direct support for generating Tinkex.ServiceClient / TrainingClient / SamplingClient / RestClient shapes with custom method names.
- Types namespace and aliasing (`Tinkex.Types.*`) is not guaranteed.

## Full Implementation Plan

### Phase 0: Confirm Baseline and Lock Requirements
- Capture a “feature parity matrix” mapping each example to required features and endpoints.
- Normalize the Tinker endpoint inventory and data types in a single spec.
- Define the minimal manifest schema extensions needed (features + flows).

Deliverables:
- Feature parity matrix in `docs/20260106/manifest-reimagining/pristine-implementation/`.
- Final manifest schema draft and acceptance criteria.

### Phase 1: Manifest Schema Expansion

Goal: Extend manifest to encode features, flows, and client surface mapping.

Tasks:
- Add `features` section for reusable feature blocks (retry policies, futures, sampling backpressure, telemetry, session, pooling).
- Add `flows` section for composite operations (multi‑step endpoint sequences).
- Add `clients` section to map generated modules to public surface names (e.g., `Tinkex.ServiceClient`).
- Extend `Pristine.Manifest.Schema` to validate new sections.
- Extend `Pristine.Manifest.Endpoint` to include new fields: `pool`, `features`, `future`, `streaming_format`, `response_mode`, `error_mapping`, `telemetry_profile`.
- Update `Pristine.Manifest.load/1` normalization to build structured flow/feature metadata.

Acceptance:
- Manifest validation enforces new fields.
- Manifest can express a Tinker endpoint with attached features and flow.

### Phase 2: Feature Pipeline and Runtime Enhancements

Goal: Make features composable and endpoint‑driven rather than hard‑coded.

Tasks:
- Refactor `Pristine.Core.Pipeline` into feature stages:
  - request preparation
  - dispatch (pool selection, rate limits, retry)
  - response handling (unwrap, error mapping)
  - feature hooks (future resolution, telemetry)
- Introduce a feature registry (e.g., `Pristine.Core.Features`) that maps feature IDs to handlers.
- Add feature hooks for:
  - sampling backpressure (429 handling + backoff + header injection)
  - queue state extraction (408 + callback)
  - future resolution (retrieve_future endpoint + type mapping)
  - telemetry batch sending (see Phase 4)
- Add feature‑level config merging (endpoint → manifest defaults → runtime overrides).

Acceptance:
- Features can be attached to endpoints declaratively.
- Pipeline behavior is driven by endpoint features, not manual code branching.

### Phase 3: Futures 2.0 (Tinker Semantics)

Goal: Align future handling with Tinker semantics and errors.

Tasks:
- Add a Tinker‑specific future adapter, e.g. `Pristine.Adapters.Future.TinkerPolling`:
  - Uses `retrieve_future` endpoint from manifest.
  - Supports `type: try_again` responses.
  - Parses `error`, `category`, and maps to RequestFailedError.
  - Emits queue_state and queue_state_reason to observers on 408.
  - Handles retryable status codes (408, 429, 5xx, 410 future expired).
- Add manifest mapping to resolve futures into typed results (e.g., CreateModelResponse).
- Extend `execute_future` to accept a target type and error mapping metadata.

Acceptance:
- A future‑returning endpoint resolves to the correct typed response.
- Queue state callbacks behave identically to Python SDK.

### Phase 4: Session Lifecycle + Heartbeat Feature

Goal: Make session creation + heartbeat an explicit manifest feature.

Tasks:
- Introduce `Pristine.Ports.SessionManager` and default adapter (GenServer).
- SessionManager responsibilities:
  - create session on client initialization
  - store session_id in context
  - spawn heartbeat process at configured interval
  - stop heartbeat on shutdown
- Manifest feature definition for session lifecycle:
  - create_session endpoint
  - heartbeat endpoint
  - tags + metadata sources (env + opts)

Acceptance:
- ServiceClient init automatically creates session and starts heartbeat.
- Session id is injected into downstream endpoints.

### Phase 5: Sampling Dispatch + Backpressure Feature

Goal: Implement sampling throttling and backpressure as generalized features.

Tasks:
- Add `Pristine.Ports.DispatchLimiter` or reuse semaphore + bytes_semaphore ports.
- Implement a `SamplingDispatch` feature that:
  - estimates payload bytes (hook for domain‑specific estimator)
  - enforces count‑based semaphore + byte‑budget semaphore
  - tracks backoff windows after 429 responses
- Add manifest hooks for:
  - `backpressure_header`
  - backoff durations
  - sampling payload byte estimator

Acceptance:
- Sampling endpoints throttle and backoff exactly as Python SDK.
- Queue state logs and backpressure reasons surface to callers.

### Phase 6: Telemetry Feature (Tinker Backend)

Goal: Implement telemetry batch reporting to `/api/v1/telemetry`.

Tasks:
- Add `Pristine.Ports.TelemetryReporter` for event batching and flush.
- Implement adapter mirroring Python `Telemetry`:
  - queue events, batch size, flush interval
  - session start/end events
  - fatal error flushing
  - env toggle `TINKER_TELEMETRY`
- Add manifest feature to enable telemetry with event schemas.

Acceptance:
- Telemetry events are posted to backend; flush + shutdown works.
- Reporter is deterministic and testable (no sleeps in tests).

### Phase 7: Codegen and Surface Mapping

Goal: Generate modules matching legacy Tinkex surface without manual wrappers.

Tasks:
- Extend codegen to read `clients` + `flows` sections.
- Generate client modules for ServiceClient, TrainingClient, SamplingClient, RestClient with specified method names.
- Generate flow methods for composite operations.
- Ensure types namespace generation maps to `Tinkex.Types.*`.
- Support public re‑exports or alias modules generated from manifest metadata.

Acceptance:
- Generated modules match `examples/*.exs` usage without renames.

### Phase 8: Tests and Parity Validation

Goal: TDD coverage for each feature and parity against examples.

Tasks:
- Add unit tests for manifest parsing (new sections).
- Add tests for future polling semantics and error mapping.
- Add tests for sampling backpressure and throttling (Supertester; no sleeps).
- Add tests for telemetry reporter and session manager.
- Add example‑driven acceptance tests in Tinkex that exercise generated surface.

Acceptance:
- `mix test`, `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors` pass in Pristine and Tinkex.

## Sequencing and Dependencies

- Phase 1 must precede codegen and runtime changes (schema drives everything).
- Phase 3 depends on Phase 2 (feature pipeline) and endpoint metadata.
- Phase 4/5/6 can proceed in parallel once feature plumbing exists.
- Phase 7 depends on manifest schema + flows.

## Open Questions

- Should flows support limited inline logic (e.g., “build client with fields from response”), or be expressed with a declarative DSL + hooks?
- How will Tinkex domain modules (tokenizer, byte estimator) inject into generic features (sampling dispatch)?
- Do we want to embed manifest in generated modules or load from file at runtime?

## Deliverables Checklist

- [ ] Manifest schema with features + flows + clients
- [ ] Feature pipeline in Pristine core
- [ ] Tinker‑specific future resolver
- [ ] Session lifecycle manager + heartbeat
- [ ] Sampling backpressure + dispatch limiter
- [ ] Telemetry batch reporter
- [ ] Codegen surface mapping + flow generation
- [ ] TDD coverage for each feature

