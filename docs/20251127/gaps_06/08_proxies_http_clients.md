# Gap Analysis #8: Proxies & Custom HTTP Clients

**Date:** 2025-11-27
**Status:** Critical Gap - High Priority
**Complexity:** Medium-High
**Effort Estimate:** 3-5 days

---

## Executive Summary

The Python SDK (Tinker) exposes HTTP customization via user-supplied `httpx.AsyncClient` instances (proxies, transports, per-client connection limits). The Elixir SDK (Tinkex) currently has **NO proxy support** and **limited HTTP client customization**, wiring every call to a single Finch pool (`Tinkex.HTTP.Pool`) configured at application boot (callers can point to another pool name only if they start it themselves).

This gap prevents users from:
- Using corporate/SOCKS proxies
- Implementing custom authentication schemes at the HTTP layer
- Injecting custom HTTP middleware
- Fine-tuning connection behavior per-client instance
- Testing with mock HTTP adapters

---

## Python SDK Deep Dive

### 1. Proxy Support (`_types.py`)

The Python SDK defines comprehensive proxy types:

```python
# Lines 38-41 in _types.py
ProxiesDict = Dict["str | URL", Union[None, str, URL, Proxy]]
ProxiesTypes = Union[str, Proxy, ProxiesDict]
```

**Capabilities:**
- **String proxy**: `"http://proxy.example.com:8080"`
- **httpx.Proxy object**: Full control with authentication
- **Dictionary mapping**: Different proxies per protocol
  ```python
  {
      "http://": "http://proxy.example.com:8080",
      "https://": "https://secure-proxy.example.com:8443"
  }
  ```
- **None value**: Explicitly disable proxy for specific URLs

**Note:** Tinker does not expose a first-class `proxies` argument on `AsyncTinker`; proxy usage flows through the `http_client` you pass (an `httpx.AsyncClient` configured with `proxies` or a custom transport).

### 2. Custom HTTP Client (`_base_client.py`)

The `AsyncAPIClient` accepts a fully customizable `httpx.AsyncClient`:

```python
# Lines 808-853 in _base_client.py
class AsyncAPIClient(BaseClient[httpx.AsyncClient, AsyncStream[Any]]):
    def __init__(
        self,
        *,
        version: str,
        base_url: str | URL,
        max_retries: int = DEFAULT_MAX_RETRIES,
        timeout: float | Timeout | None | NotGiven = NOT_GIVEN,
        http_client: httpx.AsyncClient | None = None,  # <-- Custom client injection
        custom_headers: Mapping[str, str] | None = None,
        custom_query: Mapping[str, object] | None = None,
        _strict_response_validation: bool = False,
    ) -> None:
        # If no http_client provided, use DefaultAsyncHttpxClient
        self._client = http_client or AsyncHttpxClientWrapper(
            base_url=base_url,
            timeout=cast(Timeout, timeout),
            http2=True,
        )
```

**Key Features:**

#### A. Default Client Configuration
```python
# Lines 748-753 in _base_client.py
class _DefaultAsyncHttpxClient(httpx.AsyncClient):
    def __init__(self, **kwargs: Any) -> None:
        kwargs.setdefault("timeout", DEFAULT_TIMEOUT)
        kwargs.setdefault("limits", DEFAULT_CONNECTION_LIMITS)
        kwargs.setdefault("follow_redirects", True)
        super().__init__(**kwargs)
```

From `_constants.py`:
```python
DEFAULT_TIMEOUT = httpx.Timeout(timeout=60.0, connect=5.0)
DEFAULT_CONNECTION_LIMITS = httpx.Limits(
    max_connections=1000,
    max_keepalive_connections=20
)
```

#### B. Custom Client Examples

**1. Proxy Configuration:**
```python
import httpx
from tinker import AsyncTinker

# Simple proxy
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies="http://proxy.example.com:8080"
    )
)

# Proxy with authentication
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies=httpx.Proxy(
            url="http://proxy.example.com:8080",
            auth=("username", "password")
        )
    )
)

# Different proxies per protocol
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies={
            "http://": "http://proxy1.example.com:8080",
            "https://": "https://proxy2.example.com:8443"
        }
    )
)
```

**2. Custom Transport:**
```python
# Custom transport for advanced use cases
from httpx import AsyncHTTPTransport

transport = AsyncHTTPTransport(
    retries=5,
    verify=False,  # Skip SSL verification (not recommended)
    http2=True,
    local_address="0.0.0.0"
)

client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(transport=transport)
)
```

**3. Custom Timeouts:**
```python
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        timeout=httpx.Timeout(
            connect=10.0,   # Connection timeout
            read=60.0,      # Read timeout
            write=10.0,     # Write timeout
            pool=5.0        # Pool timeout
        )
    )
)
```

