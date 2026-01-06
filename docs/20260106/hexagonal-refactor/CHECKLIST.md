# Hexagonal Refactor Checklist

## Phase 1: Integrate Foundation/Sinter

### Dependencies
- [ ] Add `foundation` to mix.exs
- [ ] Add `sinter` to mix.exs
- [ ] Add `multipart_ex` to mix.exs
- [ ] Run `mix deps.get`

### Retry/Backoff Replacement
- [ ] Create `Foundation.Retry` wrapper if needed
- [ ] Replace `Tinkex.RetryConfig` usages
- [ ] Replace `Tinkex.RetryHandler` usages
- [ ] Replace `lib/tinkex/retry.ex` usages
- [ ] Delete `lib/tinkex/retry_config.ex`
- [ ] Delete `lib/tinkex/retry_handler.ex`
- [ ] Delete `lib/tinkex/retry.ex`
- [ ] Tests pass

### Circuit Breaker Replacement
- [ ] Replace `Tinkex.CircuitBreaker` with `Foundation.CircuitBreaker`
- [ ] Replace `Tinkex.CircuitBreaker.Registry` with `Foundation.CircuitBreaker.Registry`
- [ ] Delete `lib/tinkex/circuit_breaker.ex`
- [ ] Delete `lib/tinkex/circuit_breaker/registry.ex`
- [ ] Tests pass

### Rate Limiting Replacement
- [ ] Replace `Tinkex.RateLimiter` with `Foundation.RateLimit.BackoffWindow`
- [ ] Delete `lib/tinkex/rate_limiter.ex`
- [ ] Tests pass

### Semaphore Replacement
- [ ] Replace `Tinkex.RetrySemaphore` with `Foundation.Semaphore.Counting`
- [ ] Replace `Tinkex.BytesSemaphore` with `Foundation.Semaphore.Weighted`
- [ ] Delete `lib/tinkex/retry_semaphore.ex`
- [ ] Delete `lib/tinkex/bytes_semaphore.ex`
- [ ] Tests pass

### Transform/NotGiven Replacement
- [ ] Replace `Tinkex.NotGiven` with `Sinter.NotGiven`
- [ ] Replace `Tinkex.Transform` with `Sinter.Transform`
- [ ] Delete `lib/tinkex/not_given.ex`
- [ ] Delete `lib/tinkex/transform.ex`
- [ ] Tests pass

### Multipart Replacement
- [ ] Replace `Tinkex.Multipart.Encoder` with `Multipart.Encoder`
- [ ] Replace `Tinkex.Multipart.FormSerializer` with `Multipart.Form`
- [ ] Delete `lib/tinkex/multipart/`
- [ ] Tests pass

---

## Phase 2: Stabilize

- [ ] `mix test` - all pass
- [ ] `mix test --seed 12345` - pass
- [ ] `mix test --seed 99999` - pass
- [ ] `mix test --seed 1` - pass
- [ ] `mix dialyzer` - no errors
- [ ] `mix credo --strict` - no issues
- [ ] No deprecation warnings
- [ ] Commit checkpoint

---

## Phase 3: Hexagonal Refactor

### Define Ports
- [ ] Create `lib/tinkex/ports/http_transport.ex`
- [ ] Create `lib/tinkex/ports/retry_strategy.ex`
- [ ] Create `lib/tinkex/ports/circuit_breaker.ex`
- [ ] Create `lib/tinkex/ports/rate_limiter.ex`
- [ ] Create `lib/tinkex/ports/serializer.ex`
- [ ] Create `lib/tinkex/ports/streaming.ex`
- [ ] Create `lib/tinkex/ports/telemetry.ex`
- [ ] Create `lib/tinkex/ports/pool_manager.ex`

### Create Adapters
- [ ] Create `lib/tinkex/adapters/finch_transport.ex`
- [ ] Create `lib/tinkex/adapters/foundation_retry.ex`
- [ ] Create `lib/tinkex/adapters/foundation_cb.ex`
- [ ] Create `lib/tinkex/adapters/foundation_rate.ex`
- [ ] Create `lib/tinkex/adapters/jason_serializer.ex`
- [ ] Create `lib/tinkex/adapters/sse_streaming.ex`

