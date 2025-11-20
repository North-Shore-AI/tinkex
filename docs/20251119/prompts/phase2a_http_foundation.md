# Phase 2A: HTTP Foundation - Agent Prompt

> **Target:** Build the HTTP infrastructure foundation: PoolKey, Config, and Application setup.
> **Timebox:** Week 2 - Day 1
> **Location:** `S:\tinkex` (pure Elixir library)
> **Prerequisites:** Phase 1 types must be complete (especially `Tinkex.Error` and `Tinkex.Types.RequestErrorCategory`)
> **Next:** Phase 2B (HTTP Client), Phase 2C (Endpoints and Testing)

---

## 1. Project Context

You are continuing implementation of the **Tinkex SDK**, an Elixir port of the Python Tinker SDK. Phase 1 (type system) is complete. This document covers the foundation modules that Phase 2B and 2C depend on.

### 1.1 Why Finch Instead of Req?

This SDK uses **Finch** directly rather than Req for the following reasons:

1. **HTTP/2 and Connection Pools are First-Class Concerns**

   Phase 2 is all about **pool shape** (training/sampling/session/futures/telemetry) and **pool selection per request**. Finch is literally "a small HTTP client built on Mint that focuses on connection pools". We're doing things Req doesn't expose as ergonomically:

   ```elixir
   Finch.request(request, config.http_pool,
     receive_timeout: timeout,
     pool: Tinkex.PoolKey.build(config.base_url, pool_type)
   )
   ```

   That `pool:` option, combined with `{normalized_base, :pool_type}` keys, is exactly what Finch wants to do and what Req mostly hides from you.

2. **SDK, Not App: Thin HTTP Dependency**

   For an SDK that's going to be embedded in other apps:
   - Fewer layers = fewer surprises for downstream users
   - Finch has a small, stable surface area: `build`, `request`, pool config
   - We already have our own concerns: retry policy, categorized errors, telemetry events, multi-tenant config

3. **Custom Abstraction Layer: `Tinkex.API`**

   Our `Tinkex.API` IS the high-level client abstraction handling:
   - Retry logic with server-provided backoff (x-should-retry, Retry-After)
   - Error categorization specific to Tinker's API
   - Pool routing based on operation type

   Stacking Req on top of Finch, then Tinkex.API on top of Req, would be overkill.

4. **Learning Opportunity**: Building retry logic from scratch helps understand the edge cases and produces code tailored exactly to the Python SDK's behavior.

**Note**: If you wanted built-in middleware for redirects, auth plugins, or didn't care about explicit pools per operation, Req would be tempting. But given our requirements (strict retry semantics, per-operation pools, multi-tenant config), Finch is the right choice.

### 1.2 Multi-Tenancy Design

The SDK supports multiple simultaneous clients with different configurations (different API keys, base URLs, timeouts). This is enabled by:

1. **Config Threading**: Every API function requires a `Config` struct passed via `opts[:config]`
2. **No Global State at Call Time**: `Application.get_env` is only called during `Config.new/1`, never in the HTTP request hot path
3. **Pool per Base URL**: Pool keys include the normalized base URL to prevent cross-tenant connection sharing

### 1.3 First Steps - Verify Phase 1 Completion

Before starting Phase 2A, verify Phase 1 is complete:

```bash
# Check all types exist and compile
mix compile --warnings-as-errors

# Check tests pass
mix test test/tinkex/types/

# Check Dialyzer passes
mix dialyzer

# Verify critical types exist
ls lib/tinkex/types/error.ex
ls lib/tinkex/types/request_error_category.ex
```

---

## 2. HTTP Specification (Shared Reference)

This section defines the HTTP behavior that all Phase 2 documents reference. Subsequent phases (2B, 2C) should reference this section rather than duplicating it.

### 2.1 Pool Types and Sizes

| Pool Type | Size | Purpose |
|-----------|------|---------|
| `:training` | 5 | Sequential, long-running operations |
| `:sampling` | 100 | High concurrency burst traffic |
| `:session` | 5 | Critical heartbeats (keep-alive) |
| `:futures` | 50 | Concurrent polling |
| `:telemetry` | 5 | Prevent telemetry from starving ops |
| `:default` | 10 | Miscellaneous |

### 2.2 Pool Exhaustion Behavior

