# Phase 2: HTTP Layer Implementation - Agent Prompt

> **Target:** Build the HTTP foundation with connection pooling, retry logic, and config threading.
> **Timebox:** Week 2 - Days 1-3
> **Location:** `S:\tinkex` (pure Elixir library)
> **Prerequisites:** Phase 1 types must be complete (especially `Tinkex.Error` and `Tinkex.Types.RequestErrorCategory`)

---

## 1. Project Context

You are continuing implementation of the **Tinkex SDK**, an Elixir port of the Python Tinker SDK. Phase 1 (type system) is complete. Now you'll build the HTTP layer that all clients depend on.

### 1.1 First Steps - Verify Phase 1 Completion

Before starting Phase 2, verify Phase 1 is complete:

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

If Phase 1 is incomplete, complete it first - Phase 2 depends on these types.

---

## 2. Required Reading - Documentation

Read these documents to understand HTTP layer requirements:

### 2.1 Primary References

| File | Purpose | Key Sections |
|------|---------|--------------|
| `docs/20251119/port_research/04_http_layer.md` | **PRIMARY** - Complete HTTP specification | All sections, especially lines 330-643 |
| `docs/20251119/port_research/05_error_handling.md` | Error categories and retry logic | Error categories, retry decision table |
| `docs/20251119/port_research/02_client_architecture.md` | How clients use the HTTP layer | Config threading, pool architecture |

### 2.2 Secondary References

| File | Purpose |
|------|---------|
| `docs/20251119/port_research/00_overview.md` | Project corrections history |
| `docs/20251119/port_research/07_porting_strategy.md` | Pre-implementation checklist |
| `docs/20251119/0100_tinkex_sdk_impl_proc_claude.md` | Phase dependencies |

---

## 3. Critical Requirements

### 3.1 Core Principles

1. **NO Application.get_env at call time** - Config must be threaded through function calls
2. **Config is required** - `Keyword.fetch!(opts, :config)` - no silent defaults
3. **Separate pools per operation** - Training, sampling, session, futures, telemetry
4. **x-should-retry header** - Server can override retry decisions
5. **429 with Retry-After** - Parse retry-after-ms and numeric seconds

### 3.2 Retry Logic Requirements

The HTTP layer must retry on:
- 5xx server errors (exponential backoff)
- 408 timeout (exponential backoff)
- 429 rate limit (use server-provided Retry-After)
- Connection errors (exponential backoff)
- When `x-should-retry: "true"` header is present

The HTTP layer must NOT retry on:
- 4xx client errors (except 408, 429)
- When `x-should-retry: "false"` header is present
- User errors (error category = :user)

### 3.3 Pool Configuration

| Pool Type | Size | Purpose |
|-----------|------|---------|
| `:training` | 5 | Sequential, long-running operations |
| `:sampling` | 100 | High concurrency burst traffic |
| `:session` | 5 | Critical heartbeats (keep-alive) |
| `:futures` | 50 | Concurrent polling |
| `:telemetry` | 5 | Prevent telemetry from starving ops |
| `:default` | 10 | Miscellaneous |

---

## 4. Implementation Plan

### 4.1 Implementation Order

Implement modules in this **strict order** to satisfy dependencies:

```
1. Tinkex.PoolKey          # URL normalization (no deps)
2. Tinkex.Config           # Config struct (no deps)
3. Tinkex.API              # Base HTTP module (depends on 1, 2)
4. Tinkex.API.Training     # Training endpoints (depends on 3)
5. Tinkex.API.Sampling     # Sampling endpoints (depends on 3)
6. Tinkex.API.Futures      # Future polling (depends on 3)
7. Tinkex.API.Session      # Session management (depends on 3)
8. Tinkex.API.Service      # Service operations (depends on 3)
9. Tinkex.API.Models       # Model operations (depends on 3)
10. Tinkex.API.Weights     # Weight operations (depends on 3)
11. Tinkex.API.Telemetry   # Telemetry reporting (depends on 3)
```

