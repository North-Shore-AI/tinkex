# ADR-005: Sampling Retry Configuration Support

## Status
Proposed

## Context

### The Gap

The Python Tinker SDK provides extensive retry configuration capabilities for the `SamplingClient`, allowing users to customize retry behavior, backoff strategies, connection limits, and timeout policies. The Elixir Tinkex port currently hardcodes sampling retry behavior with `max_retries: 0` and does not expose retry configuration to callers.

### Python Implementation

The Python SDK implements a sophisticated retry system with the following components:

#### 1. RetryConfig Dataclass
**File:** `tinker/src/tinker/lib/retry_handler.py` (lines 38-68)

```python
@dataclass
class RetryConfig:
    max_connections: int = DEFAULT_CONNECTION_LIMITS.max_connections or 100
    progress_timeout: float = 30 * 60  # Very long straggler (30 minutes)
    retry_delay_base: float = INITIAL_RETRY_DELAY  # 0.5 seconds
    retry_delay_max: float = MAX_RETRY_DELAY  # 10.0 seconds
    jitter_factor: float = 0.25
    enable_retry_logic: bool = True
    retryable_exceptions: tuple[Type[Exception], ...] = (
        asyncio.TimeoutError,
        tinker.APIConnectionError,
        httpx.TimeoutException,
        RetryableException,
    )
```

**Constants from** `tinker/src/tinker/_constants.py` (lines 9-12):
- `DEFAULT_CONNECTION_LIMITS = httpx.Limits(max_connections=1000, max_keepalive_connections=20)`
- `INITIAL_RETRY_DELAY = 0.5`
- `MAX_RETRY_DELAY = 10.0`

#### 2. RetryHandler Class
**File:** `tinker/src/tinker/lib/retry_handler.py` (lines 71-280)

The `RetryHandler` provides:
- **Connection limiting** via semaphores (line 109)
- **Global progress timeout tracking** (lines 95-96, 122-152)
- **Exponential backoff with jitter** (lines 262-276)
- **Configurable error classification** (lines 237-247)
- **Telemetry integration** (lines 195-219)

Key retry logic (lines 172-235):
```python
async def _execute_with_retry(
    self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any
) -> T:
    # Fast path: skip all retry logic if disabled
    if not self.config.enable_retry_logic:
        return await func(*args, **kwargs)

    start_time = time.time()
    attempt_count = 0
    while True:
        try:
            result = await func(*args, **kwargs)
            return result
        except Exception as e:
            should_retry = self._should_retry(e)
            if not should_retry:
                raise

            # Calculate retry delay with exponential backoff and jitter
            retry_delay = self._calculate_retry_delay(attempt_count - 1)
            await asyncio.sleep(retry_delay)
```

Exponential backoff calculation (lines 262-276):
```python
def _calculate_retry_delay(self, attempt: int) -> float:
    delay = min(self.config.retry_delay_base * (2**attempt), self.config.retry_delay_max)
    jitter = delay * self.config.jitter_factor * (2 * random.random() - 1)
    return max(0, min(delay + jitter, self.config.retry_delay_max))
```

#### 3. SamplingClient Integration
**File:** `tinker/src/tinker/lib/public_interfaces/sampling_client.py`

**Constructor** (lines 59-71):
```python
def __init__(
    self,
    holder: InternalClientHolder,
    *,
    sampling_session_id: str,
    retry_config: RetryConfig | None = None,
):
    self.holder = holder

    # Create retry handler with the provided configuration
    self.retry_handler = _get_retry_handler(
        sampling_session_id, retry_config=retry_config, telemetry=holder.get_telemetry()
    )
```

**Retry handler factory** (lines 320-325):
```python
@lru_cache(maxsize=100)
def _get_retry_handler(
    name: str, retry_config: RetryConfig | None = None, telemetry: Telemetry | None = None
) -> RetryHandler:
    retry_config = retry_config or RetryConfig()
    return RetryHandler(config=retry_config, name=name, telemetry=telemetry)
```