**4. Custom Connection Limits:**
```python
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        limits=httpx.Limits(
            max_connections=500,
            max_keepalive_connections=50
        )
    )
)
```

#### C. Timeout Inheritance Logic
```python
# Lines 820-831 in _base_client.py
if not is_given(timeout):
    # If user passed custom http_client with non-default timeout, use it
    if http_client and http_client.timeout != HTTPX_DEFAULT_TIMEOUT:
        timeout = http_client.timeout
    else:
        timeout = DEFAULT_TIMEOUT
```

This means:
1. Explicit `timeout` parameter takes precedence
2. Custom `http_client.timeout` is respected if no explicit timeout
3. Falls back to SDK default (60s)

### 3. Client Wrapper (`_base_client.py`)

```python
# Lines 792-801
class AsyncHttpxClientWrapper(DefaultAsyncHttpxClient):
    """Ensures proper cleanup of httpx client in async context"""
    def __del__(self) -> None:
        if self.is_closed:
            return
        try:
            asyncio.get_running_loop().create_task(self.aclose())
        except Exception:
            pass
```

### 4. Usage in `_client.py`

```python
# Lines 54-103 in _client.py
class AsyncTinker(AsyncAPIClient):
    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | httpx.URL | None = None,
        timeout: Union[float, Timeout, None, NotGiven] = NOT_GIVEN,
        max_retries: int = DEFAULT_MAX_RETRIES,
        default_headers: Mapping[str, str] | None = None,
        default_query: Mapping[str, object] | None = None,
        # Configure a custom httpx client
        http_client: httpx.AsyncClient | None = None,
        _strict_response_validation: bool = False,
    ) -> None:
        super().__init__(
            version=__version__,
            base_url=base_url,
            max_retries=max_retries,
            timeout=timeout,
            http_client=http_client,  # <-- Passed through
            custom_headers=default_headers,
            custom_query=default_query,
            _strict_response_validation=_strict_response_validation,
        )
```

---

## Elixir SDK Deep Dive

### 1. Configuration (`config.ex`)

The Elixir SDK has **NO proxy support** at the config level:

```elixir
# Lines 16-30 in config.ex
defstruct [
  :base_url,
  :api_key,
  :http_pool,        # <-- Only pool selection, NOT customization
  :timeout,
  :max_retries,
  :user_metadata,
  :tags,
  :feature_gates,
  :telemetry_enabled?,
  :log_level,
  :cf_access_client_id,
  :cf_access_client_secret,
  :dump_headers?
]
```

**Key Limitation:** `http_pool` is an atom naming a Finch pool, not a client injection point. Tinkex only boots `Tinkex.HTTP.Pool`; pointing `config.http_pool` at anything else requires callers to start and manage an alternate Finch pool themselves.

### 2. Application-Level Pool Setup (`application.ex`)

Pools are configured at application startup, NOT per-client:

```elixir
# Lines 126-142 in application.ex
defp maybe_add_http_pool(true, _destination, pool_size, pool_count) do
  # Python SDK parity: max_connections=1000, max_keepalive_connections=20
  # Finch pool config: size=connections per pool, count=number of pools
  [
    {Finch,
     name: Tinkex.HTTP.Pool,
     pools: %{
       default: [
         protocols: [:http2, :http1],
         size: pool_size,      # Default: 50
         count: pool_count     # Default: 20
       ]
     }}
  ]
end
```

**Pool Configuration:**
- `pool_size`: Connections per pool (env: `TINKEX_POOL_SIZE`, default: 50)
- `pool_count`: Number of pools (env: `TINKEX_POOL_COUNT`, default: 20)
- Total connections: `pool_size * pool_count = 1000` (matches Python)

**Limitations:**
1. **Single provided pool** - Only `Tinkex.HTTP.Pool` is started; per-tenant pools require callers to start a separate Finch pool and point `config.http_pool` at it.
2. **No runtime pool tuning** - Pool sizing set via env/app config at boot.
3. **No proxy support** - No Config/Env fields and the Finch `:proxy` option is never set
4. **Limited per-client behavior** - `timeout`/`max_retries` are per-config, but connection limits and pool selection are effectively global (pool_type/pool_key are computed but not used to pick a pool).

### 3. HTTP Client Behaviour (`http_client.ex`)

A minimal behaviour exists but is **not used for customization**:

```elixir
# Lines 1-19 in http_client.ex
defmodule Tinkex.HTTPClient do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This indirection lets tests or host applications swap out the HTTP layer.
  The default implementation is `Tinkex.API`.
  """

  alias Tinkex.Error

  @callback post(path :: String.t(), body :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback get(path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback delete(path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}
end
```

