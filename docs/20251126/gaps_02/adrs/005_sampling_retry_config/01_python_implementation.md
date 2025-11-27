# Python Retry Implementation Deep Dive

**Date:** 2025-11-26
**Status:** Analysis Complete
**Python SDK Path:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker`

---

## Table of Contents

1. [Overview](#overview)
2. [RetryConfig Dataclass](#retryconfig-dataclass)
3. [RetryHandler Implementation](#retryhandler-implementation)
4. [SamplingClient Integration](#samplingclient-integration)
5. [InternalClientHolder Retry Logic](#internalclientholder-retry-logic)
6. [Retry Flow Diagram](#retry-flow-diagram)
7. [Key Design Patterns](#key-design-patterns)

---

## Overview

The Python Tinker SDK implements a **two-layered retry system**:

1. **High-level retry layer** (`RetryHandler`) - Configurable, user-facing, with connection limiting and progress tracking
2. **Low-level retry layer** (`InternalClientHolder.execute_with_retries`) - Basic retry for HTTP operations

This document focuses on the **high-level retry layer** which is the gap in the Elixir implementation.

---

## RetryConfig Dataclass

**File:** `tinker/src/tinker/lib/retry_handler.py`
**Lines:** 38-69

### Source Code

```python
@dataclass
class RetryConfig:
    max_connections: int = DEFAULT_CONNECTION_LIMITS.max_connections or 100
    progress_timeout: float = 30 * 60  # Very long straggler
    retry_delay_base: float = INITIAL_RETRY_DELAY
    retry_delay_max: float = MAX_RETRY_DELAY
    jitter_factor: float = 0.25
    enable_retry_logic: bool = True
    retryable_exceptions: tuple[Type[Exception], ...] = (
        asyncio.TimeoutError,
        tinker.APIConnectionError,
        httpx.TimeoutException,
        RetryableException,
    )

    def __post_init__(self):
        if self.max_connections <= 0:
            raise ValueError(f"max_connections must be positive, got {self.max_connections}")

    def __hash__(self):
        return hash(
            (
                self.max_connections,
                self.progress_timeout,
                self.retry_delay_base,
                self.retry_delay_max,
                self.jitter_factor,
                self.enable_retry_logic,
                self.retryable_exceptions,
            )
        )
```

### Field Breakdown

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `max_connections` | `int` | 100 (from `DEFAULT_CONNECTION_LIMITS`) | Semaphore limit for concurrent requests |
| `progress_timeout` | `float` | 1800.0 (30 minutes) | Timeout for detecting stuck requests |
| `retry_delay_base` | `float` | 0.5 (from `INITIAL_RETRY_DELAY`) | Base delay for exponential backoff |
| `retry_delay_max` | `float` | 10.0 (from `MAX_RETRY_DELAY`) | Maximum delay between retries |
| `jitter_factor` | `float` | 0.25 | Jitter percentage (±25%) to avoid thundering herd |
| `enable_retry_logic` | `bool` | `True` | Global kill switch for retry logic |
| `retryable_exceptions` | `tuple[Type[Exception], ...]` | See above | Exception types that trigger retries |

### Constants (from `_constants.py`)

**File:** `tinker/src/tinker/_constants.py`
**Lines:** 6-12

```python
# default timeout is 1 minute
DEFAULT_TIMEOUT = httpx.Timeout(timeout=60, connect=5.0)
DEFAULT_MAX_RETRIES = 10
DEFAULT_CONNECTION_LIMITS = httpx.Limits(max_connections=1000, max_keepalive_connections=20)

