# Error Handling and Retry Logic

**⚠️ UPDATED:** This document has been corrected based on critique 400+.

**Key Corrections (Round 4 - Critique 400+):**
- **Error categories**: Updated from `USER_ERROR/TRANSIENT/FATAL` to `Unknown/Server/User` (actual Python SDK values)
- **Truth table**: Added explicit error handling decision table
- **429 handling**: Clarified retry behavior with Retry-After support
- **Retry logic**: Updated `retryable?` to match Python `is_retryable` behavior

**Key Corrections (Round 5 - Final):**
- **x-should-retry integration**: Added comprehensive decision table with server-controlled retry logic
- **Unified retry policy**: Documented priority order (header → category → status → type)
- **should_retry?/2 function**: New function that honors x-should-retry header before standard logic

## Python Exception Hierarchy

The Tinker SDK defines a comprehensive exception hierarchy:

```python
TinkerError (base exception)
├── APIError
│   ├── APIConnectionError (network/connection issues)
│   ├── APITimeoutError (request timeout)
│   ├── APIResponseValidationError (invalid response data)
│   └── APIStatusError (HTTP status errors)
│       ├── BadRequestError (400)
│       ├── AuthenticationError (401)
│       ├── PermissionDeniedError (403)
│       ├── NotFoundError (404)
│       ├── ConflictError (409)
│       ├── UnprocessableEntityError (422)
│       ├── RateLimitError (429)
│       └── InternalServerError (500+)
└── RequestFailedError (server-side operation failed)
```

### Exception Definitions

```python
# _exceptions.py
class TinkerError(Exception):
    """Base exception for all Tinker SDK errors"""
    pass

class APIError(TinkerError):
    """Base for all API-related errors"""
    pass

class APIStatusError(APIError):
    """HTTP status code error"""
    def __init__(self, message: str, *, response: httpx.Response, body: object):
        super().__init__(message)
        self.response = response
        self.body = body
        self.status_code = response.status_code

class RequestFailedError(TinkerError):
    """Server reported operation failed"""
    def __init__(
        self,
        message: str,
        *,
        request_id: str,
        error_category: RequestErrorCategory,
        details: dict | None = None,
    ):
        super().__init__(message)
        self.request_id = request_id
        self.error_category = error_category  # RequestErrorCategory (Unknown/Server/User)
        self.details = details
```

## Error Categories ⚠️ UPDATED (Round 4)

**ACTUAL Python SDK values** (verified from source):

```python
class RequestErrorCategory(StrEnum):
    Unknown = auto()
    Server = auto()
    User = auto()

# ⚠️ Wire casing is ambiguous:
# - Default StrEnum.auto() returns "Unknown"/"Server"/"User".
# - Earlier docs referenced lowercase due to an _types.StrEnum patch,
#   but that patch is not visible in this repo snapshot.
# Treat responses as case-insensitive until verified at runtime.
```

### 1. User Errors (Non-Retryable)

**Category:** `RequestErrorCategory.User`
**Wire value:** `"User"` (default StrEnum) **or** `"user"` if `_types` lowercases (parser handles both)

Errors caused by invalid input:

**Examples:**
- Invalid tensor shapes
- Missing required fields
- Invalid parameter values
- Model not found
- 4xx HTTP errors (except 408, 429)

**Handling:**
- Never retry
- Propagate immediately to user
- Include detailed error message

### 2. Server Errors (Retryable)

**Category:** `RequestErrorCategory.Server`
**Wire value:** `"Server"` (default StrEnum) **or** `"server"` if `_types` lowercases

Server-side failures that may succeed on retry:

**Examples:**
- 500 Internal Server Error
- 503 Service Unavailable
- Queue overload
- Temporary resource exhaustion

**Handling:**
- Retry with exponential backoff
- Maximum retry attempts
- Track retry count in telemetry

### 3. Unknown Errors (Retryable)

**Category:** `RequestErrorCategory.Unknown`
**Wire value:** `"Unknown"` (default StrEnum) **or** `"unknown"` if `_types` lowercases

Errors where cause is unclear - assume retryable for safety:

**Examples:**
- Network connection errors
- Timeout errors (408)
- Unexpected failures

**Handling:**
- Retry with exponential backoff
- Log for investigation
- Treat as potentially transient

### 4. Special Case: Rate Limiting (Retryable with Backoff)

**HTTP Status:** 429 (Not an error category, but special retry behavior)

**Handling:**
- Retry after backoff period
- Use server-provided `Retry-After` header
- Share backoff state across concurrent requests (for SamplingClient)

## Error Handling Decision Table ⚠️ NEW (Round 5)

Comprehensive truth table for retry logic (matches Python SDK + x-should-retry integration):