**Current Usage:** Only for testing, not for production client injection.

### 4. Finch Request Execution (`api.ex`)

Requests are made directly with Finch:

```elixir
# Lines 52-59 in api/api.ex
request = Finch.build(:post, url, headers, prepare_body(body, transform_opts))
pool_key = PoolKey.build(config.base_url, pool_type)

{result, retry_count, duration} =
  execute_with_telemetry(
    &with_retries/6,
    [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
    metadata
  )
```

`pool_key`/`pool_type` are computed for telemetry but ignored inside `with_retries/6`, so every request goes through the same pool atom.

```elixir
# Line 480 in api/api.ex
case Finch.request(request, context.pool, receive_timeout: context.timeout) do
  {:ok, %Finch.Response{} = response} = response_tuple ->
    handle_success(response_tuple, response, context, attempt)
  # ... error handling
end
```

**Key Points:**
1. `config.http_pool` is just a pool name (atom); pool_key/pool_type are computed but not used to route to different pools
2. No mechanism to inject custom client or middleware
3. Direct Finch.request call - no abstraction layer

### 5. Finch Proxy Support Research

**Finch Documentation:**
Finch itself **does support HTTP proxies** via Mint (the underlying HTTP client):

```elixir
# Example from Finch docs (NOT currently in Tinkex)
Finch.build(
  :get,
  "https://api.example.com",
  [],
  nil,
  [proxy: {:http, "proxy.example.com", 8080, []}]
)
```

**Finch Proxy Options:**
- `{:http, host, port, opts}` - HTTP proxy
- `{:https, host, port, opts}` - HTTPS CONNECT proxy
- `opts` can include:
  - `:username` - Proxy auth username
  - `:password` - Proxy auth password

**Problem:** Tinkex doesn't expose this Finch capability.

---

## Granular Differences

| Feature | Python (Tinker) | Elixir (Tinkex) | Gap Severity |
|---------|-----------------|-----------------|--------------|
| **Proxy Support** | Via `http_client`/httpx proxies (HTTP/HTTPS/SOCKS) | **None** | **Critical** |
| **Proxy Auth** | Username/password (`httpx.Proxy`) | **None** | **Critical** |
| **Custom HTTP Client** | Full injection | **None** (behaviour exists but not injectable) | **High** |
| **Per-Client Pools** | Yes (each `httpx.AsyncClient` owns its pool limits) | Single Finch pool unless caller supplies alternate `http_pool` | **High** |
| **Custom Transport** | Yes (httpx transports, optional aiohttp) | **No** | **Medium** |
| **SSL Verification Control** | Yes (per client) | **No** (global) | **Medium** |
| **Connection Limits** | Per-client `httpx.Limits` | Global Finch sizing (env/app); per-client requires caller-managed pool | **Medium** |
| **Timeout Granularity** | 4 types (connect/read/write/pool) | Single receive timeout (per config) | **Low** |
| **HTTP/2 Control** | Per-client toggle | Global only | **Low** |
| **Client Injection Points** | Constructor parameter | **None** | **High** |
| **Mock Client Testing** | Easy (pass mock client) | Harder (behaviour swap) | **Medium** |

### Detailed Gap Analysis

#### 1. Proxy Configuration Gap

**Python Example:**
```python
# Corporate proxy with auth
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies=httpx.Proxy(
            url="http://corporate-proxy.example.com:8080",
            auth=("corp_user", "corp_pass")
        )
    )
)
```

**Elixir Equivalent:** **NOT POSSIBLE**

**Workaround:** None (would require forking Tinkex or system-wide proxy config)

#### 2. Custom Client Injection Gap

**Python Example:**
```python
# Custom client with specialized behavior
class MyCustomClient(httpx.AsyncClient):
    async def send(self, request):
        # Custom logging, metrics, etc.
        print(f"Sending {request.method} {request.url}")
        return await super().send(request)

client = AsyncTinker(
    api_key="...",
    http_client=MyCustomClient()
)
```

**Elixir Equivalent:** **NOT POSSIBLE**

**Workaround:** Must modify Tinkex.API module directly

#### 3. Per-Client Pool Configuration Gap

**Python Example:**
```python
# High-throughput client
high_throughput = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        limits=httpx.Limits(max_connections=5000)
    )
)

# Low-resource client
low_resource = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        limits=httpx.Limits(max_connections=10)
    )
)
```

**Elixir Equivalent:** Only by running your own Finch pool and passing its name via `config.http_pool`; Tinkex itself starts a single pool with app/env sizing and does not vary pool settings per config/base URL.