**Usage in sample()** (lines 232-233):
```python
async def _sample_async_with_retries() -> types.SampleResponse:
    return await self.retry_handler.execute(_sample_async)
```

**Note:** The Python SDK still sets `max_retries=0` for the underlying HTTP call (line 142) because the `RetryHandler` wraps the entire sampling operation, providing higher-level retry logic that handles 429 backoff and other stateful behaviors.

#### 4. ServiceClient API
**File:** `tinker/src/tinker/lib/public_interfaces/service_client.py` (lines 278-320)

```python
def create_sampling_client(
    self,
    model_path: str | None = None,
    base_model: str | None = None,
    retry_config: RetryConfig | None = None,
) -> SamplingClient:
    """Create a SamplingClient for text generation.

    Args:
    - retry_config: Optional configuration for retrying failed requests
    """
```

Users can pass custom retry configurations:
```python
# Custom retry config with different backoff strategy
custom_retry = RetryConfig(
    max_connections=50,
    retry_delay_base=1.0,
    retry_delay_max=20.0,
    jitter_factor=0.5,
    progress_timeout=60 * 10,  # 10 minutes
    enable_retry_logic=True
)

sampling_client = service_client.create_sampling_client(
    base_model="Qwen/Qwen2.5-7B",
    retry_config=custom_retry
)
```

### Elixir Implementation

The Elixir SDK has a fundamentally different architecture with retry logic split across multiple layers:

#### 1. HTTP Layer Retry (Tinkex.API)
**File:** `lib/tinkex/api/api.ex` (lines 21-23, 455-561)

```elixir
@initial_retry_delay 500
@max_retry_delay 8_000
@max_retry_duration_ms 30_000

defp with_retries(request, pool, timeout, _pool_key, max_retries) do
  # Implements exponential backoff with jitter
  # Retries on: 429, 408, 500-599, transport errors
end

defp retry_delay(attempt) do
  base_delay = @initial_retry_delay * :math.pow(2, attempt)
  delay = min(base_delay * :rand.uniform(), @max_retry_delay)
  round(delay)
end
```

**Retryable conditions:**
- Status 429 (rate limit) - uses server `Retry-After` header
- Status 408 (timeout)
- Status 500-599 (server errors)
- Transport/connection errors
- Custom `x-should-retry` header

#### 2. Config-Level Settings
**File:** `lib/tinkex/config.ex` (lines 20, 35, 57-58)

```elixir
defstruct [:base_url, :api_key, :http_pool, :timeout, :max_retries, :user_metadata]

@default_max_retries 2
```

Users can configure `max_retries` at the config level:
```elixir
config = Tinkex.Config.new(
  api_key: "...",
  max_retries: 5  # Applied to all HTTP requests
)
```

#### 3. Sampling-Specific Behavior
**File:** `lib/tinkex/api/sampling.ex` (lines 28-38)

```elixir
def sample_async(request, opts) do
  opts =
    opts
    |> Keyword.put(:pool_type, :sampling)
    |> Keyword.put(:max_retries, 0)  # HARDCODED
    |> Keyword.put_new(:sampling_backpressure, true)

  Tinkex.API.post("/api/v1/asample", request, opts)
end
```

**Critical Issue:** `max_retries: 0` is hardcoded, overriding any config-level setting.

**Comment (lines 13-16):**
> Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry so that the higher-level client can make intelligent retry decisions based on rate limit state.

#### 4. RateLimiter for Backoff
**File:** `lib/tinkex/rate_limiter.ex`

Provides shared backoff state per `{base_url, api_key}`:
- `wait_for_backoff/1` - Blocks until backoff window passes
- `set_backoff/2` - Sets backoff duration from 429 responses
- `should_backoff?/1` - Checks if currently in backoff

**File:** `lib/tinkex/sampling_client.ex` (lines 183, 209, 212-214)