When all connections in a pool are busy (e.g., all 5 `:training` connections are in use), Finch/Mint will queue the request. The request waits until a connection becomes available or the `receive_timeout` is reached.

- **Queueing**: Request #6 to the `:training` pool will wait in queue
- **Timeout**: If no connection frees within `receive_timeout`, the request fails with a timeout error
- **HTTP/2 Multiplexing**: HTTP/2 allows multiple concurrent streams per connection, so pool exhaustion is less common than with HTTP/1.1

**Monitoring Recommendation**: In production, monitor queue depth and connection utilization via telemetry events to tune pool sizes appropriately.

### 2.3 Retry Semantics

The HTTP layer retries on:
- 5xx server errors (exponential backoff)
- 408 timeout (exponential backoff)
- 429 rate limit (use server-provided Retry-After)
- Connection errors (exponential backoff)
- When `x-should-retry: "true"` header is present

The HTTP layer does NOT retry on:
- 4xx client errors (except 408, 429)
- When `x-should-retry: "false"` header is present

**Critical**: The `x-should-retry` header takes precedence over status-based logic.

### 2.4 Header Handling

All header parsing is case-insensitive per RFC 7230:
- `x-should-retry`, `X-Should-Retry`, `X-SHOULD-RETRY` are equivalent
- `retry-after`, `Retry-After`, `RETRY-AFTER` are equivalent
- `retry-after-ms`, `Retry-After-Ms` are equivalent

### 2.5 Backoff Schedule (Approximate)

With `@initial_retry_delay = 500ms` and full jitter:
- Attempt 0 (first retry): 0-500ms
- Attempt 1: 0-1000ms
- Attempt 2: 0-2000ms
- Attempt 3: 0-4000ms
- Maximum capped at 8000ms

### 2.6 Invariants

1. **Pool keys MUST be generated via `Tinkex.PoolKey.build/2`** - Never construct tuple keys manually
2. **Config MUST be threaded via `opts[:config]`** - No Application.get_env at call time
3. **`RequestErrorCategory.parse/1` MUST return an atom** - Never `{:error, _}`

---

## 3. Required Reading

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/04_http_layer.md` | **PRIMARY** - Complete HTTP specification | Lines 330-643 |
| `docs/20251119/port_research/02_client_architecture.md` | How clients use the HTTP layer | Config threading, pool architecture |

---

## 4. Implementation Plan

### 4.1 Implementation Order (Phase 2A Only)

```
1. Tinkex.PoolKey          # URL normalization (no deps)
2. Tinkex.Config           # Config struct (no deps)
3. Tinkex.Application      # Finch pools (depends on 1)
4. Update mix.exs          # Wire up application
```

### 4.2 File Structure

```
lib/tinkex/
├── pool_key.ex           # Tinkex.PoolKey
├── config.ex             # Tinkex.Config
└── application.ex        # Tinkex.Application (update existing)
```

---

## 5. Detailed Module Specifications

### 5.1 Tinkex.PoolKey

Centralized URL normalization - single source of truth. **Critical**: Validates URLs and normalizes hosts for consistent pool keys.

**Note on URL Strictness:**
- Bare hosts (e.g., `"example.com"`) are rejected - must include scheme
- Pools are configured for HTTP/2. Using `http://` base URLs is not recommended and may result in suboptimal behavior; the SDK is intended for HTTPS endpoints.