#### 4. Testing Gap

**Python Example:**
```python
# Mock client for testing
import httpx
from unittest.mock import AsyncMock

mock_client = AsyncMock(spec=httpx.AsyncClient)
client = AsyncTinker(api_key="test", http_client=mock_client)

# Easy to verify calls
await client.service.get_metadata()
assert mock_client.send.called
```

**Elixir Equivalent:** Must implement `Tinkex.HTTPClient` behaviour
```elixir
# test/support/mock_http_client.ex
defmodule MockHTTPClient do
  @behaviour Tinkex.HTTPClient

  def post(path, body, opts) do
    # Mock implementation
  end

  def get(path, opts) do
    # Mock implementation
  end

  def delete(path, opts) do
    # Mock implementation
  end
end
```

**Problem:** No way to inject mock client at runtime, must modify source.

---

## TDD Implementation Plan

### Phase 1: Add Proxy Support (2-3 days)

#### Step 1: Extend `Tinkex.Config` with Proxy Options

**File:** `lib/tinkex/config.ex`

**Test First:**
```elixir
# test/tinkex/config_proxy_test.exs
defmodule Tinkex.ConfigProxyTest do
  use ExUnit.Case, async: true

  describe "proxy configuration" do
    test "accepts HTTP proxy URL string" do
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: "http://proxy.example.com:8080"
      )

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
    end

    test "accepts proxy tuple with auth" do
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: {:http, "proxy.example.com", 8080,
                username: "user", password: "pass"}
      )

      assert config.proxy == {:http, "proxy.example.com", 8080,
                              username: "user", password: "pass"}
    end

    test "accepts HTTPS CONNECT proxy" do
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: {:https, "secure-proxy.example.com", 8443, []}
      )

      assert match?({:https, "secure-proxy.example.com", 8443, []}, config.proxy)
    end

    test "validates proxy URL format" do
      assert_raise ArgumentError, fn ->
        Tinkex.Config.new(
          api_key: "test",
          proxy: "invalid-url"
        )
      end
    end

    test "supports nil proxy (explicit no proxy)" do
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: nil
      )

      assert is_nil(config.proxy)
    end
  end

  describe "proxy from environment" do
    test "reads HTTP_PROXY environment variable" do
      System.put_env("HTTP_PROXY", "http://env-proxy.example.com:8080")

      config = Tinkex.Config.new(api_key: "test")

      assert config.proxy == {:http, "env-proxy.example.com", 8080, []}

      System.delete_env("HTTP_PROXY")
    end

    test "reads HTTPS_PROXY environment variable" do
      System.put_env("HTTPS_PROXY", "https://secure-proxy.example.com:8443")

      config = Tinkex.Config.new(api_key: "test")

      assert config.proxy == {:https, "secure-proxy.example.com", 8443, []}

      System.delete_env("HTTPS_PROXY")
    end

    test "explicit proxy option overrides environment" do
      System.put_env("HTTP_PROXY", "http://env-proxy.example.com:8080")

      config = Tinkex.Config.new(
        api_key: "test",
        proxy: "http://explicit-proxy.example.com:9090"
      )

      assert config.proxy == {:http, "explicit-proxy.example.com", 9090, []}

      System.delete_env("HTTP_PROXY")
    end
  end
end
```