```elixir
defp do_sample(client, prompt, sampling_params, opts) do
  RateLimiter.wait_for_backoff(entry.rate_limiter)

  case entry.sampling_api.sample_async(request, api_opts) do
    {:ok, resp} ->
      RateLimiter.clear_backoff(entry.rate_limiter)

    {:error, %Error{status: 429} = error} ->
      maybe_set_backoff(entry.rate_limiter, error)
      {:error, error}
  end
end
```

#### 5. Unused RetryHandler
**Files:** `lib/tinkex/retry_handler.ex` and `lib/tinkex/retry.ex`

These modules exist but are **not used** by `SamplingClient`:

```elixir
# lib/tinkex/retry_handler.ex
defmodule Tinkex.RetryHandler do
  @default_max_retries 3
  @default_base_delay_ms 500
  @default_max_delay_ms 8_000
  @default_jitter_pct 1.0
  @default_progress_timeout_ms 30_000

  def new(opts \\ [])  # Supports customization
  def retry?(handler, error)  # Checks Error.retryable?
  def next_delay(handler)  # Exponential backoff with jitter
  def progress_timeout?(handler)  # Checks for stuck requests
end
```

### Key Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Retry Config** | `RetryConfig` dataclass passed to `SamplingClient` | Config-level `max_retries` overridden to 0 |
| **Configuration Points** | Per-client (can customize per sampling session) | Global config only |
| **HTTP Retries** | Disabled (`max_retries=0`) at HTTP layer | Also disabled (`max_retries=0`) |
| **High-Level Retries** | `RetryHandler.execute()` wraps sampling calls | No high-level retry wrapper |
| **Backoff Strategy** | Exponential with configurable jitter (0.5s - 10s) | Exponential with random jitter (0.5s - 8s) |
| **Connection Limiting** | Semaphore with configurable `max_connections` | No explicit limit (uses pool size) |
| **Progress Timeout** | Configurable (default 30 min) | Fixed at HTTP level (30s) |
| **Retryable Errors** | Configurable exception tuple | Hardcoded status codes |
| **Telemetry** | Integrated with retry attempts | Separate telemetry for HTTP layer |
| **429 Handling** | Retry with server-specified backoff | Return error, set shared backoff state |

### Current Gaps

1. **No per-client retry configuration** - Users cannot customize retry behavior for specific sampling clients
2. **No high-level retry wrapper** - Sampling operations fail on first error (except 429 backoff)
3. **Fixed backoff parameters** - Cannot adjust base delay, max delay, or jitter
4. **No progress timeout** - Long-running requests have no configurable timeout
5. **No connection limiting** - No semaphore-based concurrency control
6. **RetryHandler unused** - Existing retry infrastructure not integrated
7. **Inflexible error handling** - Cannot customize which errors trigger retries

## Decision Drivers

1. **API Parity** - Elixir SDK should offer similar capabilities to Python SDK
2. **User Control** - Users need to tune retry behavior for their workloads
3. **Reliability** - Transient failures should be handled gracefully
4. **Observability** - Retry attempts should be visible in telemetry
5. **Performance** - Connection limiting prevents resource exhaustion
6. **Backwards Compatibility** - Changes should not break existing code
7. **Elixir Idioms** - Solution should feel natural in Elixir/OTP

## Considered Options

### Option 1: Port Python's RetryConfig Directly

Create an Elixir equivalent of Python's `RetryConfig` dataclass and integrate it with `SamplingClient`.

**Pros:**
- Direct API parity with Python SDK
- All Python use cases supported
- Clear migration path for Python users

**Cons:**
- Duplicates some functionality in `Tinkex.RetryHandler`
- Doesn't leverage Elixir's existing retry infrastructure
- May feel un-idiomatic to Elixir developers

