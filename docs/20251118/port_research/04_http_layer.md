# HTTP Layer and Connection Pooling

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202, 300-302. See `303_claude_sonnet_response_to_critiques.md` for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- **Finch pools**: Changed from single pool to multiple separated pools (training, sampling, session, futures)
- **Resource isolation**: Prevents sampling requests from starving critical session heartbeats

**Key Corrections (Round 2 - Critiques 200-202):**
- **Pool key normalization**: Fixed URL normalization bug (port handling)
- **Telemetry pool**: Added dedicated pool for telemetry requests
- **Retry-After headers**: Added support for server backoff signals

**Key Corrections (Round 3 - Critiques 300-302):**
- **429 retry support**: Added 429 to retryable conditions with server-provided backoff
- **Retry-After HTTP Date**: Added support for HTTP Date format parsing (not just integers)
- **Pool key module**: Extracted normalization to `Tinkex.PoolKey` module (single source of truth)
- **Config parameter**: Added config parameter to API functions (remove global Application.get_env)

## Python Implementation

### HTTP Client: httpx

The Tinker SDK uses `httpx` for HTTP/2 support with connection pooling.

```python
# Dependencies
httpx[http2]>=0.23.0, <1
```

### Connection Pool Architecture

The SDK maintains **separate connection pools** for different operation types:

```python
class ClientConnectionPoolType(Enum):
    TRAIN = "train"           # Forward/backward, optim_step
    SAMPLE = "sample"         # Text generation
    SESSION = "session"       # Session management, heartbeat
    RETRIEVE_PROMISE = "retrieve_promise"  # Future polling
```

**Why separate pools?**
1. **Training operations**: Sequential, one request at a time
2. **Sampling operations**: Highly concurrent (up to 400 parallel requests)
3. **Session operations**: Low volume, keep-alive
4. **Promise retrieval**: High volume polling

### Connection Pool Implementation

```python
class ClientConnectionPool:
    """Manages a pool of AsyncTinker (httpx) clients"""

    def __init__(self, loop, max_requests_per_client, constructor_kwargs):
        self._loop = loop
        self._max_requests_per_client = max_requests_per_client
        self._constructor_kwargs = constructor_kwargs
        self._clients: list[AsyncTinker] = []
        self._client_active_refcount: list[int] = []

    @contextmanager
    def aclient(self) -> AsyncTinker:
        """Get a client from the pool, creating if needed"""

        # Find client with capacity
        client_idx = -1
        for i, ref_count in enumerate(self._client_active_refcount):
            if ref_count < self._max_requests_per_client:
                client_idx = i
                break

        # Create new client if all are busy
        if client_idx == -1:
            self._clients.append(AsyncTinker(**self._constructor_kwargs))
            client_idx = len(self._clients) - 1
            self._client_active_refcount.append(0)

        # Increment refcount
        self._client_active_refcount[client_idx] += 1
        try:
            yield self._clients[client_idx]
        finally:
            # Decrement refcount
            self._client_active_refcount[client_idx] -= 1
```

**Key parameters per pool type:**

| Pool Type | Max Requests/Client | Reason |
|-----------|---------------------|--------|
| TRAIN | 1 | HTTP/2 pipelining issues with long-running requests |
| SAMPLE | 50 | High concurrency for sampling |
| SESSION | 50 | Low volume, defaults fine |
| RETRIEVE_PROMISE | 50 | Polling can be concurrent |

### Base Client Configuration

```python
class AsyncTinker(AsyncAPIClient):
    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | httpx.URL | None = None,
        timeout: Union[float, Timeout, None, NotGiven] = NOT_GIVEN,
        max_retries: int = DEFAULT_MAX_RETRIES,
        default_headers: Mapping[str, str] | None = None,
        http_client: httpx.AsyncClient | None = None,
        _strict_response_validation: bool = False,
    ):
        # API key from env or parameter
        if api_key is None:
            api_key = os.environ.get("TINKER_API_KEY")

        # Base URL
        if base_url is None:
            base_url = os.environ.get("TINKER_BASE_URL")
        if base_url is None:
            base_url = "https://tinker.thinkingmachines.dev/services/tinker-prod"

        super().__init__(...)

    @property
    def auth_headers(self) -> dict[str, str]:
        return {"X-API-Key": self.api_key}
```

### Request/Response Flow