### 4.2 File Structure

```
lib/tinkex/
├── pool_key.ex           # Tinkex.PoolKey
├── config.ex             # Tinkex.Config
├── api/
│   ├── api.ex            # Tinkex.API (base module)
│   ├── training.ex       # Tinkex.API.Training
│   ├── sampling.ex       # Tinkex.API.Sampling
│   ├── futures.ex        # Tinkex.API.Futures
│   ├── session.ex        # Tinkex.API.Session
│   ├── service.ex        # Tinkex.API.Service
│   ├── models.ex         # Tinkex.API.Models
│   ├── weights.ex        # Tinkex.API.Weights
│   └── telemetry.ex      # Tinkex.API.Telemetry
└── application.ex        # Update with Finch pools
```

---

## 5. Detailed Module Specifications

### 5.1 Tinkex.PoolKey

Centralized URL normalization - single source of truth.

```elixir
defmodule Tinkex.PoolKey do
  @moduledoc """
  Centralized pool key generation and URL normalization.

  Single source of truth for pool key logic - used by both
  Application.start/2 and Tinkex.API.
  """

  @doc """
  Normalize base URL for consistent pool keys.

  Removes non-standard ports (80 for http, 443 for https).

  ## Examples

      iex> Tinkex.PoolKey.normalize_base_url("https://example.com:443")
      "https://example.com"

      iex> Tinkex.PoolKey.normalize_base_url("https://example.com:8443")
      "https://example.com:8443"
  """
  @spec normalize_base_url(String.t()) :: String.t()
  def normalize_base_url(url) when is_binary(url) do
    uri = URI.parse(url)

    port = case {uri.scheme, uri.port} do
      {"http", 80} -> ""
      {"https", 443} -> ""
      {_, nil} -> ""
      {_, port} -> ":#{port}"
    end

    "#{uri.scheme}://#{uri.host}#{port}"
  end

  @doc """
  Generate pool key for Finch request.

  ## Examples

      iex> Tinkex.PoolKey.build("https://example.com", :training)
      {"https://example.com", :training}
  """
  @spec build(String.t(), atom()) :: {String.t(), atom()} | :default
  def build(base_url, pool_type) when pool_type != :default do
    {normalize_base_url(base_url), pool_type}
  end

  def build(_base_url, :default), do: :default
end
```

### 5.2 Tinkex.Config

Multi-tenancy configuration struct.

```elixir
defmodule Tinkex.Config do
  @moduledoc """
  Client configuration for Tinkex SDK.

  Supports multi-tenancy - different API keys/URLs per client.
  """

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

  ## Examples

      config = Tinkex.Config.new(api_key: "my-key")

      config = Tinkex.Config.new(
        base_url: "https://staging.example.com",
        api_key: System.get_env("API_KEY"),
        timeout: 60_000
      )
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      base_url: opts[:base_url] ||
        Application.get_env(:tinkex, :base_url, @default_base_url),
      api_key: opts[:api_key] ||
        Application.get_env(:tinkex, :api_key) ||
        System.get_env("TINKER_API_KEY") ||
        raise(ArgumentError, "api_key is required"),
      http_pool: opts[:http_pool] ||
        Application.get_env(:tinkex, :http_pool, Tinkex.HTTP.Pool),
      timeout: opts[:timeout] ||
        Application.get_env(:tinkex, :timeout, @default_timeout),
      max_retries: opts[:max_retries] ||
        Application.get_env(:tinkex, :max_retries, @default_max_retries),
      user_metadata: opts[:user_metadata]
    }
  end

  @doc """
  Validate that config has required fields.
  """
  @spec validate!(t()) :: :ok
  def validate!(%__MODULE__{} = config) do
    unless config.api_key do
      raise ArgumentError, "api_key is required in config"
    end

    unless config.base_url do
      raise ArgumentError, "base_url is required in config"
    end

    :ok
  end
end
```