**Implementation:**
```elixir
defmodule Tinkex.SamplingRetryConfig do
  defstruct [
    max_connections: 100,
    progress_timeout_ms: 30 * 60 * 1000,
    retry_delay_base_ms: 500,
    retry_delay_max_ms: 10_000,
    jitter_factor: 0.25,
    enable_retry_logic: true,
    retryable_statuses: [408, 409, 429] ++ Enum.to_list(500..599)
  ]
end
```

### Option 2: Enhance Existing RetryHandler

Extend `Tinkex.RetryHandler` and integrate it into `SamplingClient` while keeping Elixir naming conventions.

**Pros:**
- Leverages existing code (`lib/tinkex/retry_handler.ex`, `lib/tinkex/retry.ex`)
- More idiomatic Elixir (uses GenServer/Task patterns)
- Reusable across other clients (TrainingClient, etc.)
- Already has telemetry integration

**Cons:**
- API differs from Python (may confuse cross-language users)
- Need to add connection limiting feature
- Need to add progress timeout feature

**Implementation:**
```elixir
# Enhanced RetryHandler
defmodule Tinkex.RetryHandler do
  defstruct [
    :max_retries,
    :base_delay_ms,
    :max_delay_ms,
    :jitter_pct,
    :progress_timeout_ms,
    :max_connections,  # NEW
    :enable_retry_logic,  # NEW
    :retryable_statuses,  # NEW
    # ... existing fields
  ]
end

# SamplingClient init
def init(opts) do
  retry_handler =
    opts
    |> Keyword.get(:retry_config, [])
    |> RetryHandler.new()

  # Store in state
end
```

### Option 3: Hybrid Approach - Config Builder + RetryHandler

Provide a `Tinkex.SamplingClient.RetryConfig` builder that creates options for the existing `RetryHandler`, maintaining API similarity to Python while using Elixir's infrastructure.

**Pros:**
- Familiar API for Python SDK users
- Uses proven Elixir retry infrastructure
- Clean separation of concerns
- Easy to document migration from Python

**Cons:**
- Extra layer of indirection
- Two ways to configure retries (direct opts vs config struct)

**Implementation:**
```elixir
defmodule Tinkex.SamplingClient.RetryConfig do
  @moduledoc """
  Retry configuration for SamplingClient.

  Similar to Python's tinker.lib.retry_handler.RetryConfig.
  """

  defstruct [
    max_retries: 3,
    base_delay_ms: 500,
    max_delay_ms: 10_000,
    jitter_pct: 0.25,
    progress_timeout_ms: 30 * 60 * 1000,
    enable_retry_logic: true,
    retryable_statuses: [408, 409, 429] ++ Enum.to_list(500..599)
  ]

  def to_handler_opts(%__MODULE__{} = config) do
    [
      max_retries: config.max_retries,
      base_delay_ms: config.base_delay_ms,
      max_delay_ms: config.max_delay_ms,
      jitter_pct: config.jitter_pct,
      progress_timeout_ms: config.progress_timeout_ms
    ]
  end
end
```

## Decision

**Recommended: Option 3 - Hybrid Approach**

Implement a `Tinkex.SamplingClient.RetryConfig` module that mirrors Python's API surface while delegating to the existing `Tinkex.RetryHandler` infrastructure. This provides:

1. **API Parity** - Python users see familiar configuration options
2. **Code Reuse** - Leverages existing, tested retry logic
3. **Flexibility** - Both struct-based and keyword-based configuration
4. **Discoverability** - Clear documentation linking to Python SDK
5. **Maintainability** - Single retry implementation to maintain

### Architecture Changes

1. **Remove hardcoded `max_retries: 0`** in `Tinkex.API.Sampling.sample_async/2`
2. **Add retry_config parameter** to `SamplingClient.init/1`
3. **Wrap sample operations** with `Tinkex.Retry.with_retry/2`
4. **Integrate RateLimiter** into retry decision logic
5. **Add telemetry** for retry attempts

## Consequences

### Positive