```python
# In AsyncTinker base client
async def _post(
    self,
    path: str,
    *,
    body: Body | None = None,
    options: FinalRequestOptions,
    cast_to: Type[ResponseT],
) -> ResponseT:
    # Build request
    request = self._build_request(
        method="post",
        url=path,
        json_data=body,
        headers=options.headers,
        timeout=options.timeout,
    )

    # Send via httpx
    response = await self._client.send(request)

    # Handle status codes
    if response.status_code >= 400:
        raise self._make_status_error(response)

    # Parse and validate response
    return self._process_response(
        response=response,
        cast_to=cast_to,
        options=options,
    )
```

### Retry Logic

Built into the base client:

```python
# Constants
DEFAULT_MAX_RETRIES = 2
INITIAL_RETRY_DELAY = 0.5  # seconds
MAX_RETRY_DELAY = 8.0      # seconds

async def _retry_request(
    self,
    options: FinalRequestOptions,
    fn: Callable[[], Awaitable[ResponseT]],
) -> ResponseT:
    max_retries = options.get("max_retries", DEFAULT_MAX_RETRIES)

    for attempt in range(max_retries + 1):
        try:
            return await fn()

        except APIConnectionError as e:
            if attempt >= max_retries:
                raise

            # Exponential backoff with jitter
            delay = min(
                INITIAL_RETRY_DELAY * (2 ** attempt) * (0.5 + random()),
                MAX_RETRY_DELAY
            )
            await asyncio.sleep(delay)

        except APIStatusError as e:
            # Only retry 5xx errors and 408
            if e.status_code < 500 and e.status_code != 408:
                raise

            if attempt >= max_retries:
                raise

            delay = min(
                INITIAL_RETRY_DELAY * (2 ** attempt),
                MAX_RETRY_DELAY
            )
            await asyncio.sleep(delay)
```

## Elixir Port Strategy

### HTTP Client: Finch

Finch is the recommended HTTP/2 client for Elixir:

```elixir
# mix.exs
{:finch, "~> 0.16"}
{:jason, "~> 1.4"}  # JSON encoding/decoding
```

### Application Setup ⚠️ CORRECTED - Separate Pools

**CRITICAL:** Use separate Finch pools per operation type for resource isolation.

**Why separate pools?**
- Prevents sampling burst traffic from starving session heartbeats
- Different concurrency needs (training: 1-5, sampling: 100+, session: 5)
- Matches Python SDK's intentional separation

```elixir
defmodule Tinkex.Application do
  use Application

  def start(_type, _args) do
    # Get base URL for pool configuration
    base_url = Application.get_env(:tinkex, :base_url,
      "https://tinker.thinkingmachines.dev/services/tinker-prod")

    # Normalize base URL for pool keys (critical for pool lookup)
    normalized_base = normalize_base_url(base_url)

    children = [
      # HTTP connection pools - SEPARATE per operation type
      {Finch,
       name: Tinkex.HTTP.Pool,
       pools: %{
         # Default pool (for misc operations)
         default: [
           protocol: :http2,
           size: 10,
           max_idle_time: 60_000
         ],
         # Training operations pool (sequential, long-running)
         {normalized_base, :training} => [
           protocol: :http2,
           size: 5,          # Few connections
           count: 1,         # Single connection for serial requests
           max_idle_time: 60_000
         ],
         # Sampling operations pool (high concurrency bursts)
         {normalized_base, :sampling} => [
           protocol: :http2,
           size: 100,        # Many connections for 400 concurrent requests
           max_idle_time: 30_000
         ],
         # Session management pool (critical heartbeats)
         {normalized_base, :session} => [
           protocol: :http2,
           size: 5,          # Dedicated for heartbeats
           max_idle_time: :infinity  # Keep alive
         ],
         # Future polling pool (concurrent polling)
         {normalized_base, :futures} => [
           protocol: :http2,
           size: 50,         # Moderate concurrency
           max_idle_time: 60_000
         ],
         # Telemetry pool (prevents telemetry from starving other ops)
         {normalized_base, :telemetry} => [
           protocol: :http2,
           size: 5,
           max_idle_time: 60_000
         ]
       }}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  # ⚠️ CRITICAL: Normalize base URL to prevent pool lookup failures
  defp normalize_base_url(url) do
    uri = URI.parse(url)

    # Only include port if non-standard (not 80/443/nil)
    port = case {uri.scheme, uri.port} do
      {"http", 80} -> ""
      {"https", 443} -> ""
      {_, nil} -> ""
      {_, port} -> ":#{port}"
    end

    "#{uri.scheme}://#{uri.host}#{port}"
  end
end
```

