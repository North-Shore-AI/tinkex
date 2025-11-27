# Gap Matrix: Python vs Elixir Retry Configuration

**Date:** 2025-11-26
**Status:** Analysis Complete

---

## Executive Summary

This document provides a **feature-by-feature comparison** of retry-related functionality between Python and Elixir implementations, highlighting gaps and compatibility issues.

**Legend:**
- ✅ **Implemented** - Feature exists and works correctly
- ⚠️ **Partial** - Feature exists but incomplete or incorrect
- ❌ **Missing** - Feature does not exist
- 🔧 **Needs Fix** - Feature exists but has bugs or wrong defaults

---

## 1. Retry Configuration

### 1.1 Configuration Struct

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Dedicated retry config struct** | ✅ `RetryConfig` dataclass | ⚠️ `RetryHandler` struct exists but not exposed | Gap | Need `Tinkex.RetryConfig` module |
| **max_retries field** | ⚠️ No field (uses progress timeout) | ✅ `max_retries: 3` | Difference | Python: unlimited, Elixir: 3 |
| **retry_delay_base** | ✅ `0.5` | ✅ `base_delay_ms: 500` | ✅ Match | Both 500ms |
| **retry_delay_max** | ✅ `10.0` | 🔧 `max_delay_ms: 8000` | Difference | Python: 10s, Elixir: 8s |
| **jitter_factor** | ✅ `0.25` (25%) | 🔧 `jitter_pct: 1.0` **(100%)** | **Critical** | Elixir jitter way too high |
| **progress_timeout** | ✅ `1800.0` (30 min) | 🔧 `progress_timeout_ms: 30000` **(30 sec)** | **Critical** | Elixir timeout way too short |
| **max_connections** | ✅ `100` (semaphore) | ❌ Missing | **Gap** | No concurrency control |
| **enable_retry_logic** | ✅ `True` (boolean flag) | ❌ Missing | Gap | No disable switch |
| **retryable_exceptions** | ✅ Configurable tuple | ❌ Hardcoded in `Error.retryable?/1` | Gap | Not configurable |
| **Hashable for caching** | ✅ `__hash__` method | ❌ Not hashable | Gap | Can't use as map key efficiently |
| **Validation** | ✅ `__post_init__` | ⚠️ In `Config.validate!/1` | Partial | Retry config not validated separately |

**Impact:** 🔴 **HIGH** - Cannot configure retry behavior per SamplingClient

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:38-69
@dataclass
class RetryConfig:
    max_connections: int = DEFAULT_CONNECTION_LIMITS.max_connections or 100
    progress_timeout: float = 30 * 60  # Very long straggler
    retry_delay_base: float = INITIAL_RETRY_DELAY
    retry_delay_max: float = MAX_RETRY_DELAY
    jitter_factor: float = 0.25
    enable_retry_logic: bool = True
    retryable_exceptions: tuple[Type[Exception], ...] = (...)
```

**Elixir Source:**
```elixir
# lib/tinkex/retry_handler.ex:12-32
defstruct [
  :max_retries,
  :base_delay_ms,
  :max_delay_ms,
  :jitter_pct,
  :progress_timeout_ms,
  :attempt,
  :last_progress_at,
  :start_time
]
# Defaults in @default_* module attributes
```

---

### 1.2 SamplingClient Integration

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **retry_config parameter** | ✅ `SamplingClient.__init__(retry_config=...)` | ❌ No parameter | **Critical Gap** | Can't configure retry |
| **Handler creation** | ✅ `_get_retry_handler(session_id, retry_config, telemetry)` | ❌ No handler created | **Critical Gap** | No retry logic |
| **Handler caching** | ✅ `@lru_cache(maxsize=100)` | ❌ No caching | Gap | Would recreate on every call |
| **Named handlers** | ✅ Named by `sampling_session_id` | ❌ N/A | Gap | For logging clarity |
| **Telemetry integration** | ✅ Passed to handler | ❌ N/A | Gap | No retry telemetry |

**Impact:** 🔴 **HIGH** - Core integration missing

**Python Source:**
```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py:59-71
def __init__(
    self,
    holder: InternalClientHolder,
    *,
    sampling_session_id: str,
    retry_config: RetryConfig | None = None,  # <-- Parameter
):
    self.holder = holder
    self.retry_handler = _get_retry_handler(  # <-- Create handler
        sampling_session_id, retry_config=retry_config, telemetry=holder.get_telemetry()
    )