INITIAL_RETRY_DELAY = 0.5
MAX_RETRY_DELAY = 10.0
```

### Key Design Decisions

1. **Hashable:** Implements `__hash__` to allow caching in `_get_retry_handler` (line 320 of `sampling_client.py`)
2. **Validation:** Validates `max_connections > 0` in `__post_init__`
3. **Immutable:** Uses `@dataclass` for immutability and easy construction
4. **Flexible exceptions:** Accepts tuple of exception types for extensibility

---

## RetryHandler Implementation

**File:** `tinker/src/tinker/lib/retry_handler.py`
**Lines:** 71-280

### Class Structure

```python
class RetryHandler(Generic[T]):
    """
    A generalizable retry handler for API requests.

    Features:
    - Connection limiting with semaphores
    - Global progress timeout tracking
    - Exponential backoff with jitter
    - Configurable error classification
    """

    def __init__(
        self,
        config: RetryConfig = RetryConfig(),
        name: str = "default",
        telemetry: Telemetry | None = None,
    ):
        self.config = config
        self.name = name
        self._telemetry = telemetry
        current_time = time.time()
        self._last_global_progress = current_time
        self._last_printed_progress = current_time
        self._processed_count = 0
        self._waiting_at_semaphore_count = 0
        self._in_retry_loop_count = 0
        self._retry_count = 0
        self._exception_counts = {}  # Track exception types and their counts

        self._errors_since_last_retry: defaultdict[str, int] = defaultdict(int)

        # The semaphore is used to limit the number of concurrent requests.
        self._semaphore = asyncio.Semaphore(config.max_connections)
```

### State Tracking

| State Variable | Type | Purpose |
|---------------|------|---------|
| `_last_global_progress` | `float` | Timestamp of last successful request |
| `_last_printed_progress` | `float` | Timestamp of last log message |
| `_processed_count` | `int` | Total successful requests |
| `_waiting_at_semaphore_count` | `int` | Requests blocked on semaphore |
| `_in_retry_loop_count` | `int` | Requests currently executing |
| `_retry_count` | `int` | Total retry attempts |
| `_errors_since_last_retry` | `defaultdict[str, int]` | Error frequency tracking |
| `_semaphore` | `asyncio.Semaphore` | Concurrency limiter |

### Core Method: `execute()`

**Lines:** 111-153

```python
async def execute(self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any) -> T:
    """Use as a direct function call."""

    self._waiting_at_semaphore_count += 1
    async with self._semaphore:
        self._waiting_at_semaphore_count -= 1
        if self._in_retry_loop_count == 0:
            self._last_global_progress = time.time()
        self._in_retry_loop_count += 1
        self._maybe_log_progress()

        async def _check_progress(parent_task: asyncio.Task[T]):
            while True:
                deadline = self._last_global_progress + self.config.progress_timeout
                if time.time() > deadline:
                    parent_task._no_progress_made_marker = True
                    parent_task.cancel()
                await asyncio.sleep(deadline - time.time())

        current_task = asyncio.current_task()
        assert current_task is not None
        current_task._no_progress_made_marker = False
        progress_task = asyncio.create_task(_check_progress(current_task))

        try:
            result = await self._execute_with_retry(func, *args, **kwargs)
            self._last_global_progress = time.time()
            return result
        except asyncio.CancelledError:
            if current_task._no_progress_made_marker:
                current_task.uncancel()
                # Create a dummy request for the exception
                dummy_request = httpx.Request("GET", "http://localhost")
                raise tinker.APIConnectionError(
                    message=f"No progress made in {self.config.progress_timeout}s. Requests appear to be stuck.",
                    request=dummy_request,
                )
            raise
        finally:
            self._in_retry_loop_count -= 1
            self._maybe_log_progress()
            progress_task.cancel()