| Condition | Category | User Error? | Retryable? | Notes |
|-----------|----------|-------------|------------|-------|
| **x-should-retry: "true"** | - | NO | **YES** | Server explicitly requests retry (overrides status) |
| **x-should-retry: "false"** | - | Varies | **NO** | Server explicitly forbids retry |
| `category == :user` | User | YES | NO | Invalid input, fix required |
| `status 4xx` (except 408, 429) | User | YES | NO | Client error, no retry |
| `status 408` | Unknown | NO | YES | Timeout, transient |
| `status 429` | - | NO | YES | Rate limit (use Retry-After) |
| `status 5xx` | Server | NO | YES | Server error, retry |
| `category == :server` | Server | NO | YES | Server-side failure |
| `category == :unknown` | Unknown | NO | YES | Err on side of retrying |
| Connection errors | Unknown | NO | YES | Network issues |
| Transport errors | Unknown | NO | YES | TCP/TLS failures |

**Priority:**
1. x-should-retry header (if present) - overrides all other logic
2. Error category (User/Server/Unknown)
3. HTTP status code
4. Error type (connection, timeout, etc.)

**Implementation:**

```elixir
defmodule Tinkex.Retry do
  @doc """
  Unified retry logic integrating x-should-retry header.

  Priority:
  1. x-should-retry header (server-controlled)
  2. Error category
  3. HTTP status
  4. Error type
  """
  def should_retry?(response_or_error, headers \\ []) do
    # Priority 1: Honor x-should-retry header if present
    case List.keyfind(headers, "x-should-retry", 0) do
      {_, "true"} -> true
      {_, "false"} -> false
      nil ->
        # Priority 2-4: Use standard retry logic
        retryable?(response_or_error)
    end
  end

  # Standard retry logic (when x-should-retry not present)
  def retryable?(%Tinkex.Error{type: :api_connection}), do: true
  def retryable?(%Tinkex.Error{type: :api_timeout}), do: true

  # 5xx, 408, 429 retryable
  def retryable?(%Tinkex.Error{type: :api_status, status: status})
      when status >= 500 or status in [408, 429], do: true

  # Server and Unknown categories retryable
  def retryable?(%Tinkex.Error{type: :request_failed, data: %{category: category}})
      when category in [:server, :unknown], do: true

  # User category NOT retryable
  def retryable?(%Tinkex.Error{type: :request_failed, data: %{category: :user}}), do: false

  # 4xx (except 408, 429) NOT retryable
  def retryable?(%Tinkex.Error{type: :api_status, status: status})
      when status in 400..499, do: false

  def retryable?(_), do: false
end
```

## Retry Strategies

### Base Client Retry

Built into HTTP layer:

```python
async def _retry_request(
    self,
    options: FinalRequestOptions,
    fn: Callable[[], Awaitable[ResponseT]],
) -> ResponseT:
    max_retries = options.get("max_retries", DEFAULT_MAX_RETRIES)

    for attempt in range(max_retries + 1):
        try:
            return await fn()

        except (APIConnectionError, APITimeoutError):
            if attempt >= max_retries:
                raise

            delay = calculate_backoff(attempt)
            await asyncio.sleep(delay)

        except APIStatusError as e:
            # Only retry server errors and timeouts
            if not is_retryable_status(e.status_code):
                raise

            if attempt >= max_retries:
                raise

            delay = calculate_backoff(attempt)
            await asyncio.sleep(delay)

def is_retryable_status(status_code: int) -> bool:
    return status_code >= 500 or status_code == 408
```

### Future Polling Retry

More aggressive retries for promise retrieval:

```python
async def _result_async(self, timeout: float | None = None) -> T:
    """Poll server for result, retry on transient errors"""
    iteration = 0

    while True:
        iteration += 1

        try:
            response = await client.futures.retrieve(request_id=self.request_id)

            if response.status == "completed":
                return parse_result(response.result)

            elif response.status == "failed":
                error = response.error
                if error.category == "transient":
                    # Retry transient errors
                    await asyncio.sleep(1)
                    continue
                else:
                    # Raise user/fatal errors
                    raise RequestFailedError(error.message, ...)

            elif response.status == "pending":
                # Still processing, wait and retry
                delay = min(1.0 * (2 ** (iteration // 10)), 30.0)
                await asyncio.sleep(delay)
                continue

        except APIStatusError as e:
            if e.status_code == 408:
                # Timeout, retry immediately
                continue

            if e.status_code >= 500:
                # Server error, retry with backoff
                await asyncio.sleep(calculate_backoff(iteration))
                continue

            # Other status codes, raise
            raise

        except APIConnectionError:
            # Connection error, retry with backoff
            connection_error_retries += 1
            if connection_error_retries > 5:
                raise
            await asyncio.sleep(calculate_backoff(iteration))
            continue
```

### Sampling Retry with Configuration

SamplingClient supports custom retry configuration:

```python
@dataclass
class RetryConfig:
    """Configuration for retry behavior"""
    max_retries: int = 3
    initial_delay: float = 1.0
    max_delay: float = 60.0
    exponential_base: float = 2.0
    jitter: bool = True

class RetryHandler:
    def __init__(self, config: RetryConfig, name: str, telemetry: Telemetry | None):
        self.config = config
        self.name = name
        self.telemetry = telemetry

    async def execute(self, fn: Callable[[], Awaitable[T]]) -> T:
        """Execute function with retry logic"""
        last_exception = None

        for attempt in range(self.config.max_retries + 1):
            try:
                return await fn()

            except Exception as e:
                last_exception = e

                if not self.is_retryable(e):
                    raise

                if attempt >= self.config.max_retries:
                    raise

                delay = self.calculate_delay(attempt)

                if self.telemetry:
                    self.telemetry.log(
                        f"retry.{self.name}",
                        event_data={
                            "attempt": attempt,
                            "delay": delay,
                            "exception": str(e),
                        }
                    )

                await asyncio.sleep(delay)

        raise last_exception

    def is_retryable(self, error: Exception) -> bool:
        """Determine if error is retryable"""
        if isinstance(error, APIStatusError):
            # Retry 5xx, 408 (timeout), and 429 (rate limit)
            return error.status_code >= 500 or error.status_code in (408, 429)

        if isinstance(error, (APIConnectionError, APITimeoutError)):
            return True

        if isinstance(error, RequestFailedError):
            # Retry Server and Unknown categories, NOT User
            return error.error_category in (
                RequestErrorCategory.Server,
                RequestErrorCategory.Unknown
            )

        return False

    def calculate_delay(self, attempt: int) -> float:
        """Calculate retry delay with exponential backoff and jitter"""
        delay = self.config.initial_delay * (
            self.config.exponential_base ** attempt
        )

        delay = min(delay, self.config.max_delay)

        if self.config.jitter:
            delay *= (0.5 + random.random() * 0.5)

        return delay
```

## Elixir Error Handling Strategy

### 1. Error Types

Use tagged tuples and custom exceptions:

```elixir
defmodule Tinkex.Error do
  @moduledoc "Base error type for Tinkex SDK"

  defexception [:message, :type, :status, :data, :exception]

  @type t :: %__MODULE__{
    message: String.t(),
    type: error_type(),
    status: integer() | nil,
    data: map() | nil,
    exception: Exception.t() | nil
  }

  @type error_type ::
    :api_connection
    | :api_timeout
    | :api_status
    | :request_failed
    | :validation

  def api_connection(message, exception \\ nil) do
    %__MODULE__{
      message: message,
      type: :api_connection,
      exception: exception
    }
  end

  def api_status(status, message, data \\ nil) do
    %__MODULE__{
      message: message,
      type: :api_status,
      status: status,
      data: data
    }
  end

  def request_failed(message, request_id, category, details \\ nil) do
    %__MODULE__{
      message: message,
      type: :request_failed,
      data: %{
        request_id: request_id,
        category: category,
        details: details
      }
    }
  end
end
```

### 2. Result Tuples

Use standard `{:ok, result} | {:error, reason}` pattern:

```elixir
# Success
{:ok, %Tinkex.Types.SampleResponse{}}

# User error (don't retry)
{:error, %Tinkex.Error{
  type: :request_failed,
  data: %{category: :user}
}}

# Transient error (can retry)
{:error, %Tinkex.Error{
  type: :api_status,
  status: 503
}}
```

### 3. Retry Logic

```elixir
defmodule Tinkex.Retry do
  @moduledoc "Retry logic with exponential backoff"

  @type retry_config :: %{
    max_retries: non_neg_integer(),
    initial_delay: non_neg_integer(),
    max_delay: non_neg_integer(),
    exponential_base: float(),
    jitter: boolean()
  }

  @default_config %{
    max_retries: 3,
    initial_delay: 1000,
    max_delay: 60_000,
    exponential_base: 2.0,
    jitter: true
  }

  @doc """
  Execute function with retry logic.

  Returns {:ok, result} or {:error, last_error} after all retries exhausted.
  """
  @spec with_retry((() -> {:ok, any()} | {:error, any()}), retry_config() | nil) ::
    {:ok, any()} | {:error, any()}
  def with_retry(fun, config \\ nil) do
    config = Map.merge(@default_config, config || %{})
    do_retry(fun, config, 0, nil)
  end

  defp do_retry(fun, config, attempt, _last_error) when attempt > config.max_retries do
    fun.()
  end

  defp do_retry(fun, config, attempt, _last_error) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, error} = result ->
        if retryable?(error) and attempt < config.max_retries do
          delay = calculate_delay(config, attempt)

          :telemetry.execute(
            [:tinkex, :retry],
            %{attempt: attempt, delay: delay},
            %{error: error}
          )

          Process.sleep(delay)
          do_retry(fun, config, attempt + 1, error)
        else
          result
        end
    end
  end

  @doc """
  Determine if error is retryable.

  Matches Python SDK's is_retryable logic.
  """
  def retryable?(%Tinkex.Error{type: :api_connection}), do: true
  def retryable?(%Tinkex.Error{type: :api_timeout}), do: true

  # Retry 5xx, 408 (timeout), and 429 (rate limit)
  def retryable?(%Tinkex.Error{type: :api_status, status: status})
      when status >= 500 or status in [408, 429], do: true

  # Retry Server and Unknown categories, NOT User
  def retryable?(%Tinkex.Error{type: :request_failed, data: %{category: category}})
      when category in [:server, :unknown], do: true

  def retryable?(_), do: false

  defp calculate_delay(config, attempt) do
    delay = config.initial_delay * :math.pow(config.exponential_base, attempt)
    delay = min(delay, config.max_delay)

    if config.jitter do
      jitter = :rand.uniform() * 0.5 + 0.5
      round(delay * jitter)
    else
      round(delay)
    end
  end
end
```