**Implementation:**
```elixir
# lib/tinkex/config.ex
defmodule Tinkex.Config do
  @enforce_keys [:base_url, :api_key]
  defstruct [
    :base_url,
    :api_key,
    :http_pool,
    :proxy,           # NEW: Proxy configuration
    :timeout,
    # ... rest unchanged
  ]

  @type proxy_opt ::
    String.t() |                                          # "http://proxy:8080"
    {:http, String.t(), pos_integer(), keyword()} |      # HTTP proxy
    {:https, String.t(), pos_integer(), keyword()} |     # HTTPS CONNECT
    nil                                                   # No proxy

  @type t :: %__MODULE__{
    base_url: String.t(),
    api_key: String.t(),
    http_pool: atom(),
    proxy: proxy_opt(),
    # ... rest unchanged
  }

  def new(opts \\ []) do
    # ... existing code ...

    proxy = parse_proxy_option(opts, env)

    %__MODULE__{
      # ... existing fields ...
      proxy: proxy,
    }
    |> validate!()
  end

  defp parse_proxy_option(opts, env) do
    case pick([opts[:proxy], env.http_proxy, env.https_proxy]) do
      nil -> nil
      url when is_binary(url) -> parse_proxy_url(url)
      tuple when is_tuple(tuple) -> validate_proxy_tuple(tuple)
    end
  end

  defp parse_proxy_url(url) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https"] do
      raise ArgumentError, "Proxy URL must use http:// or https:// scheme"
    end

    unless uri.host do
      raise ArgumentError, "Invalid proxy URL: missing host"
    end

    port = uri.port || default_proxy_port(uri.scheme)

    opts = []
    opts = if uri.userinfo, do: add_proxy_auth(opts, uri.userinfo), else: opts

    {String.to_atom(uri.scheme), uri.host, port, opts}
  end

  defp default_proxy_port("http"), do: 8080
  defp default_proxy_port("https"), do: 8443

  defp add_proxy_auth(opts, userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] ->
        Keyword.merge(opts, username: username, password: password)
      [username] ->
        Keyword.put(opts, :username, username)
    end
  end

  defp validate_proxy_tuple({type, host, port, opts})
      when type in [:http, :https] and is_binary(host) and is_integer(port)
      and is_list(opts) do
    {type, host, port, opts}
  end

  defp validate_proxy_tuple(invalid) do
    raise ArgumentError, """
    Invalid proxy tuple: #{inspect(invalid)}
    Expected: {:http | :https, host, port, opts}
    """
  end

  def validate!(%__MODULE__{} = config) do
    # ... existing validations ...

    if config.proxy do
      validate_proxy!(config.proxy)
    end

    config
  end

  defp validate_proxy!({type, _host, port, _opts}) when type in [:http, :https] do
    unless is_integer(port) and port > 0 and port <= 65535 do
      raise ArgumentError, "Proxy port must be 1-65535, got: #{inspect(port)}"
    end
    :ok
  end

  defp validate_proxy!(nil), do: :ok
end
```

**Update Env Module:**
```elixir
# lib/tinkex/env.ex
defmodule Tinkex.Env do
  def snapshot(env \\ :system) do
    %{
      # ... existing fields ...
      http_proxy: http_proxy(env),
      https_proxy: https_proxy(env)
    }
  end

  def http_proxy(env \\ :system), do: env |> fetch("HTTP_PROXY") |> normalize()
  def https_proxy(env \\ :system), do: env |> fetch("HTTPS_PROXY") |> normalize()
end
```
Stick to `Tinkex.Env` helpers (no direct `System.get_env/1`) so redaction and normalization stay centralized.

#### Step 2: Modify Finch Request Building to Include Proxy

**Test First:**
```elixir
# test/tinkex/api/api_proxy_test.exs
defmodule Tinkex.API.ProxyTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "proxy support" do
    test "sends request through HTTP proxy" do
      # This requires mocking Finch.request to inspect the request
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: "http://proxy.example.com:8080"
      )

      # Use Bypass to create a proxy server
      bypass = Bypass.open(port: 8080)

      Bypass.expect_once(bypass, "CONNECT", "/", fn conn ->
        # Verify proxy was used
        Plug.Conn.resp(conn, 200, "")
      end)

      # Make request
      {:ok, _} = Tinkex.API.get("/test", config: config)
    end

    test "includes proxy authentication headers" do
      config = Tinkex.Config.new(
        api_key: "test",
        proxy: {:http, "proxy.example.com", 8080,
                username: "user", password: "pass"}
      )

      # Implementation will add Proxy-Authorization header
      # Test via mocking or integration test
    end
  end
end
```

**Implementation:**
```elixir
# lib/tinkex/api/api.ex
defmodule Tinkex.API do
  # ... existing code ...

  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    headers = build_headers(:post, config, opts, timeout)

    # Build request with proxy
    request = build_request(
      :post,
      url,
      headers,
      prepare_body(body, transform_opts),
      config.proxy  # NEW: Pass proxy
    )

    # ... rest unchanged
  end

  # NEW: Build request with optional proxy
  defp build_request(method, url, headers, body \\ nil, proxy \\ nil) do
    base_request = Finch.build(method, url, headers, body)

    case proxy do
      nil ->
        base_request

      {proxy_type, host, port, opts} ->
        # Finch.build accepts proxy as 5th argument
        Finch.build(
          method,
          url,
          headers,
          body,
          [proxy: {proxy_type, String.to_charlist(host), port, finch_proxy_opts(opts)}]
        )
    end
  end

  defp finch_proxy_opts(opts) do
    opts
    |> Keyword.take([:username, :password])
    |> Enum.map(fn {k, v} -> {k, String.to_charlist(v)} end)
  end
end
```

#### Step 3: Integration Tests