1. **Feature Parity** - Elixir SDK matches Python SDK capabilities
2. **User Empowerment** - Teams can tune retries for their infrastructure
3. **Better Reliability** - Transient failures handled automatically
4. **Observability** - Retry metrics visible in telemetry
5. **Backwards Compatible** - Default behavior unchanged (can enable via config)
6. **Documentation** - Clear migration guide from Python SDK
7. **Testing** - Property-based tests can verify retry behavior

### Negative

1. **Complexity** - More configuration surface area
2. **Testing Burden** - More edge cases to test (retry loops, timeouts, etc.)
3. **Breaking Change Risk** - If default retry behavior changes
4. **Migration Work** - Existing users may need to adjust configs
5. **Documentation Debt** - Need comprehensive examples and guides

### Neutral

1. **Performance Impact** - Retries add latency on failures (by design)
2. **Memory Usage** - Retry state stored per sampling client
3. **API Surface** - More options means more to learn

## Implementation Plan

### Phase 1: Core Retry Infrastructure (Week 1)

**Files to modify:**
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\sampling_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\api\sampling.ex`

**Changes:**

1. **Create RetryConfig module** (`lib/tinkex/sampling_client/retry_config.ex`):
```elixir
defmodule Tinkex.SamplingClient.RetryConfig do
  @moduledoc """
  Retry configuration for SamplingClient.

  Mirrors Python SDK's `tinker.lib.retry_handler.RetryConfig`.

  ## Fields

  - `max_retries` - Maximum retry attempts (default: 3)
  - `base_delay_ms` - Initial retry delay in milliseconds (default: 500)
  - `max_delay_ms` - Maximum retry delay in milliseconds (default: 10_000)
  - `jitter_pct` - Jitter as percentage of delay (default: 0.25)
  - `progress_timeout_ms` - Timeout for stuck requests (default: 1_800_000 = 30 min)
  - `enable_retry_logic` - Enable/disable retries (default: true)
  - `retryable_statuses` - HTTP status codes to retry (default: [408, 409, 429, 500-599])

  ## Examples

      # Default configuration
      config = %RetryConfig{}

      # Custom aggressive retries
      config = %RetryConfig{
        max_retries: 5,
        base_delay_ms: 1000,
        max_delay_ms: 20_000,
        jitter_pct: 0.5,
        progress_timeout_ms: 600_000  # 10 minutes
      }

      # Disable retries
      config = %RetryConfig{enable_retry_logic: false}
  """

  defstruct [
    max_retries: 3,
    base_delay_ms: 500,
    max_delay_ms: 10_000,
    jitter_pct: 0.25,
    progress_timeout_ms: 30 * 60 * 1000,  # 30 minutes
    enable_retry_logic: true,
    retryable_statuses: [408, 409, 429] ++ Enum.to_list(500..599)
  ]

  @type t :: %__MODULE__{
    max_retries: non_neg_integer(),
    base_delay_ms: pos_integer(),
    max_delay_ms: pos_integer(),
    jitter_pct: float(),
    progress_timeout_ms: pos_integer(),
    enable_retry_logic: boolean(),
    retryable_statuses: [pos_integer()]
  }

  @doc """
  Convert RetryConfig to RetryHandler options.
  """
  def to_handler_opts(%__MODULE__{} = config) do
    [
      max_retries: config.max_retries,
      base_delay_ms: config.base_delay_ms,
      max_delay_ms: config.max_delay_ms,
      jitter_pct: config.jitter_pct,
      progress_timeout_ms: config.progress_timeout_ms
    ]
  end
end
```

2. **Modify SamplingClient.init/1** to accept retry_config:
```elixir
# In lib/tinkex/sampling_client.ex
def init(opts) do
  # ... existing code ...

  retry_config =
    opts
    |> Keyword.get(:retry_config, %Tinkex.SamplingClient.RetryConfig{})
    |> case do
      %Tinkex.SamplingClient.RetryConfig{} = config -> config
      opts when is_list(opts) -> struct(Tinkex.SamplingClient.RetryConfig, opts)
    end

  # Store in state and registry
  entry = %{
    # ... existing fields ...
    retry_config: retry_config
  }