```elixir
defmodule Tinkex.PoolKey do
  @moduledoc """
  Centralized pool key generation and URL normalization.

  Single source of truth for pool key logic - used by both
  Application.start/2 and Tinkex.API.

  ## Pool Key Design

  All pool types (including `:default`) use tuple keys `{normalized_base_url, pool_type}`
  for consistency. This allows Finch to properly route requests to the correct pool
  configuration.
  """

  @doc """
  Normalize base URL for consistent pool keys.

  Removes non-standard ports (80 for http, 443 for https) and
  downcases the host for case-insensitive matching per RFC 7230.

  ## Examples

      iex> Tinkex.PoolKey.normalize_base_url("https://example.com:443")
      "https://example.com"

      iex> Tinkex.PoolKey.normalize_base_url("https://Example.COM:8443")
      "https://example.com:8443"

      iex> Tinkex.PoolKey.normalize_base_url("https://example.com")
      "https://example.com"

  ## Raises

      * `ArgumentError` - if URL is missing scheme or host
  """
  @spec normalize_base_url(String.t()) :: String.t()
  def normalize_base_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        # Downcase host for case-insensitive matching (HTTP hosts are case-insensitive per RFC 7230)
        host = String.downcase(host)

        port = case {scheme, uri.port} do
          {"http", 80} -> ""
          {"http", nil} -> ""
          {"https", 443} -> ""
          {"https", nil} -> ""
          {_, nil} -> ""
          {_, p} -> ":#{p}"
        end

        "#{scheme}://#{host}#{port}"

      _ ->
        raise ArgumentError,
          "invalid base_url for pool key: #{inspect(url)} (must have scheme and host, e.g., 'https://api.example.com')"
    end
  end

  @doc """
  Generate pool key for Finch request.

  All pool types use tuple keys for consistency.

  ## Examples

      iex> Tinkex.PoolKey.build("https://example.com:443", :training)
      {"https://example.com", :training}

      iex> Tinkex.PoolKey.build("https://example.com", :default)
      {"https://example.com", :default}

      iex> Tinkex.PoolKey.build("https://EXAMPLE.COM", :sampling)
      {"https://example.com", :sampling}
  """
  @spec build(String.t(), atom()) :: {String.t(), atom()}
  def build(base_url, pool_type) when is_atom(pool_type) do
    {normalize_base_url(base_url), pool_type}
  end
end
```

### 5.2 Tinkex.Config

Multi-tenancy configuration struct with validation.

**Note**: The `user_metadata` field is not used in Phase 2. It's reserved for future client-level metadata support.

