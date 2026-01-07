# Tinkex Hexagonal Refactor Plan

## Vision

**Pristine is the generalization of Tinkex.**

The current approach (examples/tinkex duplicating original tinkex) is wrong. Ignore `~/p/g/North-Shore-AI/pristine/examples/` entirely; it is not a reference source for this refactor. Instead:
- **Pristine** = thick, contains all infrastructure (retry, circuit breaker, rate limiting, HTTP transport, streaming, etc.)
- **Tinkex** = thin, configuration + manifests that render to a full API via Pristine

The end state: tinkex becomes ~200-500 lines of domain types + manifest configuration, while Pristine provides all the machinery.

## Phased Approach

```
Phase 1: Integrate Foundation/Sinter into original tinkex
    ↓
Phase 2: Stabilize (all tests pass)
    ↓
Phase 3: Refactor to Hexagonal (ports & adapters)
    ↓
Phase 4: Stabilize (all tests pass)
    ↓
Phase 5: Extract generalized infrastructure into Pristine
    ↓
Phase 6: Tinkex becomes thin manifest-driven SDK
```

---

## Phase 1: Integrate Foundation/Sinter

**Goal:** Replace tinkex infrastructure modules with battle-tested libraries.

### 1.1 Replace Retry/Backoff

| Tinkex Module | Replacement | Lines Removed |
|---------------|-------------|---------------|
| `RetryConfig` | `Foundation.Retry.Policy` | ~143 |
| `RetryHandler` | `Foundation.Retry` | ~170 |
| `retry.ex` | `Foundation.Retry.run/3` | ~200 |

**Changes:**
```elixir
# Before (tinkex)
Tinkex.RetryConfig.new(max_retries: 3, base_delay_ms: 500)
Tinkex.RetryHandler.execute(fn -> ... end, config)

# After (foundation)
Foundation.Retry.Policy.new(max_attempts: 4, backoff: :exponential)
Foundation.Retry.run(fn -> ... end, policy)
```

### 1.2 Replace Circuit Breaker

| Tinkex Module | Replacement | Lines Removed |
|---------------|-------------|---------------|
| `CircuitBreaker` | `Foundation.CircuitBreaker` | ~235 |
| `CircuitBreaker.Registry` | `Foundation.CircuitBreaker.Registry` | ~100 |

**Changes:** Direct drop-in replacement (identical API).

### 1.3 Replace Rate Limiting

| Tinkex Module | Replacement | Lines Removed |
|---------------|-------------|---------------|
| `RateLimiter` | `Foundation.RateLimit.BackoffWindow` | ~84 |
| `RetrySemaphore` | `Foundation.Semaphore.Counting` | ~190 |
| `BytesSemaphore` | `Foundation.Semaphore.Weighted` | ~101 |

### 1.4 Replace Transform/NotGiven

| Tinkex Module | Replacement | Lines Removed |
|---------------|-------------|---------------|
| `NotGiven` | `Sinter.NotGiven` | ~47 |
| `Transform` | `Sinter.Transform` | ~109 |

### 1.5 Replace Multipart

| Tinkex Module | Replacement | Lines Removed |
|---------------|-------------|---------------|
| `Multipart.Encoder` | `Multipart.Encoder` | ~120 |
| `Multipart.FormSerializer` | `Multipart.Form` | ~80 |

### 1.6 Checklist

- [ ] Add foundation, sinter, multipart_ex to mix.exs
- [ ] Replace RetryConfig/RetryHandler with Foundation.Retry
- [ ] Replace CircuitBreaker with Foundation.CircuitBreaker
- [ ] Replace RateLimiter with Foundation.RateLimit.BackoffWindow
- [ ] Replace RetrySemaphore with Foundation.Semaphore.Counting
- [ ] Replace BytesSemaphore with Foundation.Semaphore.Weighted
- [ ] Replace NotGiven with Sinter.NotGiven
- [ ] Replace Transform with Sinter.Transform
- [ ] Replace Multipart modules with multipart_ex
- [ ] Delete replaced modules
- [ ] Update all callers

**Estimated lines removed:** ~1,200+

---

## Phase 2: Stabilize

**Goal:** All existing tests pass with Foundation/Sinter replacements.

### 2.1 Checklist

- [ ] `mix test` passes (all tests)
- [ ] `mix test --seed N` passes for multiple seeds
- [ ] `mix dialyzer` passes
- [ ] `mix credo --strict` passes
- [ ] No deprecation warnings

---

## Phase 3: Refactor to Hexagonal

**Goal:** Clear separation of domain logic from infrastructure via ports and adapters.
Note: the original tinkex does not have ports/adapters; they are created in this phase.