end
```

3. **Remove hardcoded max_retries: 0** from `lib/tinkex/api/sampling.ex`:
```elixir
def sample_async(request, opts) do
  opts =
    opts
    |> Keyword.put(:pool_type, :sampling)
    # REMOVED: |> Keyword.put(:max_retries, 0)
    |> Keyword.put_new(:sampling_backpressure, true)
    |> Keyword.put_new(:max_retries, opts[:retry_config][:max_retries] || 0)  # Use config value

  Tinkex.API.post("/api/v1/asample", request, opts)
end
```

### Phase 2: Integrate with Retry Logic (Week 2)

**Files to modify:**
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\sampling_client.ex`
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\retry.ex`

**Changes:**

1. **Enhance RetryHandler** to check status codes:
```elixir
# In lib/tinkex/retry_handler.ex
def retry?(%__MODULE__{} = handler, %Error{status: status} = error, retryable_statuses) do
  cond do
    handler.attempt >= handler.max_retries -> false
    status in retryable_statuses -> true
    Error.retryable?(error) -> true
    true -> false
  end
end
```

2. **Wrap do_sample with retry logic**:
```elixir
# In lib/tinkex/sampling_client.ex
defp do_sample(client, prompt, sampling_params, opts) do
  case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
    [{{:config, ^client}, entry}] ->
      if entry.retry_config.enable_retry_logic do
        do_sample_with_retry(entry, prompt, sampling_params, opts)
      else
        do_sample_once(entry, prompt, sampling_params, opts)
      end
  end
end

defp do_sample_with_retry(entry, prompt, sampling_params, opts) do
  handler = RetryHandler.new(RetryConfig.to_handler_opts(entry.retry_config))

  Tinkex.Retry.with_retry(
    fn -> do_sample_once(entry, prompt, sampling_params, opts) end,
    handler: handler,
    telemetry_metadata: entry.telemetry_metadata
  )
end

defp do_sample_once(entry, prompt, sampling_params, opts) do
  RateLimiter.wait_for_backoff(entry.rate_limiter)
  seq_id = next_seq_id(entry.request_id_counter)

  # ... existing sample logic ...
end
```

### Phase 3: ServiceClient API (Week 2)

**Files to modify:**
- `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\service_client.ex`

**Changes:**

```elixir
@spec create_sampling_client_async(pid(), keyword()) :: Task.t()
def create_sampling_client_async(service_pid, opts \\ []) do
  # Extract retry_config from opts
  retry_config = Keyword.get(opts, :retry_config)

  # Pass to SamplingClient.create_async
  opts = Keyword.put(opts, :retry_config, retry_config)

  SamplingClient.create_async(service_pid, opts)
end
```

### Phase 4: Testing (Week 3)

**New test files:**
- `test/tinkex/sampling_client/retry_config_test.exs`
- `test/tinkex/sampling_client_retry_test.exs`

**Test cases:**

1. **RetryConfig struct validation**
   - Default values match Python SDK
   - Invalid values raise errors
   - Conversion to handler opts

2. **Retry behavior**
   - Retries on 429, 408, 500-599
   - Does not retry on 400, 401, 404
   - Respects max_retries limit
   - Uses exponential backoff with jitter
   - Progress timeout triggers

3. **Backwards compatibility**
   - Default behavior unchanged when no retry_config
   - Existing code continues to work

4. **Integration tests**
   - End-to-end retry flow with mock server
   - Telemetry events emitted correctly
   - RateLimiter integration

### Phase 5: Documentation (Week 3)

**New documentation:**
- `docs/sampling_retry_config.md` - Comprehensive guide
- Update `README.md` with retry config examples
- Add docstrings to all new modules/functions
- Create migration guide from Python SDK

**Documentation content:**

```markdown
# Sampling Retry Configuration

