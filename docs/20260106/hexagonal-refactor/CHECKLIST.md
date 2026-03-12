# Hexagonal Refactor Checklist

Note: this is the original tinkex; ignore `~/p/g/North-Shore-AI/pristine/examples/`. Ports/adapters are created in Phase 3.

## Phase 1: Integrate Foundation/Sinter

### Dependencies
- [x] Add `foundation` to mix.exs
- [x] Add `sinter` to mix.exs
- [x] Add `multipart_ex` to mix.exs
- [x] Run `mix deps.get`

### Retry/Backoff Replacement
- [x] Create `Foundation.Retry` wrapper if needed
- [x] Replace `Tinkex.RetryConfig` usages
- [x] Replace `Tinkex.RetryHandler` usages
- [x] Replace `lib/tinkex/retry.ex` usages
- [x] Delete `lib/tinkex/retry_config.ex`
- [x] Delete `lib/tinkex/retry_handler.ex`
- [x] Delete `lib/tinkex/retry.ex`
- [x] Tests pass

### Circuit Breaker Replacement
- [x] Replace `Tinkex.CircuitBreaker` with `Foundation.CircuitBreaker`
- [x] Replace `Tinkex.CircuitBreaker.Registry` with `Foundation.CircuitBreaker.Registry`
- [x] Delete `lib/tinkex/circuit_breaker.ex`
- [x] Delete `lib/tinkex/circuit_breaker/registry.ex`
- [x] Tests pass

### Rate Limiting Replacement
- [x] Replace `Tinkex.RateLimiter` with `Foundation.RateLimit.BackoffWindow`
- [x] Delete `lib/tinkex/rate_limiter.ex`
- [x] Tests pass

### Semaphore Replacement
- [x] Replace `Tinkex.RetrySemaphore` with `Foundation.Semaphore.Counting`
- [x] Replace `Tinkex.BytesSemaphore` with `Foundation.Semaphore.Weighted`
- [x] Delete `lib/tinkex/retry_semaphore.ex`
- [x] Delete `lib/tinkex/bytes_semaphore.ex`
- [x] Tests pass

### Transform/NotGiven Replacement
- [x] Replace `Tinkex.NotGiven` with `Sinter.NotGiven`
- [x] Replace `Tinkex.Transform` with `Sinter.Transform`
- [x] Delete `lib/tinkex/not_given.ex`
- [x] Delete `lib/tinkex/transform.ex`
- [x] Tests pass

### Multipart Replacement
- [x] Replace `Tinkex.Multipart.Encoder` with `Multipart.Encoder`
- [x] Replace `Tinkex.Multipart.FormSerializer` with `Multipart.Form`
- [x] Delete `lib/tinkex/multipart/`
- [x] Tests pass

---

## Phase 2: Stabilize

- [x] `mix test` - all pass
- [x] `mix test --seed 12345` - pass
- [x] `mix test --seed 99999` - pass
- [x] `mix test --seed 1` - pass
- [x] `mix dialyzer` - no errors
- [x] `mix credo --strict` - no issues
- [x] No deprecation warnings
- [ ] Commit checkpoint

---

## Phase 3: Hexagonal Refactor

### Define Ports
- [x] Create `lib/tinkex/ports/http_transport.ex`
- [x] Create `lib/tinkex/ports/retry_strategy.ex`
- [x] Create `lib/tinkex/ports/circuit_breaker.ex`
- [x] Create `lib/tinkex/ports/rate_limiter.ex`
- [x] Create `lib/tinkex/ports/serializer.ex`
- [x] Create `lib/tinkex/ports/streaming.ex`
- [x] Create `lib/tinkex/ports/telemetry.ex`
- [x] Create `lib/tinkex/ports/pool_manager.ex`
- [x] Create `lib/tinkex/ports/semaphore.ex`

### Create Adapters
- [x] Create `lib/tinkex/adapters/finch_transport.ex`
- [x] Create `lib/tinkex/adapters/foundation_retry.ex`
- [x] Create `lib/tinkex/adapters/foundation_cb.ex`
- [x] Create `lib/tinkex/adapters/foundation_rate.ex`
- [x] Create `lib/tinkex/adapters/jason_serializer.ex`
- [x] Create `lib/tinkex/adapters/sse_streaming.ex`
- [x] Create `lib/tinkex/adapters/foundation_semaphore.ex`