### 3.1 Define Ports (Interfaces)

Create behavior modules that define contracts:

```
lib/tinkex/ports/
├── http_transport.ex      # HTTP request/response
├── retry_strategy.ex      # Retry logic
├── circuit_breaker.ex     # Circuit breaker
├── rate_limiter.ex        # Rate limiting
├── serializer.ex          # JSON encoding
├── streaming.ex           # SSE streaming
├── telemetry.ex           # Observability
└── pool_manager.ex        # Connection pooling
```

**Example Port:**
```elixir
defmodule Tinkex.Ports.HTTPTransport do
  @callback request(method, url, headers, body, opts) :: {:ok, response} | {:error, term}
  @callback stream(method, url, headers, body, opts) :: {:ok, stream} | {:error, term}
end
```

### 3.2 Create Adapters (Implementations)

```
lib/tinkex/adapters/
├── finch_transport.ex     # Finch HTTP adapter
├── foundation_retry.ex    # Foundation retry adapter
├── foundation_cb.ex       # Foundation circuit breaker adapter
├── foundation_rate.ex     # Foundation rate limiter adapter
├── jason_serializer.ex    # Jason JSON adapter
└── sse_streaming.ex       # SSE streaming adapter
```

### 3.3 Reorganize Domain Logic

```
lib/tinkex/domain/
├── sampling/
│   ├── client.ex          # SamplingClient (domain logic only)
│   ├── request.ex         # Request building
│   └── response.ex        # Response parsing
├── training/
│   ├── client.ex          # TrainingClient
│   ├── custom_loss.ex     # Custom loss functions
│   └── regularizers/      # Regularizer implementations
├── futures/
│   ├── poller.ex          # Future polling logic
│   └── combiner.ex        # Future combination
├── models/
│   └── client.ex          # Model operations
└── types/
    └── *.ex               # Domain types (keep all)
```

### 3.4 Context/Pipeline Pattern

Introduce a pipeline context that carries all adapters:

```elixir
defmodule Tinkex.Context do
  defstruct [
    :config,
    :transport,      # Tinkex.Ports.HTTPTransport
    :retry,          # Tinkex.Ports.RetryStrategy
    :circuit_breaker,# Tinkex.Ports.CircuitBreaker
    :rate_limiter,   # Tinkex.Ports.RateLimiter
    :serializer,     # Tinkex.Ports.Serializer
    :telemetry       # Tinkex.Ports.Telemetry
  ]
end
```

### 3.5 Checklist

- [ ] Define all port behaviors
- [ ] Implement Foundation adapters for each port
- [ ] Move domain logic to `lib/tinkex/domain/`
- [ ] Create Context struct
- [ ] Refactor clients to use ports via Context
- [ ] Delete old API modules (`lib/tinkex/api/`)

---

## Phase 4: Stabilize

**Goal:** All tests pass with hexagonal architecture.

### 4.1 Checklist

- [ ] `mix test` passes
- [ ] `mix test --seed N` passes
- [ ] `mix dialyzer` passes
- [ ] `mix credo --strict` passes
- [ ] Domain modules have zero infrastructure imports

---

## Phase 5: Extract to Pristine

**Goal:** Move generalized infrastructure from tinkex to pristine.

### 5.1 Move Ports to Pristine

```
# FROM tinkex
lib/tinkex/ports/*.ex

# TO pristine
lib/pristine/ports/*.ex
```
Move the ports created in Phase 3 (skip if not present).

### 5.2 Move Adapters to Pristine

```
# FROM tinkex
lib/tinkex/adapters/*.ex

# TO pristine
lib/pristine/adapters/*.ex
```
Move the adapters created in Phase 3 (skip if not present).

### 5.3 Move Context/Pipeline

```
# FROM tinkex
lib/tinkex/context.ex
lib/tinkex/pipeline.ex

# TO pristine
lib/pristine/core/context.ex
lib/pristine/core/pipeline.ex
```
Move the context/pipeline created in Phase 3 (skip if not present).

### 5.4 Define Manifest Schema

Pristine manifests should define:

