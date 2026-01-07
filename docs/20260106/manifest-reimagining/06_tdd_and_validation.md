# Manifest Reimagining: TDD and Validation Plan

This document describes a test-first plan to ensure parity and correctness for the manifest-driven redesign.

## 1. Testing Principles
- Write tests before feature implementation (TDD).
- Focus on behavior parity and public surface stability.
- Use deterministic telemetry and concurrency tests (no sleeps).
- Reintroduce removed tests where behavior is still required.

## 2. Test Layers

### 2.1 Manifest Parser Tests (Pristine)
- Schema validation (required fields, feature references).
- Endpoint expansion (paths with params).
- Flow validation (missing inputs, cycles).

### 2.2 Feature Tests (Pristine)
- Retry policies: error classification, backoff timings (bounded), max retries.
- Future resolver: try_again handling, 408 queue state, RequestFailedError.
- Telemetry: batching, flush, enable/disable via env.
- Sampling backpressure: 429 handling and backoff rules.
- Multipart: form encoding and file transform.
- Streaming: SSE decode and raw response wrappers.

### 2.3 Codegen Tests (Pristine)
- Generated module names and methods match manifest metadata.
- Types namespace generated as specified.
- Flow methods compiled and callable.

### 2.4 SDK Surface Tests (Tinkex)
- ServiceClient, TrainingClient, SamplingClient, RestClient functions exist.
- Returned types and error shapes match expected structs.
- Environment default handling (Tinkex.Env parity).

### 2.5 Example-Based Acceptance Tests
Treat each `examples/*.exs` as an acceptance test. Use a stub server or recorded fixtures where possible.
- Sampling: sample + decode flow
- Training: forward/forward_backward/optim_step
- Checkpoints: list, publish/unpublish, archive URL handling
- Telemetry: reporter flush and event capture
- CLI: run list/checkpoint list JSON output

## 3. Supertester Guidelines (Elixir)
- Use `Supertester.ExUnitFoundation` with isolation helpers.
- Avoid `Process.sleep/1`.
- Use telemetry capture helpers and deterministic hooks.

## 4. Parity Benchmarks

Define parity benchmarks between Python and Elixir:
- Same request payload for core endpoints.
- Same response parsing semantics for futures and errors.
- Same environment knob behavior for auth/telemetry/logging.

## 5. Verification Suite

After each feature or module:
- `mix test` + seeds
- `mix dialyzer`
- `mix credo --strict`
- `mix compile --warnings-as-errors`

Add targeted tests for every manifest feature and endpoint.