### 5.3 Tinkex.API (Base Module)

The core HTTP module with retry logic.

```elixir
defmodule Tinkex.API do
  @moduledoc """
  Low-level HTTP API client for Tinkex.

  All functions require config in opts - NO Application.get_env at call time.
  """

  require Logger

  # Retry constants
  @initial_retry_delay 500
  @max_retry_delay 8000

  @doc """
  POST request with retry logic.

  Config MUST be passed via opts[:config].

  ## Options

    * `:config` - Required. Tinkex.Config struct
    * `:pool_type` - Pool to use (:training, :sampling, etc.)
    * `:timeout` - Override config timeout
    * `:max_retries` - Override config max_retries
    * `:headers` - Additional headers

  ## Examples

      Tinkex.API.post("/api/v1/sample", request, [
        config: config,
        pool_type: :sampling
      ])
  """
  @spec post(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    with_retries(
      fn ->
        Finch.request(request, config.http_pool,
          receive_timeout: timeout,
          pool: Tinkex.PoolKey.build(config.base_url, pool_type)
        )
      end,
      max_retries
    )
    |> handle_response()
  end

  @doc """
  GET request with retry logic.
  """
  @spec get(String.t(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    request = Finch.build(:get, url, headers)

    with_retries(
      fn ->
        Finch.request(request, config.http_pool,
          receive_timeout: timeout,
          pool: Tinkex.PoolKey.build(config.base_url, pool_type)
        )
      end,
      max_retries
    )
    |> handle_response()
  end

  # URL building
  defp build_url(base_url, path) do
    URI.merge(base_url, path) |> to_string()
  end

  # Header building
  defp build_headers(api_key, opts) do
    base_headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  # Response handling
  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status >= 200 and status < 300 do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} ->
        {:error, %Tinkex.Error{
          message: "JSON decode error: #{inspect(reason)}",
          type: :validation,
          data: %{body: body}
        }}
    end
  end

  # 429 Rate limit - parse Retry-After
  defp handle_response({:ok, %Finch.Response{status: 429, headers: headers, body: body}}) do
    error_data = case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end

    retry_after_ms = parse_retry_after(headers)

    {:error, %Tinkex.Error{
      message: error_data["message"] || "Rate limited",
      type: :api_status,
      status: 429,
      category: :server,
      data: error_data,
      retry_after_ms: retry_after_ms
    }}
  end

  # Other error responses
  defp handle_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
    error_data = case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end

    # Parse error category from response
    category = case error_data["category"] do
      cat when is_binary(cat) ->
        Tinkex.Types.RequestErrorCategory.parse(cat)
      _ ->
        if status >= 400 and status < 500, do: :user, else: :server
    end

    # Check for retry-after on any response
    retry_after_ms = parse_retry_after(headers)

    {:error, %Tinkex.Error{
      message: error_data["message"] || error_data["error"] || "HTTP #{status}",
      type: :api_status,
      status: status,
      category: category,
      data: error_data,
      retry_after_ms: retry_after_ms
    }}
  end

  # Connection/transport errors
  defp handle_response({:error, %Mint.TransportError{} = exception}) do
    {:error, %Tinkex.Error{
      message: Exception.message(exception),
      type: :api_connection,
      data: %{exception: exception}
    }}
  end

  defp handle_response({:error, %Mint.HTTPError{} = exception}) do
    {:error, %Tinkex.Error{
      message: Exception.message(exception),
      type: :api_connection,
      data: %{exception: exception}
    }}
  end

  defp handle_response({:error, exception}) do
    {:error, %Tinkex.Error{
      message: Exception.message(exception),
      type: :api_connection,
      data: %{exception: exception}
    }}
  end

  # Retry logic with x-should-retry support
  defp with_retries(fun, max_retries, attempt \\ 0)

  defp with_retries(fun, max_retries, attempt) do
    case fun.() do
      # Success - check x-should-retry header
      {:ok, %Finch.Response{headers: headers} = response} = success ->
        case List.keyfind(headers, "x-should-retry", 0) do
          {_, "true"} when attempt < max_retries ->
            delay = retry_delay(attempt)
            Process.sleep(delay)
            with_retries(fun, max_retries, attempt + 1)

          {_, "false"} ->
            success

          _ ->
            success
        end

      # 429 rate limit - use server backoff
      {:ok, %Finch.Response{status: 429, headers: headers}} = response ->
        if attempt < max_retries do
          delay = parse_retry_after(headers)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          response
        end

      # 5xx server errors and 408 timeout
      {:ok, %Finch.Response{status: status}} = response
      when status >= 500 or status == 408 ->
        if attempt < max_retries do
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          response
        end

      # Connection/transport errors
      {:error, %Mint.TransportError{}} = error ->
        if attempt < max_retries do
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          error
        end

      {:error, %Mint.HTTPError{}} = error ->
        if attempt < max_retries do
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        else
          error
        end

      # All other responses - no retry
      other ->
        other
    end
  end

  # Exponential backoff with jitter
  defp retry_delay(attempt) do
    delay = @initial_retry_delay * :math.pow(2, attempt)
    jitter = :rand.uniform() * 0.5 + 0.5

    min(delay * jitter, @max_retry_delay)
    |> round()
  end

  # Parse Retry-After header
  defp parse_retry_after(headers) do
    # Try retry-after-ms first (milliseconds)
    case List.keyfind(headers, "retry-after-ms", 0) do
      {_, ms_str} ->
        String.to_integer(ms_str)

      nil ->
        # Fall back to retry-after (seconds)
        case List.keyfind(headers, "retry-after", 0) do
          {_, value} ->
            case Integer.parse(value) do
              {seconds, _} -> seconds * 1000
              :error -> 1000  # HTTP Date not supported in v1.0
            end

          nil ->
            1000  # Default 1 second
        end
    end
  end
end
```