```

**Elixir Source:**
```elixir
# lib/tinkex/sampling_client.ex:92-157
@impl true
def init(opts) do
  config = Keyword.fetch!(opts, :config)
  # No retry_config in opts
  # No handler created
```

---

### 1.3 Request Wrapping

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Retry wrapper around sample** | ✅ `retry_handler.execute(_sample_async)` | ❌ Direct call to API | **Critical Gap** | No retry on errors |
| **Semaphore acquisition** | ✅ Before request execution | ❌ No semaphore | **Gap** | No connection limiting |
| **Progress watchdog** | ✅ Async task monitoring | ❌ No watchdog | Gap | Can't detect stuck requests |
| **max_retries at HTTP layer** | ✅ `max_retries=0` (disabled) | ✅ `max_retries: 0` | ✅ Match | Both delegate to higher layer |

**Impact:** 🔴 **HIGH** - Core retry logic not invoked

**Python Source:**
```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py:232-236
@capture_exceptions(fatal=True)
async def _sample_async_with_retries() -> types.SampleResponse:
    return await self.retry_handler.execute(_sample_async)  # <-- Wrapped
```

**Elixir Source:**
```elixir
# lib/tinkex/sampling_client.ex:207
case entry.sampling_api.sample_async(request, api_opts) do  # <-- Direct call
```

---

## 2. Retry Handler

### 2.1 Core Retry Logic

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Retry loop implementation** | ✅ `_execute_with_retry` | ✅ `Retry.with_retry` | ✅ Exists | But unused |
| **Fast path (retry disabled)** | ✅ Early return if `enable_retry_logic=False` | ❌ No fast path | Gap | Always runs retry logic |
| **Infinite retry with timeout** | ✅ No max attempts, uses progress timeout | ⚠️ `max_retries: 3` default | Difference | Python more lenient |
| **Exception handling** | ✅ Try/catch with telemetry | ✅ Try/rescue with telemetry | ✅ Match | |
| **Error frequency tracking** | ✅ `_errors_since_last_retry` counter | ❌ No tracking | Gap | No error aggregation |

**Impact:** 🟡 **MEDIUM** - Functionality exists but behavioral differences

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:172-236
async def _execute_with_retry(...):
    if not self.config.enable_retry_logic:
        return await func(*args, **kwargs)  # Fast path

    start_time = time.time()
    attempt_count = 0
    while True:  # Infinite loop
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            if not self._should_retry(e):
                raise
            # ... retry logic
```

**Elixir Source:**
```elixir
# lib/tinkex/retry.ex:14-27
def with_retry(fun, opts \\ []) do
  handler = Keyword.get(opts, :handler, RetryHandler.new())
  # No fast path check
  do_retry(fun, handler, metadata)
end

defp do_retry(fun, handler, metadata) do
  if RetryHandler.progress_timeout?(handler) do
    {:error, Error.new(:api_timeout, "Progress timeout exceeded")}
  else
    execute_attempt(fun, handler, metadata)
  end
end
```

---

### 2.2 Retry Decision

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Retryable exception check** | ✅ `isinstance(e, config.retryable_exceptions)` | ✅ `Error.retryable?/1` | ✅ Match | |
| **Retryable status codes** | ✅ 408, 409, 429, 5xx | ✅ Same via `Error.retryable?/1` | ✅ Match | |
| **Configurable exceptions** | ✅ Via `retryable_exceptions` tuple | ❌ Hardcoded | Gap | Not configurable |
| **User error detection** | ✅ `is_user_error(e)` function | ✅ In `Error` module | ✅ Match | |

**Impact:** 🟢 **LOW** - Core logic compatible

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:34-35, 237-247
def is_retryable_status_code(status_code: int) -> bool:
    return status_code in (408, 409, 429) or (500 <= status_code < 600)