```elixir
defmodule Tinkex.Config do
  @moduledoc """
  Client configuration for Tinkex SDK.

  Supports multi-tenancy - different API keys/URLs per client.

  ## Environment Lookup Timing

  Application.get_env is only called during Config.new/1 construction, never during
  actual HTTP requests. This means:

  - Create configs once at startup or client initialization
  - Thread the config through all API calls
  - No global state lookups in the request hot path

  ## Pool Configuration for Different Base URLs

  The Tinkex.Application module configures Finch pools for the `:tinkex, :base_url`
  from application config. If you create a Config with a different base_url:

  - Requests will use Finch's default pool configuration (not the tuned pool sizes)
  - This is typically fine for testing or secondary endpoints
  - For production multi-tenant scenarios with different base URLs that need tuned
    pools, you'll need to configure additional pools in your application supervision tree

  ## Multi-Instance Note

  If you need multiple SDK instances with different configs, you MUST pass distinct
  `:http_pool` names to avoid conflicts:

      config1 = Config.new(api_key: key1, http_pool: :tinkex_pool_tenant_a)
      config2 = Config.new(api_key: key2, http_pool: :tinkex_pool_tenant_b)

  ## Multi-Tenant Pool Setup Example

  In your host application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            # Tenant A pools
            {Finch,
             name: :tinkex_pool_tenant_a,
             pools: %{
               {"https://api-tenant-a.example.com", :default} => [protocol: :http2, size: 10],
               {"https://api-tenant-a.example.com", :sampling} => [protocol: :http2, size: 100]
             }},
            # Tenant B pools
            {Finch,
             name: :tinkex_pool_tenant_b,
             pools: %{
               {"https://api-tenant-b.example.com", :default} => [protocol: :http2, size: 10],
               {"https://api-tenant-b.example.com", :sampling} => [protocol: :http2, size: 100]
             }}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
  """

  @enforce_keys [:base_url, :api_key]
  defstruct [
    :base_url,
    :api_key,
    :http_pool,
    :timeout,
    :max_retries,
    :user_metadata
  ]

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          http_pool: atom(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          user_metadata: map() | nil
        }

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_timeout 120_000
  @default_max_retries 2

  @doc """
  Create a new config with defaults from Application env.

  ## Why Anonymous Functions for Environment Lookups

  Environment lookups are wrapped in anonymous functions to ensure **runtime**
  evaluation, not compile-time evaluation. Without this, `Application.get_env`
  calls would be evaluated during compilation, which breaks CI/CD builds where
  environment variables aren't set during `mix compile`.

  ## Examples

      config = Tinkex.Config.new(api_key: "my-key")

      config = Tinkex.Config.new(
        base_url: "https://staging.example.com",
        api_key: System.get_env("API_KEY"),
        timeout: 60_000
      )

  ## Raises

      * `ArgumentError` - if api_key is missing or base_url is invalid
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    # Wrap env lookups in anonymous functions to ensure runtime evaluation
    # This prevents compile-time evaluation which would break CI/CD builds
    # where env vars aren't set during compilation
    get_api_key = fn ->
      opts[:api_key] ||
        Application.get_env(:tinkex, :api_key) ||
        System.get_env("TINKER_API_KEY")
    end

    get_base_url = fn ->
      opts[:base_url] ||
        Application.get_env(:tinkex, :base_url, @default_base_url)
    end

    get_http_pool = fn ->
      opts[:http_pool] ||
        Application.get_env(:tinkex, :http_pool, Tinkex.HTTP.Pool)
    end

    get_timeout = fn ->
      opts[:timeout] ||
        Application.get_env(:tinkex, :timeout, @default_timeout)
    end

    get_max_retries = fn ->
      opts[:max_retries] ||
        Application.get_env(:tinkex, :max_retries, @default_max_retries)
    end

    config = %__MODULE__{
      base_url: get_base_url.(),
      api_key: get_api_key.(),
      http_pool: get_http_pool.(),
      timeout: get_timeout.(),
      max_retries: get_max_retries.(),
      user_metadata: opts[:user_metadata]
    }

    # Validate URL immediately - don't let invalid URLs slip through to runtime
    # This catches malformed URLs at config creation, not at first request
    _ = Tinkex.PoolKey.normalize_base_url(config.base_url)

    # Validate during construction - don't let invalid configs slip through
    validate!(config)
  end

  @doc """
  Validate that config has required fields.

  Called automatically by new/1. You typically don't need to call this directly,
  but it's useful if you construct a Config struct manually.

  Note: When called via `new/1`, URL validation has already occurred. When called
  directly on a manually constructed struct, consider calling
  `Tinkex.PoolKey.normalize_base_url/1` first to validate the URL format.

  ## Raises

      * `ArgumentError` - if required fields are missing or invalid
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    unless config.api_key do
      raise ArgumentError,
        "api_key is required. Pass :api_key option or set TINKER_API_KEY env var"
    end

    unless config.base_url do
      raise ArgumentError, "base_url is required in config"
    end

    unless is_atom(config.http_pool) do
      raise ArgumentError, "http_pool must be an atom, got: #{inspect(config.http_pool)}"
    end

    unless is_integer(config.timeout) and config.timeout > 0 do
      raise ArgumentError, "timeout must be a positive integer, got: #{inspect(config.timeout)}"
    end

    unless is_integer(config.max_retries) and config.max_retries >= 0 do
      raise ArgumentError, "max_retries must be a non-negative integer, got: #{inspect(config.max_retries)}"
    end

    # Warn if using a different base_url than the Application config
    # Requests will use Finch's default pool config, not the tuned pools
    app_base = Application.get_env(:tinkex, :base_url, "https://tinker.thinkingmachines.dev/services/tinker-prod")

    with {:ok, config_normalized} <- {:ok, Tinkex.PoolKey.normalize_base_url(config.base_url)},
         {:ok, app_normalized} <- {:ok, Tinkex.PoolKey.normalize_base_url(app_base)} do
      if config_normalized != app_normalized do
        require Logger
        Logger.warning("""
        Config base_url (#{config_normalized}) differs from Application config (#{app_normalized}).
        Requests will use Finch's default pool, not tuned pools.
        For production multi-tenant scenarios, configure additional pools in your supervision tree.
        """)
      end
    end

    config
  end
end
```

### 5.3 Tinkex.Application

Finch pool configuration with proper pool keys.