```elixir
# test/integration/proxy_test.exs
defmodule Tinkex.ProxyIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :proxy

  setup do
    # Start a simple HTTP proxy for testing
    {:ok, proxy_pid} = TestProxy.start_link(port: 9999)

    on_exit(fn ->
      TestProxy.stop(proxy_pid)
    end)

    {:ok, proxy: proxy_pid}
  end

  test "makes requests through proxy", %{proxy: proxy} do
    config = Tinkex.Config.new(
      api_key: System.fetch_env!("TINKER_API_KEY"),
      proxy: "http://localhost:9999"
    )

    # Make a real request
    {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, _metadata} = Tinkex.ServiceClient.get_metadata(service_pid)

    # Verify proxy was used
    assert TestProxy.request_count(proxy) > 0
  end

  test "proxy authentication works", %{proxy: proxy} do
    TestProxy.require_auth(proxy, "user", "pass")

    config = Tinkex.Config.new(
      api_key: System.fetch_env!("TINKER_API_KEY"),
      proxy: {:http, "localhost", 9999,
              username: "user", password: "pass"}
    )

    {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, _metadata} = Tinkex.ServiceClient.get_metadata(service_pid)

    assert TestProxy.auth_success?(proxy)
  end
end
```

### Phase 2: Add HTTP Client Behaviour Injection (1-2 days)

#### Step 1: Define Enhanced HTTPClient Behaviour

**Test First:**
```elixir
# test/tinkex/http_client_injection_test.exs
defmodule Tinkex.HTTPClientInjectionTest do
  use ExUnit.Case, async: true

  defmodule MockHTTPClient do
    @behaviour Tinkex.HTTPClient

    def init(config), do: {:ok, %{config: config, calls: []}}

    def request(method, path, headers, body, state) do
      new_state = Map.update!(state, :calls, &[{method, path} | &1])
      {:ok, %{status: 200, headers: [], body: "{}"}, new_state}
    end

    def get_calls(state), do: Enum.reverse(state.calls)
  end

  test "allows injecting custom HTTP client" do
    config = Tinkex.Config.new(
      api_key: "test",
      http_client: MockHTTPClient
    )

    {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, _} = Tinkex.ServiceClient.get_metadata(service_pid)

    # Verify mock was called
    calls = Tinkex.ServiceClient.get_http_calls(service_pid)
    assert {:get, "/service/metadata"} in calls
  end
end
```

**Implementation:**
```elixir
# lib/tinkex/http_client.ex
defmodule Tinkex.HTTPClient do
  @moduledoc """
  Behaviour for HTTP client implementations.

  Allows injecting custom HTTP clients for testing, proxying,
  middleware, etc.
  """

  alias Tinkex.Error

  @type state :: any()
  @type headers :: [{String.t(), String.t()}]
  @type body :: iodata() | nil
  @type response :: %{
    status: pos_integer(),
    headers: headers(),
    body: binary()
  }

  @doc """
  Initialize the HTTP client with configuration.

  Returns `{:ok, state}` where state is passed to all requests.
  """
  @callback init(config :: Tinkex.Config.t()) :: {:ok, state()}

  @doc """
  Make an HTTP request.

  Returns `{:ok, response, new_state}` or `{:error, error, new_state}`.
  """
  @callback request(
    method :: :get | :post | :put | :delete | :patch,
    url :: String.t(),
    headers :: headers(),
    body :: body(),
    state :: state()
  ) :: {:ok, response(), state()} | {:error, Error.t(), state()}

  @doc """
  Close the HTTP client and clean up resources.
  """
  @callback close(state :: state()) :: :ok

  @optional_callbacks [close: 1]
end
```

#### Step 2: Default Finch-Based Implementation

```elixir
# lib/tinkex/http_client/finch_client.ex
defmodule Tinkex.HTTPClient.FinchClient do
  @moduledoc """
  Default HTTP client implementation using Finch.
  """

  @behaviour Tinkex.HTTPClient

  alias Tinkex.Config

  defstruct [:config, :pool]

  @impl true
  def init(%Config{} = config) do
    state = %__MODULE__{
      config: config,
      pool: config.http_pool
    }
    {:ok, state}
  end

  @impl true
  def request(method, url, headers, body, %__MODULE__{} = state) do
    request = build_finch_request(method, url, headers, body, state.config.proxy)

    case Finch.request(request, state.pool,
                       receive_timeout: state.config.timeout) do
      {:ok, %Finch.Response{} = response} ->
        {:ok, convert_response(response), state}

      {:error, exception} ->
        {:error, convert_error(exception), state}
    end
  end

  defp build_finch_request(method, url, headers, body, proxy) do
    case proxy do
      nil ->
        Finch.build(method, url, headers, body)
      {type, host, port, opts} ->
        Finch.build(method, url, headers, body,
          proxy: {type, String.to_charlist(host), port,
                  convert_proxy_opts(opts)})
    end
  end

  defp convert_response(%Finch.Response{} = resp) do
    %{
      status: resp.status,
      headers: resp.headers,
      body: resp.body
    }
  end

  defp convert_error(exception) do
    Tinkex.Error.from_exception(exception)
  end

  defp convert_proxy_opts(opts) do
    Enum.map(opts, fn {k, v} -> {k, String.to_charlist(v)} end)
  end
end
```