def _should_retry(self, exception: Exception) -> bool:
    if isinstance(exception, self.config.retryable_exceptions):
        return True
    if isinstance(exception, tinker.APIStatusError):
        return is_retryable_status_code(exception.status_code)
    return False
```

**Elixir Source:**
```elixir
# lib/tinkex/retry_handler.ex:50-59
def retry?(%__MODULE__{attempt: attempt, max_retries: max}, _error) when attempt >= max do
  false
end

def retry?(%__MODULE__{}, %Error{} = error) do
  Error.retryable?(error)  # Delegates to Error module
end
```

---

### 2.3 Backoff Calculation

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Exponential backoff** | ✅ `base * 2^attempt` | ✅ `base * 2^attempt` | ✅ Match | |
| **Max delay cap** | ✅ `min(delay, max_delay)` | ✅ `min(delay, max_delay)` | ✅ Match | |
| **Jitter calculation** | ✅ `delay * 0.25 * (2*random() - 1)` | 🔧 `delay * 1.0 * random()` | **Different** | Elixir has wrong formula |
| **Jitter range** | ✅ `±25%` of delay | 🔧 `0% to 100%` of delay | **Wrong** | Should be `±25%` |
| **Overflow handling** | ✅ Try/except for `2**attempt` | ❌ No overflow handling | Gap | Could crash on large attempt |
| **Min delay cap** | ✅ `max(0, delay)` | ⚠️ Implicit (always positive) | Minor | |

**Impact:** 🟡 **MEDIUM** - Wrong jitter formula causes different behavior

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:262-276
def _calculate_retry_delay(self, attempt: int) -> float:
    delay = self.config.retry_delay_max
    try:
        delay = min(self.config.retry_delay_base * (2**attempt), self.config.retry_delay_max)
    except OverflowError:
        delay = self.config.retry_delay_max

    jitter = delay * self.config.jitter_factor * (2 * random.random() - 1)
    # Range: [-jitter_factor, +jitter_factor]
    return max(0, min(delay + jitter, self.config.retry_delay_max))
```

**Elixir Source:**
```elixir
# lib/tinkex/retry_handler.ex:61-72
def next_delay(%__MODULE__{} = handler) do
  base = handler.base_delay_ms * :math.pow(2, handler.attempt)
  capped = min(base, handler.max_delay_ms)

  if handler.jitter_pct > 0 do
    jitter = capped * handler.jitter_pct * :rand.uniform()
    # Range: [0, jitter_pct] - THIS IS WRONG!
    round(jitter)
  else
    round(capped)
  end
end
```

**Fix needed:**
```elixir
# Should be:
jitter = capped * handler.jitter_pct * (2 * :rand.uniform() - 1)
# Range: [-jitter_pct, +jitter_pct]
final_delay = max(0, min(capped + jitter, handler.max_delay_ms))
round(final_delay)
```

---

## 3. Connection Limiting

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Semaphore for concurrency** | ✅ `asyncio.Semaphore(max_connections)` | ❌ No semaphore | **Critical Gap** | Can overwhelm connection pool |
| **Wait queue tracking** | ✅ `_waiting_at_semaphore_count` | ❌ N/A | Gap | No visibility into wait queue |
| **In-flight request tracking** | ✅ `_in_retry_loop_count` | ❌ N/A | Gap | No visibility into active requests |
| **Processed request counter** | ✅ `_processed_count` | ❌ N/A | Gap | No success counter |
| **Connection pool limits** | ✅ `max_connections=1000` (httpx) | ✅ Finch pool size 100 | ✅ Exists | Different layer |

**Impact:** 🔴 **HIGH** - Risk of connection pool exhaustion under load

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:86-109
def __init__(self, config: RetryConfig = RetryConfig(), ...):
    # ...
    self._waiting_at_semaphore_count = 0
    self._in_retry_loop_count = 0
    self._processed_count = 0
    self._semaphore = asyncio.Semaphore(config.max_connections)