### 4. Usage Examples

```elixir
# Simple retry
result = Tinkex.Retry.with_retry(fn ->
  Tinkex.API.Training.forward_backward(request, pool)
end)

# Custom retry config
config = %{
  max_retries: 5,
  initial_delay: 500,
  max_delay: 30_000
}

result = Tinkex.Retry.with_retry(fn ->
  Tinkex.API.Sampling.asample(request, pool)
end, config)

# Pattern matching on results
case Tinkex.Retry.with_retry(fn -> do_request() end) do
  {:ok, response} ->
    # Success
    process_response(response)

  {:error, %Tinkex.Error{type: :request_failed, data: %{category: :user}}} = error ->
    # User error, don't retry
    Logger.error("User error: #{inspect(error)}")
    {:error, error}

  {:error, error} ->
    # Other error
    Logger.error("Request failed: #{inspect(error)}")
    {:error, error}
end
```

### 5. Future Polling with Retries

```elixir
defmodule Tinkex.Future do
  defp poll_loop(request_id, pool, timeout, start_time, iteration) do
    case Tinkex.API.Futures.retrieve(%{request_id: request_id}, pool) do
      {:ok, %{"status" => "completed", "result" => result}} ->
        {:ok, result}

      {:ok, %{"status" => "failed", "error" => error}} ->
        # Parse category from JSON (case-insensitive: handles "Unknown"/"unknown")
        category = Tinkex.Types.RequestErrorCategory.parse(error["category"])

        case category do
          cat when cat in [:server, :unknown] ->
            # Retry server and unknown errors
            Process.sleep(1000)
            poll_loop(request_id, pool, timeout, start_time, iteration + 1)

          :user ->
            # User errors are NOT retryable
            {:error, Tinkex.Error.request_failed(
              error["message"],
              request_id,
              category,
              error["details"]
            )}
        end

      {:ok, %{"status" => "pending"}} ->
        # Still processing
        delay = calculate_polling_delay(iteration)
        Process.sleep(delay)
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      {:error, %{status: 408}} ->
        # Timeout, retry immediately
        poll_loop(request_id, pool, timeout, start_time, iteration)

      {:error, %{status: status}} when status >= 500 ->
        # Server error, retry with backoff
        delay = calculate_backoff(iteration)
        Process.sleep(delay)
        poll_loop(request_id, pool, timeout, start_time, iteration + 1)

      {:error, _} = error ->
        # Non-retryable error
        error
    end
  end

  defp calculate_polling_delay(iteration) do
    # Slower backoff for polling: 1s, 2s, 4s, ... max 30s
    min(1000 * :math.pow(2, div(iteration, 10)), 30_000)
    |> round()
  end
end
```

## Error Handling Best Practices

### 1. Let It Crash (OTP Philosophy)

Don't try to recover from unrecoverable errors:

```elixir
# Bad: swallow all errors
try do
  dangerous_operation()
rescue
  _ -> :ok
end

# Good: let supervisor restart
dangerous_operation()
```

### 2. Use Supervisors

```elixir
defmodule Tinkex.ClientSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
  end
end
```

### 3. Circuit Breaker Pattern

For repeated failures:

```elixir
defmodule Tinkex.CircuitBreaker do
  use GenServer

  # After 5 failures in 60s, open circuit for 30s

  def call(name, fun) do
    case GenServer.call(name, :check_state) do
      :closed -> execute_and_record(name, fun)
      :open -> {:error, :circuit_open}
      :half_open -> try_recovery(name, fun)
    end
  end
end
```

## Next Steps

See `06_telemetry.md` for observability and metrics.