### Create Context
- [x] Create `lib/tinkex/context.ex`
- [x] Wire up adapters via Context

### Reorganize Domain
- [x] Move `SamplingClient` to `lib/tinkex/domain/sampling/client.ex`
- [x] Move `TrainingClient` to `lib/tinkex/domain/training/client.ex`
- [x] Move `Future` to `lib/tinkex/domain/futures/poller.ex`
- [x] Move `RestClient` to `lib/tinkex/domain/rest/client.ex`
- [x] Keep types in `lib/tinkex/types/`

### Refactor Clients to Use Ports
- [x] SamplingClient uses ports via Context
- [x] TrainingClient uses ports via Context
- [x] Future uses ports via Context
- [x] RestClient uses ports via Context

### Delete Old API Layer
- [x] Delete `lib/tinkex/api/api.ex`
- [x] Delete `lib/tinkex/api/request.ex`
- [x] Delete `lib/tinkex/api/response.ex`
- [x] Delete `lib/tinkex/api/response_handler.ex`
- [x] Delete `lib/tinkex/api/compression.ex`
- [x] Delete `lib/tinkex/api/headers.ex`
- [x] Delete `lib/tinkex/api/url.ex`
- [x] Delete `lib/tinkex/api/helpers.ex`
- [x] Delete `lib/tinkex/api/telemetry.ex`
- [x] Delete `lib/tinkex/api/retry.ex`
- [x] Delete `lib/tinkex/api/retry_config.ex`
- [x] Delete `lib/tinkex/api/stream_response.ex`

---

## Phase 4: Stabilize

- [x] `mix test` - all pass
- [x] `mix test --seed 12345` - pass
- [x] `mix test --seed 99999` - pass
- [x] `mix test --seed 1` - pass
- [x] `mix dialyzer` - no errors
- [x] `mix credo --strict` - no issues
- [x] Domain modules have zero infrastructure imports
- [ ] Commit checkpoint

---

## Phase 5: Extract to Pristine

### Move Ports
- [x] Move `lib/tinkex/ports/*.ex` (created in Phase 3) to `pristine/lib/pristine/ports/`
- [x] Update imports/aliases

### Move Adapters
- [x] Move `lib/tinkex/adapters/*.ex` (created in Phase 3) to `pristine/lib/pristine/adapters/`
- [x] Update imports/aliases

### Move Context/Pipeline
- [x] Move Context (created in Phase 3) to `pristine/lib/pristine/core/context.ex`
- [x] Move Pipeline logic (if created) to `pristine/lib/pristine/core/pipeline.ex`

### Update Tinkex to Use Pristine
- [x] Add pristine as dependency
- [x] Import ports from pristine
- [x] Import adapters from pristine
- [x] Use Pristine.Core.Context

### Create Manifest Schema
- [x] Define adapter configuration in manifest
- [x] Define retry policy in manifest
- [x] Define circuit breaker config in manifest
- [x] Define pool configuration in manifest
- [x] Define all 40+ endpoints in manifest
- [x] Define all types in manifest

---

## Phase 6: Thin Tinkex

### Create Full Manifest
- [x] Create `lib/tinkex/manifest.yaml` (or .json)
- [x] Include all endpoints
- [x] Include all types
- [x] Include all configuration

### Generate Client
- [x] Run `mix pristine.generate --manifest manifest.yaml`
- [x] Verify generated client works

### Delete Infrastructure
- [x] Delete `lib/tinkex/ports/` (created in Phase 3; moved to pristine)
- [x] Delete `lib/tinkex/adapters/` (created in Phase 3; moved to pristine)
- [x] Delete `lib/tinkex/context.ex` (created in Phase 3; moved to pristine)

### Keep Domain-Specific
- [x] Keep `lib/tinkex/domain/tokenizer.ex`
- [x] Keep `lib/tinkex/domain/byte_estimator.ex`
- [x] Keep `lib/tinkex/domain/model_input.ex`

### Final Verification
- [x] `mix test` - all tests pass
- [x] Hand-written code < 500 lines
- [x] Generated code handles all infrastructure
- [ ] Commit final state

---

## Success Metrics

- [x] Pristine: tests pass
- [x] Tinkex: tests pass
- [x] Tinkex hand-written lines: < 500
- [x] All tests seed-independent
- [x] Zero warnings