# Line 111-118
async def execute(self, ...):
    self._waiting_at_semaphore_count += 1
    async with self._semaphore:
        self._waiting_at_semaphore_count -= 1
        self._in_retry_loop_count += 1
        # ... execute request
```

**Elixir Equivalent:** None exists

**Potential Elixir Implementation:**
```elixir
# Could use Semaphore library or process-based limiting
# https://hexdocs.pm/semaphore
{:ok, semaphore} = Semaphore.start_link(max_count: config.max_connections)
Semaphore.call(semaphore, fn ->
  # Execute request
end)
```

---

## 4. Progress Timeout Watchdog

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Watchdog task** | ✅ Separate `asyncio.Task` | ❌ No watchdog task | **Critical Gap** | Can't detect stuck requests |
| **Global progress tracking** | ✅ `_last_global_progress` timestamp | ⚠️ `last_progress_at` in handler | Partial | Exists but not monitored |
| **Task cancellation on timeout** | ✅ `parent_task.cancel()` | ❌ N/A | Gap | No cancellation mechanism |
| **Marker for timeout vs user cancel** | ✅ `_no_progress_made_marker` | ❌ N/A | Gap | Can't distinguish causes |
| **Progress timeout duration** | ✅ 30 minutes | 🔧 30 seconds | **Wrong** | Way too short |
| **Progress update on success** | ✅ Auto-update in `execute()` | ⚠️ Manual in `record_progress()` | Partial | Not called automatically |

**Impact:** 🔴 **HIGH** - Long-running requests can hang indefinitely

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:122-152
async def _check_progress(parent_task: asyncio.Task[T]):
    while True:
        deadline = self._last_global_progress + self.config.progress_timeout
        if time.time() > deadline:
            parent_task._no_progress_made_marker = True
            parent_task.cancel()
        await asyncio.sleep(deadline - time.time())

current_task = asyncio.current_task()
current_task._no_progress_made_marker = False
progress_task = asyncio.create_task(_check_progress(current_task))

try:
    result = await self._execute_with_retry(func, *args, **kwargs)
    self._last_global_progress = time.time()  # Auto-update
    return result
except asyncio.CancelledError:
    if current_task._no_progress_made_marker:  # Timeout, not user cancel
        current_task.uncancel()
        raise tinker.APIConnectionError(
            message=f"No progress made in {self.config.progress_timeout}s. Requests appear to be stuck."
        )
    raise  # Re-raise user cancellation
finally:
    progress_task.cancel()
```

**Elixir Equivalent:** None exists

**Potential Elixir Implementation:**
```elixir
# Start watchdog process
watchdog_pid = spawn_link(fn ->
  check_progress(parent_pid, timeout_ms)
end)

try do
  result = Retry.with_retry(fn -> ... end)
  # Update progress timestamp
  {:ok, result}
after
  Process.exit(watchdog_pid, :kill)
end

defp check_progress(parent, timeout) do
  receive do
    :progress -> check_progress(parent, timeout)
  after
    timeout -> Process.exit(parent, :progress_timeout)
  end
end
```

---

## 5. Rate Limiting

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **429 backoff handling** | ✅ In `_sample_async_impl` | ✅ In `do_sample` | ✅ Match | |
| **Backoff state storage** | ✅ `_sample_backoff_until` (per holder) | ✅ `RateLimiter` (per base_url/key) | Difference | Elixir more granular |
| **Backoff wait loop** | ✅ `await asyncio.sleep(1)` | 🔧 Recursive `Process.sleep(100)` | **Inefficient** | Should calculate exact wait |
| **Backoff duration** | ⚠️ Hardcoded 1 second | ✅ From `Error.retry_after_ms` | **Elixir better** | Uses server hint |
| **Clear backoff on success** | ✅ Yes | ✅ Yes | ✅ Match | |
| **Shared backoff across clients** | ❌ Per holder | ✅ Per `{base_url, api_key}` | **Elixir better** | More accurate |

**Impact:** 🟢 **LOW** - Elixir implementation actually better here