### API Module Structure

```elixir
defmodule Tinkex.API do
  @moduledoc "Low-level HTTP API client"

  @base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"

  defmodule Training do
    @moduledoc "Training API endpoints"

    def forward_backward(request, pool_name \\ Tinkex.HTTP.Pool, opts \\ []) do
      Tinkex.API.post(
        "/api/v1/forward_backward",
        request,
        pool_name,
        Keyword.put(opts, :pool_type, :training)  # Use training pool
      )
    end

    def optim_step(request, pool_name \\ Tinkex.HTTP.Pool, opts \\ []) do
      Tinkex.API.post(
        "/api/v1/optim_step",
        request,
        pool_name,
        Keyword.put(opts, :pool_type, :training)  # Use training pool
      )
    end
  end

  defmodule Sampling do
    @moduledoc "Sampling API endpoints"

    def asample(request, pool_name \\ Tinkex.HTTP.Pool, opts \\ []) do
      Tinkex.API.post(
        "/api/v1/asample",
        request,
        pool_name,
        opts
        |> Keyword.put(:pool_type, :sampling)  # Use sampling pool
        |> Keyword.put(:max_retries, 0)
      )
    end
  end

  defmodule Futures do
    @moduledoc "Future/promise retrieval"

    def retrieve(request, pool_name \\ Tinkex.HTTP.Pool, opts \\ []) do
      Tinkex.API.post(
        "/api/v1/future/retrieve",
        request,
        pool_name,
        Keyword.put(opts, :pool_type, :futures)  # Use futures pool
      )
    end
  end

  ## Generic HTTP operations

  def post(path, body, pool_name, opts \\ []) do
    url = build_url(path)
    headers = build_headers(opts)
    timeout = Keyword.get(opts, :timeout, 120_000)
    max_retries = Keyword.get(opts, :max_retries, 2)
    pool_type = Keyword.get(opts, :pool_type, :default)

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    with_retries(fn ->
      # Specify pool type for resource isolation
      Finch.request(request, pool_name,
        receive_timeout: timeout,
        pool: build_pool_key(url, pool_type)
      )
    end, max_retries)
    |> handle_response()
  end

  defp build_pool_key(_url, :default), do: :default
  defp build_pool_key(url, pool_type) do
    # Normalize base URL (MUST match pool config normalization)
    normalized_base = normalize_base_url(url)
    {normalized_base, pool_type}
  end

  # ⚠️ CRITICAL: Same normalization as Application.start
  defp normalize_base_url(url) do
    uri = URI.parse(url)

    port = case {uri.scheme, uri.port} do
      {"http", 80} -> ""
      {"https", 443} -> ""
      {_, nil} -> ""
      {_, port} -> ":#{port}"
    end

    "#{uri.scheme}://#{uri.host}#{port}"
  end

  defp build_url(path) do
    base = Application.get_env(:tinkex, :base_url, @base_url)
    URI.merge(base, path) |> to_string()
  end

  defp build_headers(opts) do
    api_key = Application.get_env(:tinkex, :api_key) ||
              System.get_env("TINKER_API_KEY")

    base_headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status >= 200 and status < 300 do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  # Special handling for 429 (rate limit) - parse Retry-After headers
  defp handle_response({:ok, %Finch.Response{status: 429, headers: headers, body: body}}) do
    error = case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end

    retry_after_ms = parse_retry_after(headers)

    {:error, %Tinkex.Error{
      status: 429,
      message: error["message"] || "Rate limited",
      data: error,
      retry_after_ms: retry_after_ms
    }}
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}) do
    error = case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end

    {:error, %Tinkex.Error{status: status, message: error["message"], data: error}}
  end

  defp handle_response({:error, exception}) do
    {:error, %Tinkex.Error{message: Exception.message(exception), exception: exception}}
  end

  ## Retry logic

  defp with_retries(fun, max_retries, attempt \\ 0) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, %{status: status}} = error when status >= 500 or status == 408 ->
        if attempt < max_retries do
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          error
        end

      {:error, %Mint.TransportError{}} = error ->
        if attempt < max_retries do
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          error
        end

      error ->
        error
    end
  end

  defp retry_delay(attempt) do
    # Exponential backoff: 500ms, 1s, 2s, 4s, max 8s
    base = 500
    max = 8000

    delay = base * :math.pow(2, attempt)
    jitter = :rand.uniform() * 0.5 + 0.5  # 0.5 to 1.0

    min(delay * jitter, max)
    |> round()
  end

  # ⚠️ NEW: Parse Retry-After headers from server
  defp parse_retry_after(headers) do
    # Try retry-after-ms first (milliseconds)
    case List.keyfind(headers, "retry-after-ms", 0) do
      {_, ms_str} ->
        String.to_integer(ms_str)

      nil ->
        # Fall back to retry-after (seconds)
        case List.keyfind(headers, "retry-after", 0) do
          {_, seconds_str} -> String.to_integer(seconds_str) * 1000
          nil -> 1000  # Default 1 second
        end
    end
  end
end
```