The Tinkex SDK provides fine-grained control over retry behavior for sampling operations.

## Quick Start

```elixir
# Default retry behavior (matches Python SDK)
{:ok, client} = Tinkex.ServiceClient.create_sampling_client_async(service_pid,
  base_model: "Qwen/Qwen2.5-7B"
) |> Task.await()

# Custom retry config
retry_config = %Tinkex.SamplingClient.RetryConfig{
  max_retries: 5,
  base_delay_ms: 1000,
  max_delay_ms: 20_000,
  jitter_pct: 0.5
}

{:ok, client} = Tinkex.ServiceClient.create_sampling_client_async(service_pid,
  base_model: "Qwen/Qwen2.5-7B",
  retry_config: retry_config
) |> Task.await()

# Disable retries
{:ok, client} = Tinkex.ServiceClient.create_sampling_client_async(service_pid,
  base_model: "Qwen/Qwen2.5-7B",
  retry_config: %Tinkex.SamplingClient.RetryConfig{enable_retry_logic: false}
) |> Task.await()
```

## Migrating from Python SDK

| Python | Elixir |
|--------|--------|
| `RetryConfig(max_connections=50)` | Not yet supported (future enhancement) |
| `RetryConfig(progress_timeout=600)` | `%RetryConfig{progress_timeout_ms: 600_000}` |
| `RetryConfig(retry_delay_base=1.0)` | `%RetryConfig{base_delay_ms: 1000}` |
| `RetryConfig(retry_delay_max=20.0)` | `%RetryConfig{max_delay_ms: 20_000}` |
| `RetryConfig(jitter_factor=0.5)` | `%RetryConfig{jitter_pct: 0.5}` |
| `RetryConfig(enable_retry_logic=False)` | `%RetryConfig{enable_retry_logic: false}` |

## Configuration Options

See `Tinkex.SamplingClient.RetryConfig` for complete API documentation.
```

### Phase 6: Rollout Plan

1. **Week 1-2:** Implement core features behind feature flag
2. **Week 3:** Internal testing with production workloads
3. **Week 4:** Documentation review and beta release
4. **Week 5:** Gather feedback, fix issues
5. **Week 6:** GA release with migration guide

### Future Enhancements (Not in Scope)

1. **Connection limiting** - Add semaphore-based concurrency control (similar to Python's `max_connections`)
2. **Custom retryable exceptions** - Allow users to define which errors trigger retries
3. **Per-request retry override** - Pass retry config to individual `sample/4` calls
4. **Retry budgets** - Limit total retry time across all requests
5. **Circuit breaker** - Fail fast when server is consistently down

## References

### Python SDK Files
- `tinker/src/tinker/lib/retry_handler.py` - RetryConfig and RetryHandler implementation
- `tinker/src/tinker/lib/public_interfaces/sampling_client.py` - SamplingClient integration
- `tinker/src/tinker/lib/public_interfaces/service_client.py` - ServiceClient API
- `tinker/src/tinker/_constants.py` - Default retry constants

### Elixir SDK Files
- `lib/tinkex/sampling_client.ex` - SamplingClient implementation
- `lib/tinkex/api/sampling.ex` - Sampling API with hardcoded max_retries: 0
- `lib/tinkex/rate_limiter.ex` - Backoff state management
- `lib/tinkex/retry_handler.ex` - Existing retry infrastructure (unused)
- `lib/tinkex/retry.ex` - Retry execution logic (unused)
- `lib/tinkex/api/api.ex` - HTTP-level retry logic
- `lib/tinkex/config.ex` - Config-level max_retries setting

### Design Principles
- **Phase 4 Comment** (sampling.ex:13-16): Rationale for max_retries: 0 at HTTP layer
- **Python Retry Philosophy**: High-level retry wrapper + disabled HTTP retries for intelligent backoff
- **Elixir Current State**: HTTP retries disabled, no high-level wrapper, RateLimiter for shared state