```yaml
# tinkex.manifest.yaml
name: Tinkex
version: 1.0.0
base_url: https://api.tinker.ai

# Adapter configuration
adapters:
  transport: finch
  retry: foundation
  circuit_breaker: foundation
  rate_limiter: foundation
  serializer: jason

# Retry policy
retry:
  max_attempts: 3
  backoff: exponential
  base_delay_ms: 500
  max_delay_ms: 30000

# Circuit breaker config
circuit_breaker:
  failure_threshold: 5
  recovery_time_ms: 30000

# Connection pools
pools:
  sampling:
    size: 50
    count: 20
  training:
    size: 5
    count: 2
  futures:
    size: 25
    count: 10

# Endpoints
endpoints:
  - id: sample_future
    resource: sampling
    method: POST
    path: /v1/sample_future
    request: SampleFutureRequest
    response: FutureReference

  - id: compute_logprobs_future
    resource: sampling
    method: POST
    path: /v1/compute_logprobs_future
    request: LogprobsRequest
    response: FutureReference

  # ... 40+ more endpoints

# Types (or reference external schema)
types:
  SampleFutureRequest:
    fields:
      sampling_session_id: {type: string, required: true}
      prompt: {type_ref: ModelInput, required: true}
      sampling_params: {type_ref: SamplingParams}
      seq_id: {type: integer}
      num_samples: {type: integer, default: 1}
```

### 5.5 Checklist

- [ ] Move all ports to pristine
- [ ] Move all adapters to pristine
- [ ] Move Context/Pipeline to pristine
- [ ] Create comprehensive manifest schema
- [ ] Tinkex manifest covers all 40+ endpoints
- [ ] Generate types from manifest

---

## Phase 6: Thin Tinkex

**Goal:** Tinkex becomes manifest + thin domain wrapper.

### 6.1 Final Tinkex Structure

```
lib/tinkex/
├── manifest.yaml          # Full API manifest (or .json)
├── client.ex              # Generated client (via Pristine)
├── types/                 # Generated types (via Pristine)
│   └── *.ex
└── domain/                # Tinkex-specific logic (~200 lines)
    ├── tokenizer.ex       # TikToken integration
    ├── byte_estimator.ex  # Token counting
    └── model_input.ex     # Input transformation
```

### 6.2 Generated vs Hand-Written

| Component | Source |
|-----------|--------|
| HTTP transport | Pristine (generated) |
| Retry logic | Pristine (generated) |
| Circuit breaker | Pristine (generated) |
| Rate limiting | Pristine (generated) |
| Streaming | Pristine (generated) |
| Connection pooling | Pristine (generated) |
| API endpoints | Pristine (generated from manifest) |
| Request/Response types | Pristine (generated from manifest) |
| Tokenizer | Hand-written (tinkex-specific) |
| ModelInput | Hand-written (tinkex-specific) |

### 6.3 Final Line Count Target

| Module | Lines |
|--------|-------|
| manifest.yaml | ~500 |
| domain/tokenizer.ex | ~100 |
| domain/byte_estimator.ex | ~50 |
| domain/model_input.ex | ~50 |
| **Total hand-written** | **~200** |
| Generated code | ~5000+ |

### 6.4 Checklist

- [ ] Create full tinkex manifest
- [ ] Generate client via `mix pristine.generate`
- [ ] Verify all 40+ endpoints work
- [ ] Delete hand-written infrastructure created in Phases 3-5 (ports/adapters/context; skip if not present)
- [ ] Keep only domain-specific modules
- [ ] All tests pass

---

## Success Criteria

1. **Pristine contains:**
   - All ports (HTTPTransport, Retry, CircuitBreaker, RateLimiter, etc.)
   - All adapters (Finch, Foundation, Jason, etc.)
   - Context/Pipeline orchestration
   - Manifest loading and validation
   - Code generation for clients and types
   - Streaming infrastructure
   - Telemetry infrastructure

2. **Tinkex contains:**
   - `manifest.yaml` defining full API
   - ~200 lines of domain-specific code
   - Generated client and types

3. **Tests:**
   - Pristine: ~500 infrastructure tests
   - Tinkex: ~1700 domain/integration tests
   - All pass with any seed

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1: Foundation/Sinter integration | 2-3 days |
| Phase 2: Stabilize | 1 day |
| Phase 3: Hexagonal refactor | 3-5 days |
| Phase 4: Stabilize | 1-2 days |
| Phase 5: Extract to Pristine | 3-5 days |
| Phase 6: Thin Tinkex | 2-3 days |
| **Total** | **12-19 days** |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing tinkex users | Maintain API compatibility until v2.0 |
| Foundation/Sinter gaps | Extend libraries as needed |
| Manifest can't express all tinkex features | Add custom extensions to manifest schema |
| Performance regression | Benchmark before/after each phase |
| Test coverage gaps | Add tests as we refactor |

---

## Next Steps

1. **Immediate:** Start Phase 1 in ~/p/g/North-Shore-AI/tinkex
2. **First PR:** Replace RetryConfig/RetryHandler with Foundation.Retry
3. **Iterate:** One module replacement per PR, test after each