### Create Context
- [ ] Create `lib/tinkex/context.ex`
- [ ] Wire up adapters via Context

### Reorganize Domain
- [ ] Move `SamplingClient` to `lib/tinkex/domain/sampling/client.ex`
- [ ] Move `TrainingClient` to `lib/tinkex/domain/training/client.ex`
- [ ] Move `Future` to `lib/tinkex/domain/futures/poller.ex`
- [ ] Move `RestClient` to `lib/tinkex/domain/rest/client.ex`
- [ ] Keep types in `lib/tinkex/types/`

### Refactor Clients to Use Ports
- [ ] SamplingClient uses ports via Context
- [ ] TrainingClient uses ports via Context
- [ ] Future uses ports via Context
- [ ] RestClient uses ports via Context

### Delete Old API Layer
- [ ] Delete `lib/tinkex/api/api.ex`
- [ ] Delete `lib/tinkex/api/request.ex`
- [ ] Delete `lib/tinkex/api/response.ex`
- [ ] Delete `lib/tinkex/api/response_handler.ex`
- [ ] Delete `lib/tinkex/api/compression.ex`
- [ ] Delete `lib/tinkex/api/headers.ex`
- [ ] Delete `lib/tinkex/api/url.ex`
- [ ] Delete `lib/tinkex/api/helpers.ex`
- [ ] Delete `lib/tinkex/api/telemetry.ex`
- [ ] Delete `lib/tinkex/api/retry.ex`
- [ ] Delete `lib/tinkex/api/retry_config.ex`
- [ ] Delete `lib/tinkex/api/stream_response.ex`

---

## Phase 4: Stabilize

- [ ] `mix test` - all pass
- [ ] `mix test --seed 12345` - pass
- [ ] `mix dialyzer` - no errors
- [ ] `mix credo --strict` - no issues
- [ ] Domain modules have zero infrastructure imports
- [ ] Commit checkpoint

---

## Phase 5: Extract to Pristine

### Move Ports
- [ ] Move `lib/tinkex/ports/*.ex` to `pristine/lib/pristine/ports/`
- [ ] Update imports/aliases

### Move Adapters
- [ ] Move `lib/tinkex/adapters/*.ex` to `pristine/lib/pristine/adapters/`
- [ ] Update imports/aliases

### Move Context/Pipeline
- [ ] Move Context to `pristine/lib/pristine/core/context.ex`
- [ ] Move Pipeline logic to `pristine/lib/pristine/core/pipeline.ex`

### Update Tinkex to Use Pristine
- [ ] Add pristine as dependency
- [ ] Import ports from pristine
- [ ] Import adapters from pristine
- [ ] Use Pristine.Core.Context

### Create Manifest Schema
- [ ] Define adapter configuration in manifest
- [ ] Define retry policy in manifest
- [ ] Define circuit breaker config in manifest
- [ ] Define pool configuration in manifest
- [ ] Define all 40+ endpoints in manifest
- [ ] Define all types in manifest

---

## Phase 6: Thin Tinkex

### Create Full Manifest
- [ ] Create `lib/tinkex/manifest.yaml` (or .json)
- [ ] Include all endpoints
- [ ] Include all types
- [ ] Include all configuration

### Generate Client
- [ ] Run `mix pristine.generate --manifest manifest.yaml`
- [ ] Verify generated client works

### Delete Infrastructure
- [ ] Delete `lib/tinkex/ports/` (moved to pristine)
- [ ] Delete `lib/tinkex/adapters/` (moved to pristine)
- [ ] Delete `lib/tinkex/context.ex` (moved to pristine)

### Keep Domain-Specific
- [ ] Keep `lib/tinkex/tokenizer.ex`
- [ ] Keep `lib/tinkex/byte_estimator.ex`
- [ ] Keep `lib/tinkex/domain/model_input.ex`

### Final Verification
- [ ] `mix test` - all 1700+ tests pass
- [ ] Hand-written code < 500 lines
- [ ] Generated code handles all infrastructure
- [ ] Commit final state

---

## Success Metrics

- [ ] Pristine: 500+ infrastructure tests
- [ ] Tinkex: 1700+ domain tests
- [ ] Tinkex hand-written lines: < 500
- [ ] All tests seed-independent
- [ ] Zero warnings