### 5.4 API Endpoint Modules

Each endpoint module follows the same pattern:

#### Tinkex.API.Training

```elixir
defmodule Tinkex.API.Training do
  @moduledoc "Training API endpoints"

  @doc """
  Forward-backward pass for gradient computation.

  Uses :training pool (sequential, long-running).
  """
  @spec forward_backward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_backward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward_backward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Optimizer step to update model parameters.
  """
  @spec optim_step(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def optim_step(request, opts) do
    Tinkex.API.post(
      "/api/v1/optim_step",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Forward pass only (inference).
  """
  @spec forward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
```

#### Tinkex.API.Sampling

```elixir
defmodule Tinkex.API.Sampling do
  @moduledoc "Sampling API endpoints"

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - SamplingClient handles retries via RateLimiter.
  """
  @spec asample(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def asample(request, opts) do
    opts
    |> Keyword.put(:pool_type, :sampling)
    |> Keyword.put(:max_retries, 0)  # SamplingClient handles retries
    |> then(&Tinkex.API.post("/api/v1/asample", request, &1))
  end
end
```

#### Tinkex.API.Futures

```elixir
defmodule Tinkex.API.Futures do
  @moduledoc "Future/promise retrieval endpoints"

  @doc """
  Retrieve future result by request_id.

  Uses :futures pool (concurrent polling).
  """
  @spec retrieve(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def retrieve(request, opts) do
    Tinkex.API.post(
      "/api/v1/future/retrieve",
      request,
      Keyword.put(opts, :pool_type, :futures)
    )
  end
end
```

#### Tinkex.API.Session