```elixir
defmodule Tinkex.Application do
  @moduledoc """
  Application supervisor for Tinkex SDK.

  Starts Finch HTTP connection pools with tuned configurations for different
  operation types.

  ## Pool Configuration

  Pools are tuned for the configured `:tinkex, :base_url`. Requests to different
  base URLs will use Finch's default pool config. This is typically fine for
  testing or secondary endpoints. For production multi-tenant scenarios requiring
  tuned pools for multiple base URLs, configure additional pools in your
  application's supervision tree.

  ## Pool Types and Sizes

  See Section 2.1 (HTTP Specification) for pool type definitions.

  ## Future Enhancements

  - Pool health monitoring with periodic health checks
  - Telemetry events for pool status (idle/active connections)
  - Dynamic pool creation for multi-tenant scenarios
  """

  use Application

  @impl true
  def start(_type, _args) do
    base_url = Application.get_env(
      :tinkex,
      :base_url,
      "https://tinker.thinkingmachines.dev/services/tinker-prod"
    )

    normalized_base = Tinkex.PoolKey.normalize_base_url(base_url)

    children = [
      # HTTP connection pools
      {Finch,
       name: Tinkex.HTTP.Pool,
       pools: %{
         # Default pool - uses tuple key for consistency with other pools
         {normalized_base, :default} => [
           protocol: :http2,
           size: 10,
           max_idle_time: 60_000
         ],
         # Training (sequential, long-running)
         {normalized_base, :training} => [
           protocol: :http2,
           size: 5,
           count: 1,
           max_idle_time: 60_000
         ],
         # Sampling (high concurrency)
         {normalized_base, :sampling} => [
           protocol: :http2,
           size: 100,
           max_idle_time: 30_000
         ],
         # Session (critical heartbeats)
         {normalized_base, :session} => [
           protocol: :http2,
           size: 5,
           max_idle_time: :infinity
         ],
         # Futures (concurrent polling)
         {normalized_base, :futures} => [
           protocol: :http2,
           size: 50,
           max_idle_time: 60_000
         ],
         # Telemetry (isolated)
         {normalized_base, :telemetry} => [
           protocol: :http2,
           size: 5,
           max_idle_time: 60_000
         ]
       }}
    ]

    opts = [strategy: :one_for_one, name: Tinkex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 5.4 Update mix.exs

**Critical**: Wire up the Application module so Finch pools actually start.

```elixir
def application do
  [
    mod: {Tinkex.Application, []},
    extra_applications: [:logger]
  ]
end

defp deps do
  [
    {:finch, "~> 0.18"},
    {:jason, "~> 1.4"},
    {:telemetry, "~> 1.2"},
    # Test dependencies
    {:bypass, "~> 2.1", only: :test},
    {:supertester, "~> 0.3.0", only: :test}  # For future OTP-level tests; Phase 2 uses ExUnit + Bypass only
  ]
end
```

---

## 6. Test-Driven Development

### 6.1 Test Structure

```
test/tinkex/
├── pool_key_test.exs
└── config_test.exs
```

### 6.2 PoolKey Tests

```elixir
defmodule Tinkex.PoolKeyTest do
  use ExUnit.Case, async: true

  alias Tinkex.PoolKey

  describe "normalize_base_url/1" do
    test "removes standard HTTPS port" do
      assert PoolKey.normalize_base_url("https://example.com:443") ==
               "https://example.com"
    end

    test "removes standard HTTP port" do
      assert PoolKey.normalize_base_url("http://example.com:80") ==
               "http://example.com"
    end

    test "preserves non-standard ports" do
      assert PoolKey.normalize_base_url("https://example.com:8443") ==
               "https://example.com:8443"
    end

    test "handles URLs without port" do
      assert PoolKey.normalize_base_url("https://example.com") ==
               "https://example.com"
    end

    test "downcases host for case-insensitive matching" do
      assert PoolKey.normalize_base_url("https://EXAMPLE.COM") ==
               "https://example.com"
      assert PoolKey.normalize_base_url("https://Example.Com:8080") ==
               "https://example.com:8080"
    end

    test "raises on bare host without scheme" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("example.com")
      end
    end

    test "raises on invalid URL without host" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("https://")
      end
    end

    test "raises on completely invalid URL" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("not-a-url")
      end
    end
  end

  describe "build/2" do
    test "creates tuple for training pool" do
      assert PoolKey.build("https://example.com:443", :training) ==
               {"https://example.com", :training}
    end

    test "creates tuple for default pool" do
      assert PoolKey.build("https://example.com", :default) ==
               {"https://example.com", :default}
    end

    test "creates tuple for sampling pool" do
      assert PoolKey.build("https://EXAMPLE.COM", :sampling) ==
               {"https://example.com", :sampling}
    end

    test "normalizes URL in pool key" do
      assert PoolKey.build("https://example.com:443", :futures) ==
               {"https://example.com", :futures}
    end
  end
