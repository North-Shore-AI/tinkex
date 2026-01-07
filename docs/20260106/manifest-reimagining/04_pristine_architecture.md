# Manifest Reimagining: Pristine Architecture Plan

This document proposes how Pristine should implement the generalized infrastructure required by the manifest. The goal is to keep all reusable behavior in Pristine and keep Tinkex thin.

## 1. Architectural Layers

1. Manifest parser
   - Reads the declarative manifest and produces an internal model (types, endpoints, features, flows).

2. Core pipeline
   - Feature pipeline that attaches behaviors (retry, telemetry, futures, streaming, rate limiting) to endpoint calls.

3. Ports/Adapters
   - Ports define behavior interfaces. Adapters implement them (Finch, Jason, Foundation, etc.).

4. Codegen
   - Generates clients and resources from manifest definitions.

## 2. Required Ports (Pristine)

Existing ports are not sufficient to model all required behaviors. Proposed additional ports:

- HTTPTransport (existing)
  - request/stream calls with headers/body/opts

- RetryStrategy (existing or extended)
  - policy construction, backoff logic, retry classifier

- CircuitBreaker, RateLimiter (existing)

- TelemetryPort (new)
  - enqueue, flush, start/stop, event schemas

- FutureResolverPort (new)
  - resolve promise results, retry loop, error mapping
  - handles queue state callbacks

- SessionManagerPort (new)
  - create session, heartbeat scheduling, session id propagation

- StreamingPort (new)
  - SSE decoding and streamed response wrappers

- MultipartPort (new)
  - multipart form encoding and file handling

- ConnectionPoolPort (new)
  - pool selection and per-pool concurrency limits

These ports allow manifest feature blocks to map cleanly to Pristine implementations.

## 3. Feature Pipeline Model

Feature pipeline executes in ordered phases:
1. Request preparation (auth headers, idempotency, querystring, serialization).
2. Dispatch phase (pool selection, rate limiter, retry wrapper).
3. Response handling (future resolution, streaming decode, error mapping).
4. Telemetry hooks (pre/post, error capture).

Each feature is a pipeline plugin with deterministic ordering.

## 4. Futures and Queue State

Pristine must support the promise/future pattern as a feature:
- Endpoints flagged as `future` return an internal handle with `request_id`.
- The resolver feature calls the manifest-defined retrieve endpoint.
- It handles:
  - try_again responses
  - 408 queue_state parsing + observer callback
  - categorized request_failed errors

This should be a reusable feature independent of Tinkex domain.

## 5. Session Lifecycle

Pristine should own session creation and heartbeat scheduling:
- On client creation, call create_session flow if manifest declares it.
- Start a heartbeat process with configurable interval and timeout.
- Expose session_id for downstream calls.

Session lifecycle must be represented as a feature/flow in the manifest.

## 6. Sampling Dispatch and Backpressure

Pristine should implement sample dispatch throttling and backpressure:
- Count-based semaphore
- Byte-based semaphore with backoff amplification
- Backpressure response handling (429 -> backoff, return None, retry)

These are general behaviors for streaming/interactive inference and should be reusable.

## 7. Telemetry

Pristine should provide:
- Telemetry queue and batching
- Flush scheduling and manual flush
- Event schemas defined in manifest types
- Toggle via env or config

Tinkex should only wire this feature and not implement it directly.

## 8. Streaming and Raw Responses

Pristine should provide:
- SSE decoder utilities
- Raw response wrappers and streaming to file
- Ability to attach stream handling to endpoints in manifest

## 9. Codegen Responsibilities

Codegen should:
- Generate client modules with existing method names.
- Generate resource modules for endpoint groups.
- Bind flow definitions into client methods.
- Attach feature pipeline configuration at compile time.

No handwritten compatibility layer should be needed.