```elixir
defmodule Tinkex.API.Session do
  @moduledoc "Session management endpoints"

  @doc """
  Create a new session.

  Uses :session pool (critical, keep-alive).
  """
  @spec create(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @doc """
  Send heartbeat to keep session alive.
  """
  @spec heartbeat(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def heartbeat(request, opts) do
    Tinkex.API.post(
      "/api/v1/heartbeat",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
```

#### Tinkex.API.Service

```elixir
defmodule Tinkex.API.Service do
  @moduledoc "Service and model creation endpoints"

  @spec create_model(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_model(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_model",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @spec create_sampling_session(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_sampling_session(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_sampling_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
```

#### Tinkex.API.Weights

```elixir
defmodule Tinkex.API.Weights do
  @moduledoc "Weight management endpoints"

  @spec save_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @spec load_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def load_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/load_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @spec save_weights_for_sampler(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights_for_sampler(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights_for_sampler",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
```

#### Tinkex.API.Telemetry

```elixir
defmodule Tinkex.API.Telemetry do
  @moduledoc "Telemetry reporting endpoints"

  @spec send(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def send(request, opts) do
    # Fire and forget - don't block on telemetry
    opts
    |> Keyword.put(:pool_type, :telemetry)
    |> Keyword.put(:max_retries, 1)
    |> then(&Tinkex.API.post("/api/v1/telemetry", request, &1))
  end
end
```

### 5.5 Application Setup

Update `lib/tinkex/application.ex` with Finch pools:

```elixir
defmodule Tinkex.Application do
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
         # Default pool
         :default => [
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

---

## 6. Test-Driven Development

### 6.1 Test Structure

```
test/tinkex/
├── pool_key_test.exs
├── config_test.exs
├── api/
│   ├── api_test.exs
│   ├── training_test.exs
│   ├── sampling_test.exs
│   └── ...
└── support/
    └── mock_server.ex    # Bypass setup
```

### 6.2 Test Examples

#### PoolKey Tests

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
  end

  describe "build/2" do
    test "creates tuple for non-default pools" do
      assert PoolKey.build("https://example.com:443", :training) ==
               {"https://example.com", :training}
    end

    test "returns :default for default pool" do
      assert PoolKey.build("https://example.com", :default) == :default
    end
  end
end
```

#### Config Tests

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
    end

    test "overrides defaults with options" do
      config = Config.new(
        api_key: "test-key",
        base_url: "https://staging.example.com",
        timeout: 60_000
      )

      assert config.base_url == "https://staging.example.com"
      assert config.timeout == 60_000
    end

    test "raises without api_key" do
      assert_raise ArgumentError, ~r/api_key is required/, fn ->
        Config.new([])
      end
    end
  end