**Python Source:**
```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py:158-179
async def _sample_async_impl(self, ...):
    async with self.holder._sample_dispatch_semaphore:
        while True:
            if (
                self.holder._sample_backoff_until is not None
                and time.time() < self.holder._sample_backoff_until
            ):
                await asyncio.sleep(1)  # Fixed 1 second
                continue
            # ... make request
            if untyped_future is not None:
                break
            self.holder._sample_backoff_until = time.time() + 1  # Hardcoded 1s
            continue
```

**Elixir Source:**
```elixir
# lib/tinkex/sampling_client.ex:183, 209, 263-268
RateLimiter.wait_for_backoff(entry.rate_limiter)  # Before request

{:ok, resp} ->
  RateLimiter.clear_backoff(entry.rate_limiter)

{:error, %Error{status: 429} = error} ->
  maybe_set_backoff(entry.rate_limiter, error)  # Uses retry_after_ms

# lib/tinkex/rate_limiter.ex:68-75
def wait_for_backoff(limiter) do
  if should_backoff?(limiter) do
    Process.sleep(100)  # Fixed 100ms - INEFFICIENT
    wait_for_backoff(limiter)  # Recursive
  else
    :ok
  end
end
```

**Elixir Fix Needed:**
```elixir
def wait_for_backoff(limiter) do
  backoff_until = :atomics.get(limiter, 1)
  now = System.monotonic_time(:millisecond)

  if backoff_until > 0 and backoff_until > now do
    wait_ms = max(backoff_until - now, 0)
    Process.sleep(wait_ms)  # Sleep exact duration, once
  end

  :ok
end
```

---

## 6. Telemetry

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Retry attempt events** | ✅ `RetryHandler.execute.exception` | ✅ `:tinkex, :retry, :attempt, :*` | ✅ Match | |
| **Exception metadata** | ✅ Full (type, message, stack, status) | ✅ Similar | ✅ Match | |
| **Attempt count tracking** | ✅ In event data | ✅ In metadata | ✅ Match | |
| **Elapsed time tracking** | ✅ `start_time`, `current_time`, `elapsed_time` | ✅ `duration` | ✅ Match | |
| **Severity levels** | ✅ WARNING (retryable) vs ERROR (fatal) | ⚠️ No severity levels | Gap | All events same level |
| **User error classification** | ✅ `is_user_error` flag | ⚠️ In Error module but not in telemetry | Gap | Not exposed to telemetry |
| **Progress logging** | ✅ Every 2s, shows queue state | ❌ No progress logging | Gap | No visibility |

**Impact:** 🟡 **MEDIUM** - Harder to debug production issues

**Python Source:**
```python
# tinker/src/tinker/lib/retry_handler.py:195-219
if telemetry := self.get_telemetry():
    telemetry.log(
        "RetryHandler.execute.exception",
        event_data={
            "func": getattr(func, "__qualname__", ...),
            "exception": str(e),
            "exception_type": type(e).__name__,
            "exception_stack": traceback.format_exception(...),
            "status_code": getattr(e, "status_code", None),
            "should_retry": should_retry,
            "is_user_error": user_error,
            "attempt_count": attempt_count,
            "start_time": start_time,
            "current_time": current_time,
            "elapsed_time": current_time - start_time,
        },
        severity="WARNING" if should_retry or user_error else "ERROR",
    )
```

**Elixir Source:**
```elixir
# lib/tinkex/retry.ex:32-36, 72-76
:telemetry.execute(
  @telemetry_start,
  %{system_time: System.system_time()},
  attempt_metadata
)

:telemetry.execute(
  @telemetry_retry,
  %{duration: duration, delay_ms: delay},
  Map.merge(attempt_metadata, %{error: error})
)
```

---

## 7. Handler Lifecycle

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Handler caching** | ✅ `@lru_cache(maxsize=100)` | ❌ No caching | Gap | Would create duplicate handlers |
| **Cache key** | ✅ `(name, hash(config), telemetry)` | ❌ N/A | Gap | Config not hashable |
| **Reuse semaphores** | ✅ Via cache | ❌ N/A | Gap | New semaphore per call |
| **Named handlers** | ✅ For logging clarity | ❌ N/A | Gap | No handler names |
| **Handler creation location** | ✅ `_get_retry_handler` helper | ❌ No creation | Gap | No handlers created |