#### Step 3: Integrate into API Layer

```elixir
# lib/tinkex/api/api.ex
defmodule Tinkex.API do
  # ... existing code ...

  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)
    http_client = Keyword.get(opts, :http_client, default_http_client())

    # Initialize client if needed
    {:ok, client_state} = http_client.init(config)

    url = build_url(config.base_url, path)
    headers = build_headers(:post, config, opts, config.timeout)

    case http_client.request(:post, url, headers, body, client_state) do
      {:ok, response, _new_state} ->
        handle_response(response, opts)

      {:error, error, _new_state} ->
        {:error, error}
    end
  end

  defp default_http_client do
    Application.get_env(:tinkex, :http_client,
                        Tinkex.HTTPClient.FinchClient)
  end
end
```

### Phase 3: Documentation & Examples (1 day)

#### Example 1: Corporate Proxy

```elixir
# config/runtime.exs
config :tinkex,
  proxy: System.get_env("CORPORATE_PROXY"),
  # OR
  proxy: {:http, "proxy.corp.example.com", 8080,
          username: System.fetch_env!("PROXY_USER"),
          password: System.fetch_env!("PROXY_PASS")}
```

#### Example 2: Custom HTTP Client with Metrics

```elixir
defmodule MyApp.MetricsHTTPClient do
  @behaviour Tinkex.HTTPClient

  def init(config) do
    {:ok, client_state} = Tinkex.HTTPClient.FinchClient.init(config)
    {:ok, %{finch: client_state, metrics: %{}}}
  end

  def request(method, url, headers, body, state) do
    start = System.monotonic_time()

    result = Tinkex.HTTPClient.FinchClient.request(
      method, url, headers, body, state.finch
    )

    duration = System.monotonic_time() - start

    :telemetry.execute(
      [:my_app, :http, :request],
      %{duration: duration},
      %{method: method, url: url}
    )

    case result do
      {:ok, response, new_finch_state} ->
        {:ok, response, %{state | finch: new_finch_state}}
      {:error, error, new_finch_state} ->
        {:error, error, %{state | finch: new_finch_state}}
    end
  end
end

# Usage
config = Tinkex.Config.new(
  api_key: "...",
  http_client: MyApp.MetricsHTTPClient
)
```

---

## Testing Strategy

### Unit Tests

1. **Config Proxy Parsing** (`test/tinkex/config_proxy_test.exs`)
   - String URL parsing
   - Tuple validation
   - Environment variable reading
   - Auth credential parsing
   - Error cases (invalid URLs, ports)

2. **HTTP Client Behaviour** (`test/tinkex/http_client_test.exs`)
   - Mock client injection
   - State management
   - Error propagation

3. **Finch Client** (`test/tinkex/http_client/finch_client_test.exs`)
   - Request building with proxy
   - Response conversion
   - Error handling

### Integration Tests

1. **Proxy Connectivity** (`test/integration/proxy_test.exs`)
   - HTTP proxy flow
   - HTTPS CONNECT proxy
   - Proxy authentication
   - No-proxy bypass

2. **Custom Client** (`test/integration/custom_http_client_test.exs`)
   - Mock client for testing
   - Metrics collection client
   - Logging client

3. **Multi-Client Scenarios** (`test/integration/multi_client_proxy_test.exs`)
   - Different proxies per client
   - Proxied and non-proxied clients simultaneously

### Property Tests

```elixir
# test/property/proxy_config_test.exs
defmodule Tinkex.ProxyConfigPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "proxy URL parsing is reversible" do
    check all scheme <- member_of(["http", "https"]),
              host <- string(:alphanumeric, min_length: 1),
              port <- integer(1..65535) do

      url = "#{scheme}://#{host}:#{port}"
      config = Tinkex.Config.new(api_key: "test", proxy: url)

      assert {String.to_atom(scheme), host, port, []} == config.proxy
    end
  end
end
```

---

## Migration Guide

### For Existing Users (No Breaking Changes)

Proxy support is **opt-in**:

```elixir
# Before (still works)
config = Tinkex.Config.new(api_key: "...")

# After (with proxy)
config = Tinkex.Config.new(
  api_key: "...",
  proxy: "http://proxy.example.com:8080"
)
```

### Environment Variables