end
```

#### API Retry Tests

```elixir
defmodule Tinkex.APITest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    config = Tinkex.Config.new(
      api_key: "test-key",
      base_url: "http://localhost:#{bypass.port}"
    )
    {:ok, bypass: bypass, config: config}
  end

  describe "post/3 retry logic" do
    test "retries on 5xx errors", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        count = Agent.get_and_update(counter, &{&1, &1 + 1})

        if count < 2 do
          Plug.Conn.resp(conn, 503, ~s({"error": "Service unavailable"}))
        else
          Plug.Conn.resp(conn, 200, ~s({"result": "success"}))
        end
      end)

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 3
    end

    test "uses Retry-After for 429", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        count = Agent.get_and_update(counter, &{&1, &1 + 1})

        if count < 1 do
          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "100")
          |> Plug.Conn.resp(429, ~s({"error": "Rate limited"}))
        else
          Plug.Conn.resp(conn, 200, ~s({"result": "success"}))
        end
      end)

      start = System.monotonic_time(:millisecond)
      {:ok, _result} = Tinkex.API.post("/test", %{}, config: config)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should have waited ~100ms
      assert elapsed >= 100
    end

    test "honors x-should-retry: false", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-should-retry", "false")
        |> Plug.Conn.resp(503, ~s({"error": "Don't retry"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "does not retry 4xx errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error": "Bad request"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 400
      assert error.category == :user
    end

    test "raises without config" do
      assert_raise KeyError, fn ->
        Tinkex.API.post("/test", %{}, [])
      end
    end
  end

  describe "error categorization" do
    test "parses error category from response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error": "Bad input", "category": "user"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers category from status code", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"error": "Internal error"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )
      assert error.category == :server
    end
  end
end
```

---

## 7. Quality Gates

Phase 2 is **complete** when ALL of the following are true:

### 7.1 Implementation Checklist

- [ ] `Tinkex.PoolKey` - URL normalization working
- [ ] `Tinkex.Config` - Multi-tenancy struct complete
- [ ] `Tinkex.API` - Base module with retry logic
- [ ] `Tinkex.API.Training` - forward_backward, optim_step, forward
- [ ] `Tinkex.API.Sampling` - asample
- [ ] `Tinkex.API.Futures` - retrieve
- [ ] `Tinkex.API.Session` - create, heartbeat
- [ ] `Tinkex.API.Service` - create_model, create_sampling_session
- [ ] `Tinkex.API.Weights` - save_weights, load_weights, save_weights_for_sampler
- [ ] `Tinkex.API.Telemetry` - send
- [ ] `Tinkex.Application` - Finch pools configured

### 7.2 Testing Checklist

- [ ] PoolKey normalization tests
- [ ] Config creation and validation tests
- [ ] Retry logic tests (5xx, 408, 429, connection errors)
- [ ] x-should-retry header tests
- [ ] Retry-After parsing tests (retry-after-ms, numeric seconds)
- [ ] Error categorization tests
- [ ] Config threading tests (no Application.get_env at call time)
- [ ] All tests pass: `mix test`

### 7.3 Type Safety Checklist

- [ ] All modules have `@spec` for public functions
- [ ] `Tinkex.Error` struct properly typed
- [ ] Dialyzer passes: `mix dialyzer`

### 7.4 Integration Verification

- [ ] Can create config and make request
- [ ] Different pool types are used correctly
- [ ] Retry behavior matches Python SDK
- [ ] Error categories parsed correctly

---

## 8. Common Pitfalls to Avoid

1. **Don't use Application.get_env at call time** - Only in Config.new/1
2. **Don't forget :config in opts** - It's required, not optional
3. **Don't retry on :user category errors** - Only :server and :unknown
4. **Don't hardcode retry delays** - Use Retry-After when available
5. **Don't share pools** - Use separate pools per operation type
6. **Don't forget HTTP Date fallback** - Currently defaults to 1000ms

---

## 9. Execution Commands

### 9.1 Development Cycle

```bash
# Run specific test
mix test test/tinkex/api/api_test.exs

# Run all API tests
mix test test/tinkex/api/

# Check types
mix dialyzer

# Full verification
mix test && mix dialyzer && mix format --check-formatted
```

### 9.2 Integration Testing

```bash
# Test with real API (requires TINKER_API_KEY)
TINKER_API_KEY=your-key mix test test/integration/
```

---

## 10. Next Steps After Phase 2

Once Phase 2 is complete:

1. **Phase 3**: Futures and polling (`Tinkex.Future`)
2. **Phase 4**: Client implementations (TrainingClient, SamplingClient)

The HTTP layer is the foundation for all network operations. Clients in Phase 4 will use `Tinkex.API.*` functions directly, passing their config through opts.

---

## Summary

Your task is to implement the complete HTTP layer with:

1. **Centralized URL normalization** (PoolKey)
2. **Multi-tenant configuration** (Config)
3. **Retry logic** matching Python SDK (5xx, 408, 429, x-should-retry)
4. **Error categorization** (user/server/unknown)
5. **Separate connection pools** per operation type

Every API function must require config in opts - NO global state at call time. This enables multi-tenancy where different clients can use different API keys and base URLs.

Good luck! 🚀