**Impact:** 🟡 **MEDIUM** - Performance and correctness issue (duplicate semaphores)

**Python Source:**
```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py:320-325
@lru_cache(maxsize=100)
def _get_retry_handler(
    name: str,
    retry_config: RetryConfig | None = None,
    telemetry: Telemetry | None = None
) -> RetryHandler:
    retry_config = retry_config or RetryConfig()
    return RetryHandler(config=retry_config, name=name, telemetry=telemetry)
```

**Elixir Equivalent:** None exists

**Potential Implementation:**
```elixir
# Could use ETS for caching
defp get_retry_handler(name, retry_config, telemetry) do
  key = {:retry_handler, name, retry_config}

  case :ets.lookup(:tinkex_retry_handlers, key) do
    [{^key, handler}] -> handler
    [] ->
      handler = RetryHandler.new(retry_config)
      :ets.insert(:tinkex_retry_handlers, {key, handler})
      handler
  end
end
```

---

## 8. Configuration Integration

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **Config accepts retry_config** | ✅ Optional parameter | ❌ No retry_config field | **Critical Gap** | Can't configure |
| **Default retry config** | ✅ `RetryConfig()` | ❌ N/A | Gap | No defaults |
| **Config validation** | ✅ In `__post_init__` | ❌ No retry validation | Gap | |
| **max_retries field** | ⚠️ Not in RetryConfig | ✅ In `Config` struct | Difference | Different location |
| **Config in opts chain** | ✅ Passed through | ⚠️ Passed but not used for retry | Gap | |

**Impact:** 🔴 **HIGH** - Users cannot configure retry behavior

**Python Source:**
```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py:59-71
def __init__(
    self,
    holder: InternalClientHolder,
    *,
    sampling_session_id: str,
    retry_config: RetryConfig | None = None,  # <-- User-facing parameter
):
    # ...
    self.retry_handler = _get_retry_handler(
        sampling_session_id,
        retry_config=retry_config,  # <-- Passed to handler
        telemetry=holder.get_telemetry()
    )
```

**Elixir Source:**
```elixir
# lib/tinkex/sampling_client.ex:92-99
def init(opts) do
  config = Keyword.fetch!(opts, :config)
  # No retry_config parameter
  # No handler creation
```

---

## 9. Error Handling

| Feature | Python | Elixir | Status | Notes |
|---------|--------|--------|--------|-------|
| **RetryableException type** | ✅ Custom exception class | ❌ No equivalent | Gap | |
| **Error.retryable?** check | ❌ In RetryHandler | ✅ In Error module | ✅ Better | Centralized |
| **Exception to Error conversion** | ✅ Via Tinker exceptions | ✅ In Retry module | ✅ Match | |
| **Stack trace capture** | ✅ Full traceback | ✅ `__STACKTRACE__` | ✅ Match | |

**Impact:** 🟢 **LOW** - Mostly compatible

---

## 10. Summary Tables

### 10.1 Critical Gaps (Must Fix)

| Gap | Python | Elixir | Impact |
|-----|--------|--------|--------|
| **SamplingClient retry integration** | ✅ Integrated | ❌ Missing | 🔴 **Blocks all retry** |
| **retry_config parameter** | ✅ Exposed | ❌ Missing | 🔴 **No user control** |
| **Connection semaphore** | ✅ Per handler | ❌ Missing | 🔴 **Pool exhaustion risk** |
| **Progress watchdog** | ✅ Async task | ❌ Missing | 🔴 **Stuck requests** |
| **Jitter formula** | ✅ Correct | 🔧 **Wrong** | 🔴 **Wrong backoff behavior** |
| **Progress timeout duration** | ✅ 30 min | 🔧 **30 sec** | 🔴 **Kills valid requests** |

### 10.2 Configuration Defaults