end
```

### 6.3 Config Tests

```elixir
defmodule Tinkex.ConfigTest do
  use ExUnit.Case

  alias Tinkex.Config

  describe "new/1" do
    test "creates config with defaults" do
      config = Config.new(api_key: "test-key")

      assert config.api_key == "test-key"
      assert config.base_url =~ "tinker.thinkingmachines.dev"
      assert config.timeout == 120_000
      assert config.max_retries == 2
      assert config.http_pool == Tinkex.HTTP.Pool
    end

    test "overrides defaults with options" do
      config = Config.new(
        api_key: "test-key",
        base_url: "https://staging.example.com",
        timeout: 60_000,
        max_retries: 5
      )

      assert config.base_url == "https://staging.example.com"
      assert config.timeout == 60_000
      assert config.max_retries == 5
    end

    test "accepts custom http_pool" do
      config = Config.new(
        api_key: "test-key",
        http_pool: :my_custom_pool
      )

      assert config.http_pool == :my_custom_pool
    end

    test "accepts user_metadata" do
      config = Config.new(
        api_key: "test-key",
        user_metadata: %{user_id: "123", team: "ml"}
      )

      assert config.user_metadata == %{user_id: "123", team: "ml"}
    end

    test "raises without api_key" do
      assert_raise ArgumentError, ~r/api_key is required/, fn ->
        Config.new([])
      end
    end

    test "raises with invalid timeout" do
      assert_raise ArgumentError, ~r/timeout must be a positive integer/, fn ->
        Config.new(api_key: "key", timeout: -1)
      end
    end

    test "raises with invalid max_retries" do
      assert_raise ArgumentError, ~r/max_retries must be a non-negative integer/, fn ->
        Config.new(api_key: "key", max_retries: -1)
      end
    end
  end

  describe "validate!/1" do
    test "returns config if valid" do
      config = %Config{
        api_key: "key",
        base_url: "https://example.com",
        http_pool: :pool,
        timeout: 1000,
        max_retries: 2,
        user_metadata: nil
      }

      assert Config.validate!(config) == config
    end

    test "raises if api_key is nil" do
      config = %Config{
        api_key: nil,
        base_url: "https://example.com",
        http_pool: :pool,
        timeout: 1000,
        max_retries: 2,
        user_metadata: nil
      }

      assert_raise ArgumentError, ~r/api_key is required/, fn ->
        Config.validate!(config)
      end
    end
  end
end
```

---

## 7. Quality Gates for Phase 2A

Phase 2A is **complete** when ALL of the following are true:

### 7.1 Implementation Checklist

- [ ] `Tinkex.PoolKey` - URL normalization with validation and host downcasing
- [ ] `Tinkex.Config` - Multi-tenancy struct with @enforce_keys and validate! in new/1
- [ ] `Tinkex.Application` - Finch pools with tuple keys for all pool types
- [ ] `mix.exs` - Application module wired up with `mod:` option
- [ ] `mix.exs` - Dependencies include `{:supertester, "~> 0.3.0", only: :test}`

### 7.2 Testing Checklist

- [ ] PoolKey normalization tests (standard ports, non-standard ports, case-insensitivity)
- [ ] PoolKey validation tests (invalid URLs raise ArgumentError)
- [ ] Config creation and validation tests
- [ ] Config error cases (missing api_key, invalid values)
- [ ] All tests pass: `mix test test/tinkex/pool_key_test.exs test/tinkex/config_test.exs`

### 7.3 Type Safety Checklist

- [ ] All modules have `@spec` for public functions
- [ ] `@enforce_keys` on Config struct
- [ ] Dialyzer passes: `mix dialyzer`

---

## 8. Common Pitfalls to Avoid

1. **Don't forget to wire up Application in mix.exs** - Without `mod:`, your pools won't start
2. **Don't allow invalid URLs to generate pool keys** - Fail loud with ArgumentError
3. **Don't forget to downcase hosts** - HTTP hosts are case-insensitive per RFC 7230
4. **Don't call Application.get_env outside of Config.new/1** - Wrap in anonymous functions for runtime evaluation
5. **Don't skip validation in Config.new/1** - Always call validate! at construction time
6. **Don't construct pool key tuples manually** - Always use `Tinkex.PoolKey.build/2`

---

## 9. Execution Commands

```bash
# Run Phase 2A tests
mix test test/tinkex/pool_key_test.exs test/tinkex/config_test.exs

# Check types
mix dialyzer