### Connection Pool Strategy ⚠️ CORRECTED

**IMPORTANT:** Elixir DOES need separate pool instances, just like Python!

**Why separate pools are critical:**
1. **Resource isolation**: Prevents sampling bursts from starving session heartbeats
2. **Different concurrency profiles**: Training (1-5), Sampling (100+), Session (5)
3. **Failure isolation**: Issues in one pool don't affect others
4. **Matches Python intent**: The Python SDK separates pools deliberately, not accidentally

**Python approach:**
```python
# Separate pool per operation type
pool_train = ClientConnectionPool(max_per_client=1)
pool_sample = ClientConnectionPool(max_per_client=50)
pool_session = ClientConnectionPool(max_per_client=50)
pool_futures = ClientConnectionPool(max_per_client=50)
```

**Elixir approach (CORRECTED):**
```elixir
# Multiple pools in Finch, keyed by {base_url, pool_type}
{Finch, name: Tinkex.HTTP.Pool, pools: %{
  default: [protocol: :http2, size: 10],
  {base_url, :training} => [size: 5, count: 1],
  {base_url, :sampling} => [size: 100],
  {base_url, :session} => [size: 5, max_idle_time: :infinity],
  {base_url, :futures} => [size: 50]
}}

# Usage: Specify pool via :pool option in Finch.request
Finch.request(req, Tinkex.HTTP.Pool, pool: {base_url, :sampling})
```

**Why this matters:**
If 1000 sampling requests saturate a shared pool, session heartbeats can't get connections → session dies → all clients fail. Separate pools prevent cascading failures.

### Request Tracing

Add telemetry for observability:

```elixir
defmodule Tinkex.API do
  def post(path, body, pool, opts) do
    metadata = %{
      path: path,
      method: :post,
      timestamp: System.monotonic_time()
    }

    :telemetry.span(
      [:tinkex, :http, :request],
      metadata,
      fn ->
        result = do_post(path, body, pool, opts)
        {result, metadata}
      end
    )
  end

  defp do_post(path, body, pool, opts) do
    # ... actual HTTP request ...
  end
end
```

### Streaming Support

For future streaming responses:

```elixir
defmodule Tinkex.API.Stream do
  @doc "Stream server-sent events"
  def stream(path, body, pool, opts \\ []) do
    url = Tinkex.API.build_url(path)
    headers = Tinkex.API.build_headers(opts)

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    Finch.stream(request, pool, nil, fn
      {:status, status}, acc ->
        {:cont, Map.put(acc, :status, status)}

      {:headers, headers}, acc ->
        {:cont, Map.put(acc, :headers, headers)}

      {:data, data}, acc ->
        # Parse SSE data
        events = parse_sse(data)
        {:cont, Map.update(acc, :events, events, &(&1 ++ events))}
    end)
  end

  defp parse_sse(data) do
    # Parse server-sent event format
    # data: {...}\n\n
    ...
  end
end
```

## Configuration

```elixir
# config/config.exs
config :tinkex,
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod",
  api_key: nil,  # Read from env
  timeout: 120_000,
  max_retries: 2

# config/runtime.exs
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY")
```

## Comparison Summary

| Feature | Python (httpx) | Elixir (Finch) |
|---------|---------------|----------------|
| **HTTP/2** | ✅ Via httpx[http2] | ✅ Native via Mint |
| **Connection Pooling** | Manual per operation type | Automatic in Finch |
| **Retry Logic** | Built into base client | Custom wrapper |
| **Async** | asyncio | Native processes |
| **Streaming** | AsyncIterator | Finch.stream |
| **Configuration** | Constructor args | Application config |

## Next Steps

See `05_error_handling.md` for exception and error handling patterns.
