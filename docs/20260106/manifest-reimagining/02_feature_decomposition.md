# Manifest Reimagining: Feature Decomposition

This document decomposes SDK behaviors into reusable features that must be expressible in the manifest. The intent is to generalize infrastructure in Pristine and leave only domain-specific logic in Tinkex.

## 1. Core Cross-Cutting Features (Generalizable)

### 1.1 Auth + Header Injection
- API key header: `X-API-Key` from config/env.
- Cloudflare Access headers: `CF-Access-Client-Id`, `CF-Access-Client-Secret`.
- SDK metadata headers: async library, retry count, read timeout.
- Idempotency header (`X-Idempotency-Key`) for write endpoints.

Manifest needs:
- auth: api_key header name
- optional headers: env-sourced + config overrides
- per-endpoint idempotency flag
- header redaction for secret dumps

### 1.2 Request Building and Serialization
- Querystring format: comma arrays (Python `Querystring(array_format="comma")`).
- JSON body vs multipart form handling.
- `NotGiven` / `Omit` for optional fields.
- Extra headers/query/body override precedence.

Manifest needs:
- serializer type (JSON/multipart)
- querystring format
- request option merge semantics

### 1.3 Retry/Backoff Strategies
Two distinct retry systems exist:
- Global request retries in `InternalClientHolder.execute_with_retries`.
- Sampling-specific `RetryHandler` with connection limiting and progress timeout.

Retry semantics:
- Retry on 408, 409, 429, and 5xx.
- Exponential backoff capped at 30s.
- Progress timeout semantics (no progress marker) for long-running batches.

Manifest needs:
- retry policy blocks with classed error sets
- per-endpoint overrides (max_retries)
- specialized retry policies for sampling vs general

### 1.4 Futures and Asynchronous Results
Server returns `UntypedAPIFuture` for many endpoints. Client must:
- Call `/api/v1/retrieve_future` to resolve.
- Handle `try_again` responses.
- Handle `RequestFailedError` with categories.
- Attach telemetry metadata and queue state events.

Manifest needs:
- future-returning endpoints with resolved type
- promise retrieval endpoint (method/path/type)
- error and queue-state parsing hints

### 1.5 Queue State and Backpressure
Queue state is reported via 408 response JSON:
- queue_state: active | paused_rate_limit | paused_capacity
- queue_state_reason: server-supplied reason

Sampling-specific backpressure:
- `/api/v1/asample` returns 429 to trigger client backoff.
- Client sends `X-Tinker-Sampling-Backpressure: 1` header.

Manifest needs:
- queue state extraction rule
- per-endpoint backpressure header and backoff rules

### 1.6 Connection Pools and Concurrency
Python SDK uses pool types:
- SESSION, TRAIN, SAMPLE, RETRIEVE_PROMISE, TELEMETRY

Behaviors:
- Train pool limited to 1 request/client
- Sample pool uses dispatch semaphores (count + bytes)
- Each pool uses separate AsyncTinker instances

Manifest needs:
- endpoint-level pool assignment
- per-pool concurrency limits
- sample dispatch rate limiter settings

### 1.7 Session Lifecycle + Heartbeat
- `create_session` on startup (tags + user metadata + SDK version)
- background heartbeat every 10s
- warning on missed heartbeat

Manifest needs:
- session init flow with tagging
- heartbeat schedule
- session id propagation to dependent calls

### 1.8 Telemetry
Telemetry system:
- batched events sent to `/api/v1/telemetry`
- session start/end events
- exception events (fatal vs non-fatal)
- flush interval, batch size, queue size

Manifest needs:
- telemetry feature with batching config
- event schemas for telemetry types
- toggles via env (TINKER_TELEMETRY)

### 1.9 Streaming and Raw Responses
- Raw response wrappers (`with_raw_response`)
- Streamed response wrappers (`with_streaming_response`)
- SSE decoding in `_streaming.py`

Manifest needs:
- endpoint response mode metadata (raw/stream)
- streaming codecs (SSE)

### 1.10 Multipart Encoding
- Multipart form serialization (`multipart/form-data` boundary handling)
- File inputs in request options

Manifest needs:
- multipart serializer feature
- file input type rules

### 1.11 Logging and Diagnostics
- Log level via `TINKER_LOG`
- HTTPX logging tuned to avoid backpressure noise

Manifest needs:
- logging config hooks or client-level toggles

### 1.12 Error Taxonomy
- APIStatusError, APIConnectionError, APIResponseValidationError
- RequestFailedError for future failures

Manifest needs:
- error mapping and categories
- typed error shaping for caller

## 2. Domain-Specific Features (Tinkex-Owned)

These are specific to Tinkex usage and should remain in Tinkex (or explicit manifest flow hooks) rather than being generalized in Pristine:

- Tokenizer integration (tiktoken, model overrides)
- ModelInput helpers and byte estimation logic
- Training custom loss helpers (client-side logprobs -> gradients)
- Regularizer pipeline and gradient tracking
- Recovery subsystem (Monitor/Executor/Policy)
- Metrics aggregation (p50/p95/p99, counters)

## 3. Feature Matrix (Endpoint-Level)

Examples of how features apply per endpoint:

- create_session
  - auth headers, idempotency, base retry, telemetry
  - session flow start

- asample
  - auth, sampling retry policy, backpressure header, queue state observer
  - sample dispatch rate limit (count + bytes)

- forward/forward_backward/optim_step
  - auth, future resolution, queue state observer, training chunking

- retrieve_future
  - raw response support, queue state parsing

- telemetry
  - telemetry batching + retry

- checkpoints archive
  - special accept header, follow_redirects false, response header parsing

## 4. Generalization Targets for Pristine

These behaviors should be implemented in Pristine features (not handwritten in Tinkex):
- Retry policies (standard + sampling-specific)
- Future handling and queue state parsing
- Connection pool and concurrency policies
- Telemetry batching and ingestion
- Multipart and file handling
- Streaming response parsing
- Session lifecycle and heartbeat

The manifest must provide hooks/configuration for each so Tinkex can be generated without hidden behavior.

