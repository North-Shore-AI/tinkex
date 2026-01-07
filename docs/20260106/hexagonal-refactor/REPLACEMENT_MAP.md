# Module Replacement Map

Note: this is the original tinkex; ignore `~/p/g/North-Shore-AI/pristine/examples/`. Ports/adapters are created in Phase 3.

## Infrastructure Replacements

### Retry & Backoff

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/retry_config.ex` | ~143 | `Foundation.Retry.Policy` | Config struct |
| `lib/tinkex/retry_handler.ex` | ~170 | `Foundation.Retry` | State machine |
| `lib/tinkex/retry.ex` | ~200 | `Foundation.Retry.run/3` | Orchestration |
| `lib/tinkex/api/retry.ex` | ~150 | `Foundation.Retry` | HTTP retry |
| `lib/tinkex/api/retry_config.ex` | ~80 | `Foundation.Retry.Policy` | Duplicate |

**Total: ~743 lines**

### Circuit Breaker

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/circuit_breaker.ex` | ~235 | `Foundation.CircuitBreaker` | Drop-in |
| `lib/tinkex/circuit_breaker/registry.ex` | ~100 | `Foundation.CircuitBreaker.Registry` | ETS-backed |

**Total: ~335 lines**

### Rate Limiting

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/rate_limiter.ex` | ~84 | `Foundation.RateLimit.BackoffWindow` | Atomics-based |

**Total: ~84 lines**

### Semaphores

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/retry_semaphore.ex` | ~190 | `Foundation.Semaphore.Counting` | Connection limiting |
| `lib/tinkex/bytes_semaphore.ex` | ~101 | `Foundation.Semaphore.Weighted` | Byte-budget |
| `lib/tinkex/semaphore.ex` | ~50 | Delete | Wrapper |

**Total: ~341 lines**

### Transform & NotGiven

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/not_given.ex` | ~47 | `Sinter.NotGiven` | Sentinel values |
| `lib/tinkex/transform.ex` | ~109 | `Sinter.Transform` | Payload transform |

**Total: ~156 lines**

### Multipart

| Tinkex Module | Lines | Replacement | Notes |
|---------------|-------|-------------|-------|
| `lib/tinkex/multipart/encoder.ex` | ~120 | `Multipart.Encoder` | Encoding |
| `lib/tinkex/multipart/form_serializer.ex` | ~80 | `Multipart.Form` | Form building |

**Total: ~200 lines**

---

## Grand Total: ~1,859 lines removable

---

## Domain Logic (Keep As-Is)

These modules contain tinkex-specific business logic and should NOT be replaced:

| Module | Purpose |
|--------|---------|
| `lib/tinkex/sampling_client.ex` | High-level sampling API |
| `lib/tinkex/training_client.ex` | High-level training API |
| `lib/tinkex/rest_client.ex` | High-level REST API |
| `lib/tinkex/service_client.ex` | Service operations |
| `lib/tinkex/future.ex` | Future polling logic |
| `lib/tinkex/session_manager.ex` | Session lifecycle |
| `lib/tinkex/tokenizer.ex` | TikToken integration |
| `lib/tinkex/byte_estimator.ex` | Token estimation |
| `lib/tinkex/config.ex` | SDK configuration |
| `lib/tinkex/error.ex` | Error types |
| `lib/tinkex/types/*.ex` | Domain types (~50 modules) |
| `lib/tinkex/regularizer/*.ex` | Regularization framework |
| `lib/tinkex/regularizers/*.ex` | Regularizer implementations |
| `lib/tinkex/training/custom_loss.ex` | Custom loss functions |

---

## API Modules (Refactor to Use Ports)

These modules should be refactored to use ports/adapters (created in Phase 3):

| Module | Current Role | Future Role |
|--------|--------------|-------------|
| `lib/tinkex/api/sampling.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/training.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/rest.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/futures.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/models.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/weights.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/session.ex` | HTTP calls | Port adapter |
| `lib/tinkex/api/service.ex` | HTTP calls | Port adapter |

---

## HTTP Infrastructure (Move to Pristine)

These modules become part of Pristine's HTTP transport:

| Module | Future Location |
|--------|-----------------|
| `lib/tinkex/api/api.ex` | `pristine/lib/pristine/adapters/http/finch.ex` |
| `lib/tinkex/api/request.ex` | `pristine/lib/pristine/core/request.ex` |
| `lib/tinkex/api/response.ex` | `pristine/lib/pristine/core/response.ex` |
| `lib/tinkex/api/response_handler.ex` | `pristine/lib/pristine/core/response_handler.ex` |
| `lib/tinkex/api/compression.ex` | `pristine/lib/pristine/adapters/http/compression.ex` |
| `lib/tinkex/api/headers.ex` | `pristine/lib/pristine/core/headers.ex` |
| `lib/tinkex/api/url.ex` | `pristine/lib/pristine/core/url.ex` |
| `lib/tinkex/api/helpers.ex` | Delete (utility functions inline) |
| `lib/tinkex/api/telemetry.ex` | `pristine/lib/pristine/adapters/telemetry/default.ex` |
| `lib/tinkex/api/stream_response.ex` | `pristine/lib/pristine/core/stream_response.ex` |

---

## Foundation Library APIs

### Foundation.Retry

```elixir
# Policy creation
policy = Foundation.Retry.Policy.new(
  max_attempts: 4,
  max_elapsed_ms: 60_000,
  backoff: %Foundation.Backoff.Policy{
    type: :exponential,
    base_ms: 500,
    max_ms: 30_000,
    jitter: :factor
  }
)

# Execution
Foundation.Retry.run(fn ->
  make_http_request()
end, policy)

# With progress timeout
Foundation.Retry.run(fn state ->
  result = make_request()
  state = Foundation.Retry.record_progress(state)
  {result, state}
end, policy)
```

### Foundation.CircuitBreaker

```elixir
# Create
cb = Foundation.CircuitBreaker.new("endpoint",
  failure_threshold: 5,
  recovery_time_ms: 30_000
)

# Use
Foundation.CircuitBreaker.call(cb, fn ->
  make_request()
end)

# Registry
Foundation.CircuitBreaker.Registry.get_or_create("endpoint", opts)
```

### Foundation.RateLimit.BackoffWindow

```elixir
# Get limiter for key
limiter = Foundation.RateLimit.BackoffWindow.for_key({base_url, api_key})

# Check/set backoff
if Foundation.RateLimit.BackoffWindow.should_backoff?(limiter) do
  Foundation.RateLimit.BackoffWindow.wait_for_backoff(limiter)
end

# Set backoff from 429 response
Foundation.RateLimit.BackoffWindow.set_backoff(limiter, retry_after_ms)
```

### Foundation.Semaphore.Counting

```elixir
# Create
sem = Foundation.Semaphore.Counting.new(max_permits: 10)

# Acquire/release
Foundation.Semaphore.Counting.with_permit(sem, fn ->
  do_work()
end)
```

### Sinter.NotGiven

```elixir
# Check if value was provided
case value do
  Sinter.NotGiven -> # not provided
  nil -> # explicitly nil
  value -> # has value
end

# In structs
defstruct [
  required_field: nil,
  optional_field: Sinter.NotGiven
]
```

### Sinter.Transform

```elixir
# Transform payload
Sinter.Transform.transform(payload,
  aliases: %{"api_name" => "apiName"},
  formatters: %{timestamp: :iso8601}
)
```