| Setting | Python | Elixir | Match? |
|---------|--------|--------|--------|
| max_retries | Unlimited (progress timeout) | 3 | ❌ |
| base_delay | 0.5s | 0.5s | ✅ |
| max_delay | 10.0s | 8.0s | ⚠️ Close |
| jitter | 25% | **100%** | ❌ **Wrong** |
| progress_timeout | 30 min | **30 sec** | ❌ **Wrong** |
| max_connections | 100 | N/A | ❌ **Missing** |

### 10.3 Functionality Checklist

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Retry configuration struct | ✅ | ⚠️ Exists but not exposed | |
| Exponential backoff | ✅ | ✅ | ✅ |
| Jitter | ✅ | 🔧 Wrong formula | |
| Connection limiting | ✅ | ❌ | |
| Progress timeout | ✅ | 🔧 Wrong default | |
| Rate limiting (429) | ✅ | ✅ | ✅ |
| Telemetry events | ✅ | ✅ | ✅ |
| Handler caching | ✅ | ❌ | |
| User-facing config | ✅ | ❌ | |
| Integration with SamplingClient | ✅ | ❌ | |

**Overall Compatibility:** 🔴 **45% Complete**

- ✅ **Core retry logic exists** (Retry + RetryHandler modules)
- ❌ **No integration with SamplingClient**
- ❌ **No user-facing configuration**
- ❌ **Critical features missing** (semaphore, watchdog)
- 🔧 **Several wrong defaults**

---

## 11. Migration Checklist

### Phase 1: Fix Existing Modules (Quick Wins)

- [ ] Fix `RetryHandler.next_delay/1` jitter formula
- [ ] Fix `RetryHandler` progress_timeout default (30s → 30min)
- [ ] Fix `RateLimiter.wait_for_backoff/1` to sleep once instead of recursive
- [ ] Reduce `RetryHandler` jitter_pct default (1.0 → 0.25)

### Phase 2: Create RetryConfig Module

- [ ] Create `lib/tinkex/retry_config.ex`
- [ ] Add all fields from Python `RetryConfig`
- [ ] Implement defaults matching Python
- [ ] Add validation logic
- [ ] Make struct hashable (for ETS caching)

### Phase 3: Add Connection Limiting

- [ ] Add `:semaphore` dependency to `mix.exs`
- [ ] Integrate semaphore into retry execution
- [ ] Add wait queue tracking

### Phase 4: Add Progress Watchdog

- [ ] Implement watchdog process
- [ ] Add progress timestamp updates
- [ ] Handle timeout vs user cancellation

### Phase 5: Integrate with SamplingClient

- [ ] Add `retry_config` option to `SamplingClient.start_link/1`
- [ ] Create `get_retry_handler/3` with ETS caching
- [ ] Wrap `do_sample/4` with `Retry.with_retry/2`
- [ ] Remove `max_retries: 0` from `API.Sampling`

### Phase 6: Testing & Validation

- [ ] Unit tests for retry logic
- [ ] Integration tests with SamplingClient
- [ ] Property tests for backoff calculation
- [ ] Load tests for connection limiting
- [ ] Timeout tests for progress watchdog

---

## 12. Recommended Action Plan

### Immediate (This Week)

1. **Fix critical bugs:**
   - Jitter formula
   - Progress timeout default
   - RateLimiter wait loop

2. **Create RetryConfig module:**
   - Match Python defaults
   - Validate configuration

### Short-term (Next Sprint)

3. **Add connection limiting:**
   - Integrate Semaphore library
   - Track metrics

4. **Integrate with SamplingClient:**
   - Add retry_config parameter
   - Wrap API calls with Retry.with_retry

### Long-term (Future Sprint)

5. **Add progress watchdog:**
   - Implement monitoring process
   - Handle timeouts gracefully

6. **Comprehensive testing:**
   - Unit, integration, property tests
   - Load and stress testing

---

## 13. References

- **Python Implementation:** See `01_python_implementation.md`
- **Elixir Implementation:** See `02_elixir_implementation.md`
- **Implementation Spec:** See `04_implementation_spec.md`
- **Test Plan:** See `05_test_plan.md`