```bash
# Automatic proxy detection
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=https://secure-proxy.example.com:8443

# Start app (proxy auto-configured)
mix run --no-halt
```

### Application Config

```elixir
# config/runtime.exs
config :tinkex,
  proxy: System.get_env("CORPORATE_PROXY")
```

---

## Performance Considerations

1. **Proxy Overhead:**
   - Additional TCP connection to proxy
   - ~10-50ms latency increase
   - Mitigated by connection pooling

2. **Memory:**
   - Proxy config: ~100 bytes per config struct
   - Negligible impact

3. **Connection Limits:**
   - Proxy counts toward Finch pool limits
   - May need to increase `pool_size` for high-traffic proxies

---

## Security Considerations

1. **Credential Storage:**
   ```elixir
   # GOOD: Runtime env
   proxy: {:http, "proxy.example.com", 8080,
           username: System.fetch_env!("PROXY_USER"),
           password: System.fetch_env!("PROXY_PASS")}

   # BAD: Hardcoded
   proxy: {:http, "proxy.example.com", 8080,
           username: "user", password: "password123"}
   ```

2. **Proxy Trust:**
   - Proxies can inspect all HTTP traffic
   - Use HTTPS to API endpoints
   - Verify proxy server identity

3. **Inspect Masking:**
   ```elixir
   # Ensure proxy credentials are masked in logs
   defimpl Inspect, for: Tinkex.Config do
     def inspect(config, opts) do
       data =
         config
         |> Map.from_struct()
         |> Map.update(:proxy, nil, &mask_proxy/1)

       concat(["#Tinkex.Config<", to_doc(data, opts), ">"])
     end

     defp mask_proxy({type, host, port, opts}) do
       masked_opts = Keyword.update(opts, :password, nil, fn _ -> "***" end)
       {type, host, port, masked_opts}
     end
   end
   ```
   Reuse `Tinkex.Env.mask_secret/1` for any proxy secret redaction to stay consistent with other masked fields.

---

## Open Questions

1. **SOCKS Proxy Support?**
   - Finch/Mint support SOCKS5?
   - Research needed

2. **Proxy Auto-Configuration (PAC)?**
   - Parse PAC files?
   - Out of scope for v1

3. **No-Proxy List?**
   - Skip proxy for certain URLs?
   - Common in corporate environments

4. **Proxy Rotation?**
   - Round-robin multiple proxies?
   - Fallback on proxy failure?

---

## Success Criteria

- [ ] Proxy config parsing (strings, tuples, env vars)
- [ ] Finch request building with proxy
- [ ] HTTP proxy support
- [ ] HTTPS CONNECT proxy support
- [ ] Proxy authentication (username/password)
- [ ] Custom HTTP client behaviour
- [ ] Default Finch client implementation
- [ ] Client injection at config level
- [ ] Unit tests (>95% coverage)
- [ ] Integration tests (real proxy)
- [ ] Documentation (guides + API docs)
- [ ] Examples (corporate proxy, custom client)
- [ ] No breaking changes to existing API

---

## Appendix: Python SDK Proxy Examples

### Example 1: Simple HTTP Proxy

```python
import httpx
from tinker import AsyncTinker

client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies="http://proxy.example.com:8080"
    )
)
```

### Example 2: Authenticated Proxy

```python
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies=httpx.Proxy(
            url="http://proxy.example.com:8080",
            auth=("username", "password")
        )
    )
)
```

### Example 3: Per-Protocol Proxies

```python
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies={
            "http://": "http://http-proxy.example.com:8080",
            "https://": "https://https-proxy.example.com:8443"
        }
    )
)
```

### Example 4: SOCKS Proxy

```python
# Requires httpx[socks]
client = AsyncTinker(
    api_key="...",
    http_client=httpx.AsyncClient(
        proxies="socks5://socks-proxy.example.com:1080"
    )
)
```

### Example 5: Custom Client with Middleware

```python
class LoggingClient(httpx.AsyncClient):
    async def send(self, request, **kwargs):
        print(f"Sending {request.method} {request.url}")
        response = await super().send(request, **kwargs)
        print(f"Received {response.status_code}")
        return response

client = AsyncTinker(
    api_key="...",
    http_client=LoggingClient()
)
```

---

## Summary

This gap is **critical for enterprise adoption**. Many organizations require proxy support for all outbound HTTP traffic. The lack of proxy support in Tinkex is a blocker for these users.

**Recommended Priority:** **HIGH** (implement in next sprint)

**Estimated Effort:** 3-5 days (including tests and docs)

**Breaking Changes:** None (fully backward compatible)

**Dependencies:** None (Finch already supports proxies)
