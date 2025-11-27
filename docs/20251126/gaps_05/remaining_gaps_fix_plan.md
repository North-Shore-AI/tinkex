# Remaining Python↔Elixir Parity Gaps (as of 2025-11-27)

Context: `gap-analysis-python-to-elixir.md` currently claims full parity. The items below are the **actual gaps still open**, with concrete fixes to reach 100% parity with the Python SDK (`tinker/src/tinker`).

## 1) HTTP retry behavior deviates
- **What’s different:** `lib/tinkex/api/api.ex` retries on 408/429/5xx only, with jitter `0..1x`, `@max_retry_delay` = 8s, and a global cutoff at 30s. Python (`tinker/_base_client.py:_should_retry`) retries 408/409/429/5xx, uses a 0.75–1.0 jitter, caps delay at 10s, and has no 30s wall-clock cutoff (it runs for all `max_retries`).
- **Impact:** Locked/409 responses and long tails (>30s) will fail in Elixir while Python keeps retrying; backoff timing is also different.
- **Fix:** Update `status_based_decision/4` to include 409, align jitter/delay to Python’s formula and 10s cap, and drop/raise the 30s wall clock (let `max_retries` govern). Add a regression test that mirrors `_should_retry` cases and jitter window.

## 2) HTTP pool sizing below Python defaults
- **What’s different:** Finch starts with the default pool (`Tinkex.Application`) of 50 conns/1 pool; Python uses `httpx.Limits(max_connections=1000, max_keepalive_connections=20)` (`_constants.py`).
- **Impact:** High-concurrency sampling/training can saturate the Elixir pool long before Python would.
- **Fix:** Allow configuring Finch pool size/count (env + app config), and bump the default toward the Python limit (e.g., size: 1000; count or idle settings to approximate `max_keepalive_connections=20`). Document the knobs alongside parity mode.

## 3) Raw/streaming response surface missing
- **What’s different:** Python exposes `with_raw_response` and `with_streaming_response` on every resource, yielding `APIResponse`/`Stream` with headers/status and SSE chunking. Elixir has `Tinkex.API.Response` and `StreamResponse`, but Service/Training/Sampling/Rest clients never expose a way to request them, and `API.stream_get/3` buffers the full body (not a live stream).
- **Impact:** Callers cannot replicate Python’s raw-header access or streaming consumption for long-running/SSE endpoints.
- **Fix:** Plumb a `response: :wrapped | :stream` option through client functions to `Tinkex.API.*`, surface helpers (`with_raw_response/1`, `with_streaming_response/1`), and make `stream_get/3` truly streaming via `Finch.stream/5` + `SSEDecoder`. Add parity tests for raw/streamed futures and archive download endpoints.

## 4) Type coverage gaps
- **Missing vs Python types:** `FutureRetrieveRequest/FutureRetrieveResponse`, `SessionHeartbeatRequest/Response`, `TelemetryResponse`, `RequestFailedResponse`, `ModelInputChunk` alias, `LossFnInputs/LossFnOutput` aliases, `UntypedAPIFuture`.
- **Impact:** Type-level parity is incomplete; guides/tests cannot rely on these structs, and heartbeat/future payloads stay as loose maps.
- **Fix:** Add the missing structs/aliases under `lib/tinkex/types/` (and `types/telemetry`), wire them into `Future.poll/2`, `SessionManager` heartbeat payloads, and telemetry sender, plus round-trip tests mirroring the Python JSON.

## 5) Tensor dtype expectations
- **What’s the int64/float32 thing:** Both SDKs only allow `"int64"`/`"float32"` on the wire. Elixir’s `TensorDtype.from_nx_type/1` downcasts `{:f, 64}` to float32 and upcasts `{:s, 32}`/unsigned to int64.
- **Impact:** Silent downcasts can surprise callers who pass `Nx` tensors with wider types and expect bit-for-bit parity.
- **Fix:** Document this clearly in the public guides/API reference, and optionally emit warnings when downcasting; add a small test asserting the cast behavior so parity intent is explicit.

---

These are the only remaining gaps found after reviewing current code (`0.1.10`). Closing them will align Elixir behavior with the Python SDK across retries, pooling, raw/streaming access, and type coverage.