```

**Key Features:**

1. **Semaphore-based concurrency control** (lines 114-115)
2. **Progress timeout watchdog** (lines 122-128) - Separate async task monitors for stuck requests
3. **Graceful cancellation handling** (lines 139-148) - Distinguishes progress timeout from user cancellation
4. **Automatic progress tracking** (lines 117-118, 137-138)

### Retry Logic: `_execute_with_retry()`

**Lines:** 172-236

```python
async def _execute_with_retry(
    self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any
) -> T:
    """Main retry logic."""
    # Fast path: skip all retry logic if disabled
    if not self.config.enable_retry_logic:
        return await func(*args, **kwargs)

    start_time = time.time()
    attempt_count = 0
    while True:
        current_time = time.time()
        self._maybe_log_progress()
        try:
            attempt_count += 1
            logger.debug(f"Attempting request (attempt #{attempt_count})")
            result = await func(*args, **kwargs)

        except Exception as e:
            exception_str = f"{type(e).__name__}: {str(e) or 'No error message'}"
            self._errors_since_last_retry[exception_str] += 1
            should_retry = self._should_retry(e)
            user_error = is_user_error(e)
            if telemetry := self.get_telemetry():
                current_time = time.time()
                telemetry.log(
                    "RetryHandler.execute.exception",
                    event_data={
                        "func": getattr(func, "__qualname__", ...),
                        "exception": str(e),
                        "exception_type": type(e).__name__,
                        "exception_stack": ...,
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

            if not should_retry:
                logger.error(f"Request failed with non-retryable error: {exception_str}")
                raise

            self._log_retry_reason(e, attempt_count)
            self._retry_count += 1

            # Calculate retry delay with exponential backoff and jitter
            retry_delay = self._calculate_retry_delay(attempt_count - 1)
            logger.debug(f"Retrying in {retry_delay:.2f}s")
            await asyncio.sleep(retry_delay)
        else:
            logger.debug(f"Request succeeded after {attempt_count} attempts")
            self._processed_count += 1
            return result
```

**Key Features:**

1. **Fast path optimization** (lines 177-178) - Skip retry logic entirely if disabled
2. **Infinite retry loop** - No max attempts limit at this level
3. **Comprehensive telemetry** (lines 195-219) - Logs every exception with full context
4. **Error frequency tracking** (line 192) - Aggregates errors for debugging
5. **Exponential backoff with jitter** (line 228-230)

### Retry Decision Logic: `_should_retry()`

**Lines:** 237-247

```python
def _should_retry(self, exception: Exception) -> bool:
    """Determine if an exception should trigger a retry."""
    # Check if it's a generally retryable exception type
    if isinstance(exception, self.config.retryable_exceptions):
        return True

    # Check for API status errors with retryable status codes
    if isinstance(exception, tinker.APIStatusError):
        return is_retryable_status_code(exception.status_code)

    return False
```

**Retryable Status Codes** (line 34-35):

```python
def is_retryable_status_code(status_code: int) -> bool:
    return status_code in (408, 409, 429) or (500 <= status_code < 600)
```

- **408:** Request Timeout
- **409:** Conflict (lock timeout)
- **429:** Too Many Requests (rate limiting)
- **5xx:** Server errors

### Backoff Calculation: `_calculate_retry_delay()`

**Lines:** 262-276

```python
def _calculate_retry_delay(self, attempt: int) -> float:
    """Calculate retry delay with exponential backoff and jitter."""
    delay = self.config.retry_delay_max
    try:
        delay = min(self.config.retry_delay_base * (2**attempt), self.config.retry_delay_max)
    except OverflowError:
        # Handles integer overflow for very large attempt numbers
        delay = self.config.retry_delay_max

    jitter = delay * self.config.jitter_factor * (2 * random.random() - 1)
    # Ensure the final delay doesn't exceed the maximum, even with jitter
    return max(0, min(delay + jitter, self.config.retry_delay_max))
```

**Formula:**
```
base_delay = retry_delay_base * 2^attempt (capped at retry_delay_max)
jitter = base_delay * jitter_factor * random(-1 to +1)
final_delay = clamp(base_delay + jitter, 0, retry_delay_max)
```

**Example with defaults:**
- Attempt 0: 0.5 * 2^0 = 0.5s ± 0.125s → **[0.375s, 0.625s]**
- Attempt 1: 0.5 * 2^1 = 1.0s ± 0.25s → **[0.75s, 1.25s]**
- Attempt 2: 0.5 * 2^2 = 2.0s ± 0.5s → **[1.5s, 2.5s]**
- Attempt 3: 0.5 * 2^3 = 4.0s ± 1.0s → **[3.0s, 5.0s]**
- Attempt 4: 0.5 * 2^4 = 8.0s ± 2.0s → **[6.0s, 10.0s]**
- Attempt 5+: Capped at 10.0s ± 2.5s → **[7.5s, 10.0s]**

### Progress Logging: `_maybe_log_progress()`

**Lines:** 154-170

```python
def _maybe_log_progress(self):
    current_time = time.time()
    elapsed_since_last_printed_progress = current_time - self._last_printed_progress
    finished = self._waiting_at_semaphore_count + self._in_retry_loop_count == 0
    if elapsed_since_last_printed_progress > 2 or finished:
        logger.debug(
            f"[{self.name}]: {self._waiting_at_semaphore_count} waiting, "
            f"{self._in_retry_loop_count} in progress, {self._processed_count} completed"
        )
        if self._errors_since_last_retry:
            sorted_items = sorted(
                self._errors_since_last_retry.items(), key=lambda x: x[1], reverse=True
            )
            logger.debug(
                f"[{self.name}]: {self._retry_count} total retries, "
                f"errors since last log: {sorted_items}"
            )
        self._last_printed_progress = current_time
        self._errors_since_last_retry.clear()
```

**Logging triggers:**
- Every 2 seconds during active processing
- Immediately when all requests complete

**Example log output:**
```
[sampling_session_abc123]: 5 waiting, 10 in progress, 42 completed
[sampling_session_abc123]: 15 total retries, errors since last log: [('APIConnectionError: Connection refused', 3), ('HTTPStatusError: 429', 2)]
```

---

## SamplingClient Integration

**File:** `tinker/src/tinker/lib/public_interfaces/sampling_client.py`
**Lines:** 59-71, 232-236, 320-325

### Initialization

**Lines:** 59-71

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

    self.feature_gates = set(
        os.environ.get("TINKER_FEATURE_GATES", "async_sampling").split(",")
    )
    # ... rest of initialization
```

**Key points:**
1. Accepts optional `retry_config` parameter
2. Uses `_get_retry_handler()` helper with LRU cache
3. Names handler with `sampling_session_id` for logging clarity
4. Passes telemetry instance for integrated logging

### Usage in `sample()` Method

**Lines:** 232-236

```python
@capture_exceptions(fatal=True)
async def _sample_async_with_retries() -> types.SampleResponse:
    return await self.retry_handler.execute(_sample_async)

return self.holder.run_coroutine_threadsafe(_sample_async_with_retries()).future()
```

**Flow:**
1. `sample()` → wraps `_sample_async()` with retry handler
2. `retry_handler.execute(_sample_async)` → handles retries, semaphore, progress timeout
3. `run_coroutine_threadsafe()` → schedules on event loop
4. Returns `Future` to caller

### Handler Caching: `_get_retry_handler()`

**Lines:** 320-325

```python
@lru_cache(maxsize=100)
def _get_retry_handler(
    name: str, retry_config: RetryConfig | None = None, telemetry: Telemetry | None = None
) -> RetryHandler:
    retry_config = retry_config or RetryConfig()
    return RetryHandler(config=retry_config, name=name, telemetry=telemetry)
```

**Purpose:**
- **Cache handlers per unique (name, config, telemetry)** to avoid creating duplicate semaphores
- **maxsize=100** handles up to 100 different sampling sessions
- **Requires hashable `RetryConfig`** (hence `__hash__` implementation)

### Double-Retry Pattern

SamplingClient uses **two layers of retry**:

1. **High-level:** `retry_handler.execute()` - Handles connection limits, progress timeout, exponential backoff
2. **Low-level:** `InternalClientHolder.execute_with_retries()` (line 167)

**Why two layers?**
- High-level: **User-configurable** retry behavior per SamplingClient
- Low-level: **Fallback** retry for basic HTTP failures (used by all API endpoints)

---

## InternalClientHolder Retry Logic

**File:** `tinker/src/tinker/lib/internal_client_holder.py`
**Lines:** 243-306

### Method: `execute_with_retries()`

```python
async def execute_with_retries(
    self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any
) -> T:
    MAX_WAIT_TIME = 60 * 5  # 5 minutes
    start_time = time.time()
    attempt_count = 0
    while True:
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            is_retryable = self._is_retryable_exception(e)
            user_error = is_user_error(e)
            current_time = time.time()
            elapsed_time = current_time - start_time
            if telemetry := self.get_telemetry():
                telemetry.log(
                    "InternalClientHolder.execute_with_retries.exception",
                    event_data={...},
                    severity="WARNING" if is_retryable or user_error else "ERROR",
                )
            if is_retryable and elapsed_time < MAX_WAIT_TIME:
                # Apply exponential backoff
                time_to_wait = min(2**attempt_count, 30)
                attempt_count += 1
                # Don't wait too long if we're almost at the max wait time
                time_to_wait = min(time_to_wait, start_time + MAX_WAIT_TIME - current_time)
                await asyncio.sleep(time_to_wait)
                continue

            raise e
```

### Retryable Exception Check

**Lines:** 243-257

```python
@staticmethod
def _is_retryable_status_code(status_code: int) -> bool:
    return status_code in (408, 409, 429) or (500 <= status_code < 600)

@staticmethod
def _is_retryable_exception(exception: Exception) -> bool:
    RETRYABLE_EXCEPTIONS = (
        asyncio.TimeoutError,
        APIConnectionError,
        httpx.TimeoutException,
    )
    if isinstance(exception, RETRYABLE_EXCEPTIONS):
        return True
    if isinstance(exception, APIStatusError):
        return InternalClientHolder._is_retryable_status_code(exception.status_code)
    return False
```

**Differences from `RetryHandler`:**
- Hardcoded exception list (not configurable)
- No `RetryableException` type
- Same status code logic

### Backoff Formula

```
delay = min(2^attempt, 30 seconds)
capped_delay = min(delay, time_remaining_until_MAX_WAIT_TIME)
```

**No jitter** - simpler than `RetryHandler`

**Example:**
- Attempt 0: 1s
- Attempt 1: 2s
- Attempt 2: 4s
- Attempt 3: 8s
- Attempt 4: 16s
- Attempt 5+: 30s (capped)

---

## Retry Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      SamplingClient.sample()                    │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             _sample_async_with_retries() wrapper                │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                  retry_handler.execute()                        │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 1. Acquire semaphore (max_connections limit)           │    │
│  │ 2. Start progress timeout watchdog                     │    │
│  │ 3. Call _execute_with_retry()                          │    │
│  │ 4. Update progress timestamp on success                │    │
│  │ 5. Release semaphore                                   │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│              retry_handler._execute_with_retry()                │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Loop:                                                   │    │
│  │   1. Attempt request                                   │    │
│  │   2. On exception:                                     │    │
│  │      - Check if retryable (_should_retry)              │    │
│  │      - Log telemetry event                             │    │
│  │      - Calculate backoff with jitter                   │    │
│  │      - Sleep and retry                                 │    │
│  │   3. On success: return result                         │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   _sample_async() - actual work                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ 1. Check backoff state                                 │    │
│  │ 2. Call holder.execute_with_retries()                  │    │
│  │ 3. Handle 429 rate limit (set backoff)                 │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│        InternalClientHolder.execute_with_retries()              │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Loop (max 5 minutes total):                            │    │
│  │   1. Attempt HTTP request                              │    │
│  │   2. On retryable exception:                           │    │
│  │      - Log telemetry                                   │    │
│  │      - Exponential backoff (no jitter)                 │    │
│  │      - Retry                                           │    │
│  │   3. On non-retryable or timeout: raise                │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│              _send_asample_request() - HTTP call                │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ client.sampling.asample(request, max_retries=0)        │    │
│  │ - Hardcoded max_retries=0 at HTTP layer!               │    │
│  │ - Retry handled at higher levels                       │    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Key Observations

1. **max_retries=0** at HTTP layer (line 142 in `sampling_client.py`)
2. **Three retry layers:**
   - `RetryHandler` (configurable, with semaphore)
   - `InternalClientHolder.execute_with_retries` (basic fallback)
   - HTTP client retries (disabled)
3. **Progress timeout is orthogonal to retry logic** - runs in parallel as watchdog

---

## Key Design Patterns

### 1. Configurable vs. Hardcoded Retries

| Aspect | RetryHandler | InternalClientHolder |
|--------|--------------|---------------------|
| Max attempts | Unlimited (runs until progress timeout) | Limited by 5-minute wall clock |
| Exception list | Configurable `RetryConfig.retryable_exceptions` | Hardcoded tuple |
| Backoff | Configurable base, max, jitter | Fixed formula |
| Disable flag | `enable_retry_logic` | No disable option |
| Telemetry | Full event logging | Basic logging |

### 2. Semaphore-Based Concurrency Control

**Purpose:** Prevent overwhelming HTTP connection pool

**Implementation:**
```python
self._semaphore = asyncio.Semaphore(config.max_connections)

async def execute(self, ...):
    self._waiting_at_semaphore_count += 1
    async with self._semaphore:
        self._waiting_at_semaphore_count -= 1
        # ... do work
```

**Benefits:**
- Limits concurrent requests to `max_connections`
- Tracks wait queue size for debugging
- Prevents connection pool exhaustion

### 3. Progress Timeout Watchdog

**Purpose:** Detect and kill stuck requests

**Implementation:**
```python
async def _check_progress(parent_task: asyncio.Task[T]):
    while True:
        deadline = self._last_global_progress + self.config.progress_timeout
        if time.time() > deadline:
            parent_task._no_progress_made_marker = True
            parent_task.cancel()
        await asyncio.sleep(deadline - time.time())
```

**Key points:**
- Runs as separate async task
- Monitors **global progress** across all requests in handler
- Cancels task and sets marker to distinguish from user cancellation
- Converted to `APIConnectionError` with clear message

### 4. LRU-Cached Handler Construction

**Purpose:** Reuse handlers (and their semaphores) across multiple calls

**Implementation:**
```python
@lru_cache(maxsize=100)
def _get_retry_handler(
    name: str, retry_config: RetryConfig | None = None, telemetry: Telemetry | None = None
) -> RetryHandler:
    retry_config = retry_config or RetryConfig()
    return RetryHandler(config=retry_config, name=name, telemetry=telemetry)
```

**Why needed:**
- Each `RetryHandler` has its own semaphore
- Multiple sampling clients may share same config
- Cache prevents creating duplicate semaphores
- Cache key: `(name, hash(retry_config), telemetry)`

### 5. Exponential Backoff with Jitter

**Purpose:** Avoid thundering herd, respect server capacity

**Formula:**
```python
delay = min(retry_delay_base * (2**attempt), retry_delay_max)
jitter = delay * jitter_factor * (2 * random.random() - 1)
final_delay = max(0, min(delay + jitter, retry_delay_max))
```

**Jitter range:** `delay * (1 - jitter_factor)` to `delay * (1 + jitter_factor)`

**Example with defaults (25% jitter):**
- Base delay 2.0s → Final delay in **[1.5s, 2.5s]**

### 6. Infinite Retry with Progress Timeout

**Why no max attempts?**

Instead of hardcoded `max_retries`, Python SDK uses:
1. **Progress timeout (30 min default):** Kill if no forward progress
2. **InternalClientHolder timeout (5 min):** Backstop at lower level

**Advantage:**
- Handles temporary network blips gracefully
- Prevents infinite loops via progress watchdog
- More forgiving than "3 strikes and you're out"

### 7. Telemetry Integration

Every exception logged with full context:
```python
telemetry.log(
    "RetryHandler.execute.exception",
    event_data={
        "func": func.__qualname__,
        "exception": str(e),
        "exception_type": type(e).__name__,
        "exception_stack": traceback.format_exception(...),
        "status_code": getattr(e, "status_code", None),
        "should_retry": should_retry,
        "is_user_error": user_error,
        "attempt_count": attempt_count,
        "elapsed_time": current_time - start_time,
    },
    severity="WARNING" if should_retry else "ERROR",
)
```

**Benefits:**
- Full visibility into retry behavior
- Helps diagnose production issues
- Severity reflects impact (retryable → WARNING, fatal → ERROR)

---

## Summary

The Python implementation provides a **rich, configurable retry system** with:

✅ **User-facing configuration** via `RetryConfig` dataclass
✅ **Connection limiting** via semaphore
✅ **Progress timeout watchdog** to detect stuck requests
✅ **Exponential backoff with jitter** to avoid thundering herd
✅ **Comprehensive telemetry** integration
✅ **Handler caching** to reuse semaphores
✅ **Flexible exception classification** via configurable tuple
✅ **Two-layer retry** (high-level configurable + low-level fallback)

This is the **gold standard** that the Elixir implementation should match.