# Full verification
mix compile --warnings-as-errors && mix test test/tinkex/pool_key_test.exs test/tinkex/config_test.exs && mix dialyzer
```

---

## 10. Dependencies and Next Steps

### Dependencies

Phase 2A has no dependencies on other Phase 2 parts.

### Required Before Phase 2B

Phase 2B (HTTP Client) requires Phase 2A to be complete:
- `Tinkex.PoolKey` for pool key generation
- `Tinkex.Config` for config threading
- `Tinkex.Application` running Finch pools

### Required Before Phase 2C

Phase 2C (Endpoints and Testing) requires both Phase 2A and 2B to be complete.

---

## 11. Production Deployment Considerations

This section covers cross-cutting concerns for production deployments. These apply across all Phase 2 components.

### 11.1 Pool Monitoring

Monitor Finch pool health via telemetry. Key metrics:

```elixir
# Attach to Finch telemetry events
:telemetry.attach_many("finch-metrics", [
  [:finch, :request, :start],
  [:finch, :request, :stop],
  [:finch, :request, :exception],
  [:finch, :queue, :start],
  [:finch, :queue, :stop]
], &handle_finch_event/4, %{})

# Alert on queue time exceeding threshold
defp handle_finch_event([:finch, :queue, :stop], measurements, metadata, _config) do
  if measurements.duration > 5_000_000_000 do  # 5 seconds in native units
    Logger.warning("Finch queue time exceeded: #{System.convert_time_unit(measurements.duration, :native, :millisecond)}ms")
  end
end
```

### 11.2 Pool Size Tuning

Default pool sizes are starting points. Tune based on:

- **:training (5)**: Increase if you see queue delays during sequential training operations
- **:sampling (100)**: Increase for higher burst throughput; monitor HTTP/2 stream limits
- **:session (5)**: Usually sufficient; increase only if running many concurrent sessions

### 11.3 Idempotency Considerations

**Warning**: The HTTP layer retries all 5xx errors by default, including non-idempotent operations (POST). If your API endpoints are not idempotent:

1. Set `max_retries: 0` for non-idempotent operations
2. Use idempotency keys where supported by the API
3. Check Phase 4 clients for operation-specific retry policies

### 11.4 Request Cancellation

When a calling process crashes, HTTP requests are **not** automatically cancelled:

- **In-flight requests**: Complete and discard results
- **Pending retries**: Won't be attempted if caller is dead

For resource-sensitive applications, consider:
- Wrapping API calls in linked Tasks
- Using `Task.shutdown/2` with timeout
- Implementing explicit cancellation tokens

### 11.5 API Key Rotation

To rotate API keys without downtime:

```elixir
# Create new config with new key
new_config = Tinkex.Config.new(api_key: new_key)

# Gradually shift traffic to new config
# Old requests use old_config, new requests use new_config
# Once all old requests complete, discard old_config
```

### 11.6 Circuit Breaker Pattern

For production resilience, consider wrapping Tinkex calls with a circuit breaker:

```elixir
# Example with Fuse library
defmodule MyApp.TinkerClient do
  @fuse_name :tinkex_fuse
  @fuse_options [
    strategy: {:standard, 10, 10_000},  # 10 failures in 10s
    refresh: 15_000                      # Reset after 15s
  ]

  def call(fun) do
    case :fuse.ask(@fuse_name, :sync) do
      :ok ->
        case fun.() do
          {:error, %Tinkex.Error{type: :api_connection}} = error ->
            :fuse.melt(@fuse_name)
            error
          result ->
            result
        end
      :blown ->
        {:error, :circuit_open}
    end
  end
end
```

### 11.7 Future Enhancements

Consider adding for production deployments:

- **Lifecycle diagrams**: Visual documentation of request flow through retry logic
- **Connection draining**: Graceful shutdown with in-flight request completion
- **Distributed tracing**: OpenTelemetry integration for cross-service observability

---

## Summary

Phase 2A establishes the HTTP foundation:

1. **URL Normalization** - Centralized pool key generation with validation
2. **Multi-tenant Configuration** - Config struct with runtime env lookup
3. **Finch Pools** - Properly configured pools for different operation types
4. **Shared HTTP Specification** - Reference section for all Phase 2 documents

This foundation enables the HTTP client (Phase 2B) and endpoint modules (Phase 2C).
