# Advanced Configuration

This guide covers advanced configuration options for Tinkex, including environment variables, application-level configuration, HTTP connection pooling, session management, and production best practices.

## Table of Contents

1. [Configuration Overview](#configuration-overview)
2. [Config Struct Reference](#config-struct-reference)
3. [Environment Variables](#environment-variables)
4. [Application Configuration](#application-configuration)
5. [HTTP Pool Configuration](#http-pool-configuration)
6. [Timeout Configuration](#timeout-configuration)
7. [Session Management](#session-management)
8. [User Metadata](#user-metadata)
9. [Multi-Environment Setup](#multi-environment-setup)
10. [Production Best Practices](#production-best-practices)

## Configuration Overview

Tinkex uses a layered configuration approach, with values resolved in this order of precedence:

1. **Runtime options** (highest priority) - passed to `Tinkex.Config.new/1`
2. **Application environment** - set in `config/config.exs`
3. **Environment variables** (fallback) - `TINKER_API_KEY`, `TINKER_BASE_URL`
4. **Defaults** (lowest priority) - built-in SDK defaults

This design supports multi-tenant usage where different API keys, base URLs, and timeout policies can coexist within a single BEAM VM.

```elixir
# Runtime options take precedence
config = Tinkex.Config.new(
  api_key: "tml-runtime-key",        # Overrides env/config
  timeout: 60_000                # Overrides default
)
```

## Config Struct Reference

The `Tinkex.Config` struct contains all configuration needed for API requests:

```elixir
@type t :: %Tinkex.Config{
  base_url: String.t(),            # API base URL (required)
  api_key: String.t(),             # API authentication key (required)
  http_pool: atom(),               # Finch pool base name/prefix (default: Tinkex.HTTP.Pool)
  http_client: module(),           # HTTP client module (default: Tinkex.API)
  timeout: pos_integer(),          # Request timeout in milliseconds (default: 60_000; set parity_mode: :beam for 120_000)
  max_retries: non_neg_integer(),  # Additional retry attempts (default: 10; set parity_mode: :beam for 2)
  telemetry_enabled?: boolean(),   # Toggle client telemetry (default: true)
  log_level: :debug | :info | :warn | :error | nil, # Logger level (applied at startup)
  dump_headers?: boolean(),        # Dump HTTP headers (redacted)
  default_headers: map(),          # Headers merged into every request
  default_query: map(),            # Query params merged into every request
  cf_access_client_id: String.t() | nil,
  cf_access_client_secret: String.t() | nil,
  tags: [String.t()],              # Session tags (default: ["tinkex-elixir"])
  feature_gates: [String.t()],     # Feature gates (default: ["async_sampling"])
  user_metadata: map() | nil       # Custom metadata for sessions (optional)
}
```

### Field Details

**base_url** (required)
- Production default: `"https://tinker.thinkingmachines.dev/services/tinker-prod"`
- Must include scheme (`https://`) and host
- Paths are discarded (Finch pools by host, not path)
- Automatically normalized (lowercased, default ports stripped)

**api_key** (required)
- Authentication token for Tinkex API
- Retrieved from runtime option > app config > `TINKER_API_KEY` env var
- Automatically masked in `inspect/1` output for security

**http_pool** (default: `Tinkex.HTTP.Pool`)
- Base name/prefix for Finch pools
- Must be an atom
- Per-type pools (session/training/sampling/futures/telemetry) derive from this name + `base_url`
- See [HTTP Pool Configuration](#http-pool-configuration) for custom pools and sizing

**http_client** (default: `Tinkex.API`)
- Module implementing the `Tinkex.HTTPClient` behaviour
- Override for custom HTTP adapters or test stubs

**timeout** (default: `60_000` ms = 1 minute; use parity_mode: :beam for 120_000)
- Maximum time for a single HTTP request
- Can be overridden per-request with `timeout:` option
- Does not include retry delays

**max_retries** (default: `10`; use parity_mode: :beam for 2)
- Number of additional attempts after initial request fails
- Total attempts = 1 + max_retries (default: 11 total)
- Uses exponential backoff: starts at 500ms and caps at 10_000ms

**user_metadata** (optional)
- Custom key-value pairs attached to sessions
- Useful for tracking user IDs, experiment names, etc.
- Sent to server during session creation
- Example: `%{user_id: "user-123", experiment: "exp-456"}`

**default_headers / default_query**
- Maps merged into every request (opts > app config > env > `%{}`)
- Header values are stringified and secret headers (`x-api-key`, `cf-access-client-secret`, auth headers) are redacted in dumps/inspect
- Query values are stringified; `nil` entries are dropped

**telemetry_enabled? / log_level / dump_headers?**
- `telemetry_enabled?` toggles client-side telemetry (default: true)
- `log_level` sets Logger at application start when provided (`:debug | :info | :warn | :error`)
- `dump_headers?` enables HTTP request/response dumps with sensitive headers redacted

## Environment Variables

Tinkex reads these environment variables as fallback configuration:

### TINKER_API_KEY (required)

Your Tinkex API authentication key.

```bash
export TINKER_API_KEY="tml-your-api-key-here"
```

The API key must start with the `tml-` prefix.

```elixir
# Automatically used if no other api_key specified
config = Tinkex.Config.new()  # Uses TINKER_API_KEY
```

### TINKER_BASE_URL (optional)

Override the default API base URL.

```bash
export TINKER_BASE_URL="https://staging.example.com"
```

```elixir
config = Tinkex.Config.new()  # Uses TINKER_BASE_URL if set
```

### Development vs Production

```bash
# Development
export TINKER_API_KEY="tml-dev-key-123"
export TINKER_BASE_URL="https://dev.tinker.example.com"

# Production
export TINKER_API_KEY="tml-prod-key-456"
# Uses default production URL
```

## Application Configuration

Configure defaults in your `config/config.exs` that apply to all configs unless overridden:

```elixir
# config/config.exs
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod",
  timeout: 60_000,
  max_retries: 10,
  http_pool: Tinkex.HTTP.Pool,
  enable_http_pools: true,
  heartbeat_interval_ms: 10_000,
  heartbeat_warning_after_ms: 120_000,
  metrics_enabled: true,
  metrics_latency_buckets: [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000],
  metrics_histogram_max_samples: 1_000,
  suppress_base_url_warning: false
```

### Configuration Options

**:api_key**
- Fallback when not provided at runtime
- Should use `System.get_env/1` for security

**:base_url**
- Default: `"https://tinker.thinkingmachines.dev/services/tinker-prod"`
- Determines which Finch pool is created at startup

**:timeout**
- Default: `60_000` ms (set `parity_mode: :beam` for `120_000`)
- Global default for all requests

**:max_retries**
- Default: `10` (set `parity_mode: :beam` for `2`)
- Number of retry attempts after initial failure

**:http_pool**
- Default: `Tinkex.HTTP.Pool`
- Name of Finch pool for HTTP connections

**:enable_http_pools**
- Default: `true`
- Set to `false` to disable automatic Finch pool startup
- Useful when managing pools manually

**:heartbeat_interval_ms**
- Default: `10_000` ms (10 seconds)
- How often to send session heartbeats
- Lower values = more frequent health checks
- Higher values = reduced API calls

**:heartbeat_warning_after_ms**
- Default: `120_000` ms (2 minutes)
- How long heartbeats can fail consecutively before a warning is emitted (heartbeats continue retrying)

**:metrics_enabled**
- Default: `true`
- Toggle telemetry metrics collection
- Set to `false` in test environments for speed

**:metrics_latency_buckets**
- Default: `[1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]`
- Histogram bucket boundaries in milliseconds

**:metrics_histogram_max_samples**
- Default: `1_000`
- Maximum samples to keep for percentile calculations

**:suppress_base_url_warning**
- Default: `false`
- Set to `true` to suppress warnings about mismatched base URLs
- Useful in multi-tenant scenarios with custom pools

## HTTP Pool Configuration

Tinkex uses [Finch](https://hexdocs.pm/finch/) for HTTP connection pooling and now isolates connections per pool type (session, training, sampling, futures, telemetry) to match Python behavior.

### Automatic pools

`Tinkex.Application` starts per-type Finch pools when `:enable_http_pools` is `true` (default). Pool names are derived from `http_pool` + `base_url` via `Tinkex.PoolKey.pool_name/3`. Defaults mirror Python:

- `:session`: size 5, count 1
- `:training`: size 5, count 2
- `:sampling`: size/count from `pool_size`/`pool_count` (defaults: 50/20)
- `:futures`: half of sampling size/count (rounded up)
- `:telemetry`: size 5, count 1

Example of the generated specs:

```elixir
pool_map =
  Tinkex.Application.build_pool_map(
    "https://tinker.thinkingmachines.dev/services/tinker-prod",
    50,
    20,
    %{},
    :my_base_pool
  )

# Start pools manually (Application does this for you when enabled)
children =
  Enum.map(pool_map, fn {_type, %{name: name, pools: pools}} ->
    {Finch, name: name, pools: pools}
  end)
```

Requests resolve pool names via `Tinkex.PoolKey.resolve_pool_name/3`, falling back to the base `http_pool` if a typed pool is not running (useful for tests or custom supervisors).

### Customizing pools

- Override per-type sizing with `config :tinkex, pool_overrides: %{training: %{size: 10, count: 4}}`.
- Change the base name/prefix with `config :tinkex, :http_pool, :my_pool_prefix`.
- Set `config :tinkex, :enable_http_pools, false` to manage Finch pools yourself (still use `PoolKey.pool_name/3` for consistent naming).

### Pool Sizing Guidelines

**Low traffic (<100 req/s)**
```elixir
size: 10-25
count: 1-2
```

**Medium traffic (100-1000 req/s)**
```elixir
size: 25-50
count: 2-4
```

**High traffic (>1000 req/s)**
```elixir
size: 50-100
count: 4-8
```

Monitor pool exhaustion via metrics and adjust accordingly.

## Timeout Configuration

Tinkex supports both global and per-request timeouts.

### Global Timeout

Set a default timeout for all requests via config:

```elixir
# Via application config
config :tinkex, timeout: 60_000  # 60 seconds

# Via Config.new
config = Tinkex.Config.new(timeout: 60_000)
```

### Per-Request Timeout

Override the global timeout for specific operations:

```elixir
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service,
  base_model: "meta-llama/Llama-3.1-8B"
)

# Long-running generation with custom timeout
{:ok, task} = Tinkex.SamplingClient.sample(
  sampler,
  prompt,
  params,
  timeout: 300_000  # 5 minutes for this specific request
)
```

### Timeout Recommendations

**Operation Type** | **Recommended Timeout**
---|---
Session creation | 30 seconds (`30_000`)
Simple sampling | 60 seconds (`60_000`)
Complex generation | 120-300 seconds (`120_000` - `300_000`)
Checkpoint upload | 600 seconds (`600_000`)
Checkpoint download | 900 seconds (`900_000`)
List/query operations | 15-30 seconds (`15_000` - `30_000`)

### Timeout vs Retries

Timeouts and retries work together:

```elixir
config = Tinkex.Config.new(
  timeout: 30_000,      # Each attempt times out after 30s
  max_retries: 2        # Up to 3 total attempts
)

# Maximum wall time = timeout * (1 + max_retries) + retry_delays
# = 30s * 3 + (0.5s + 1s + 2s) = 93.5s worst case
```

## Session Management

Sessions provide connection reuse and health monitoring via automatic heartbeats.

### Heartbeat Configuration

Configure heartbeat frequency globally:

```elixir
# config/config.exs
config :tinkex, heartbeat_interval_ms: 10_000  # 10 seconds (default)

# More aggressive health checks
config :tinkex, heartbeat_interval_ms: 5_000   # 5 seconds

# Reduce API calls
config :tinkex, heartbeat_interval_ms: 30_000  # 30 seconds
```

Heartbeat requests use a fixed 10_000ms timeout with `max_retries: 0` (Python parity); warnings are debounced to avoid log spam when connectivity is impaired.

### Session Lifecycle

Sessions are automatically managed by `Tinkex.SessionManager`:

1. **Creation**: When `ServiceClient.start_link/1` is called
2. **Heartbeats**: Sent every `heartbeat_interval_ms` automatically
3. **Cleanup**: Session stopped when `ServiceClient` process exits

```elixir
# Session created automatically
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

# Heartbeats sent automatically in background
# No manual intervention needed

# Session cleaned up automatically when service exits
GenServer.stop(service)
```

### Manual Session Management

For advanced use cases, you can manage sessions directly:

```elixir
{:ok, session_id} = Tinkex.SessionManager.start_session(config)

# Do work with session_id
# ...

# Clean up when done
:ok = Tinkex.SessionManager.stop_session(session_id)
```

### Heartbeat Behavior

- **Success (200)**: Session remains active
- **Any error (4xx/5xx/network)**: Session remains tracked; heartbeat retries on the next interval
- **Sustained failures**: If failures exceed `heartbeat_warning_after_ms` (default: 120s), a warning is logged with the last error; the manager keeps retrying

## User Metadata

Attach custom metadata to sessions for tracking and debugging:

### Basic Usage

```elixir
config = Tinkex.Config.new(
  api_key: "tml-your-key",
  user_metadata: %{
    user_id: "user-12345",
    experiment: "baseline-v1",
    environment: "production"
  }
)

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
# Metadata sent to server during session creation
```

### Use Cases

**User Tracking**
```elixir
user_metadata: %{
  user_id: current_user.id,
  email: current_user.email,
  tier: current_user.subscription_tier
}
```

**Experiment Tracking**
```elixir
user_metadata: %{
  experiment_id: "exp-789",
  variant: "treatment",
  cohort: "week-2024-47"
}
```

**Environment Tracking**
```elixir
user_metadata: %{
  environment: config_env(),
  node: Node.self(),
  region: System.get_env("AWS_REGION")
}
```

**Cost Attribution**
```elixir
user_metadata: %{
  cost_center: "ml-research",
  project: "llama-fine-tuning",
  budget_code: "FY24-Q4"
}
```

### Metadata Best Practices

1. **Keep it small**: Metadata is sent with every session creation
2. **Use string keys**: For consistency and JSON serialization
3. **Avoid PII**: Unless required for your use case
4. **Use consistent keys**: For easier analysis across sessions
5. **Version your schemas**: Add `metadata_version: "v1"` field

## Multi-Environment Setup

Configure Tinkex for development, staging, and production environments.

### Directory Structure

```
config/
├── config.exs       # Shared config
├── dev.exs          # Development overrides
├── test.exs         # Test overrides
└── prod.exs         # Production overrides
```

### config/config.exs

```elixir
import Config

# Shared defaults
config :tinkex,
  enable_http_pools: true,
  heartbeat_interval_ms: 10_000,
  metrics_enabled: true,
  max_retries: 2

# Load environment-specific config
import_config "#{config_env()}.exs"
```

### config/dev.exs

```elixir
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY_DEV"),
  base_url: "https://dev.tinker.example.com",
  timeout: 30_000,
  heartbeat_interval_ms: 30_000,  # Less frequent in dev
  suppress_base_url_warning: true
```

### config/test.exs

```elixir
import Config

config :tinkex,
  api_key: "tml-test-api-key",
  base_url: "http://localhost:4000",
  enable_http_pools: false,  # Use mock
  metrics_enabled: false,    # Faster tests
  heartbeat_interval_ms: 60_000  # Minimal heartbeats
```

### config/prod.exs

```elixir
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: System.get_env("TINKER_BASE_URL") ||
    "https://tinker.thinkingmachines.dev/services/tinker-prod",
  timeout: 120_000,
  max_retries: 3,  # More aggressive retries in prod
  heartbeat_interval_ms: 10_000

# Validate required environment variables at compile time
unless System.get_env("TINKER_API_KEY") do
  raise "TINKER_API_KEY environment variable is required in production"
end
```

### Runtime Configuration

For releases, use runtime configuration in `config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  config :tinkex,
    api_key: System.fetch_env!("TINKER_API_KEY"),
    base_url: System.get_env("TINKER_BASE_URL") ||
      "https://tinker.thinkingmachines.dev/services/tinker-prod",
    timeout: String.to_integer(System.get_env("TINKER_TIMEOUT") || "120000"),
    max_retries: String.to_integer(System.get_env("TINKER_MAX_RETRIES") || "3"),
    heartbeat_interval_ms: String.to_integer(
      System.get_env("TINKER_HEARTBEAT_MS") || "10000"
    )
end
```

## Production Best Practices

### 1. Secret Management

Never hardcode API keys:

```elixir
# ❌ BAD: Hardcoded key
config :tinkex, api_key: "tml-sk-abc123..."

# ✅ GOOD: Environment variable
config :tinkex, api_key: System.get_env("TINKER_API_KEY")

# ✅ BETTER: Runtime config with validation
# config/runtime.exs
config :tinkex, api_key: System.fetch_env!("TINKER_API_KEY")
```

### 2. Connection Pooling

Tune pool sizes for your workload:

```elixir
{Finch,
 name: Tinkex.HTTP.Pool,
 pools: %{
   default: [
     size: 50,              # Adjust based on concurrent requests
     count: 4,              # Number of pools
     protocols: [:http2],   # Prefer HTTP/2 for multiplexing
     pool_max_idle_time: :timer.minutes(5)
   ]
 }}
```

### 3. Timeout Strategy

Use operation-appropriate timeouts:

```elixir
# Short timeout for list operations
{:ok, sessions} = Tinkex.RestClient.list_sessions(rest,
  limit: 10,
  timeout: 15_000  # 15s
)

# Long timeout for generation
{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params,
  timeout: 300_000  # 5 minutes
)
```

### 4. Retry Configuration

Balance reliability with latency:

```elixir
# High-reliability, latency-tolerant
config :tinkex, max_retries: 3

# Low-latency, fail-fast
config :tinkex, max_retries: 1
```

### 5. Error Handling

Always handle errors explicitly:

```elixir
case Tinkex.SamplingClient.sample(sampler, prompt, params) do
  {:ok, task} ->
    case Task.await(task, 120_000) do
      {:ok, response} ->
        process_sequences(response.sequences)

      {:error, %Tinkex.Error{code: :timeout}} ->
        Logger.error("Request timed out")
        {:error, :timeout}

      {:error, %Tinkex.Error{code: :rate_limit_exceeded}} ->
        Logger.warning("Rate limited, backing off")
        Process.sleep(5_000)
        retry_request()

      {:error, error} ->
        Logger.error("Request failed: #{Tinkex.Error.format(error)}")
        {:error, error}
    end

  {:error, error} ->
    Logger.error("Failed to start sample: #{inspect(error)}")
    {:error, error}
end
```

### 6. Metrics and Monitoring

Enable metrics in production:

```elixir
# config/prod.exs
config :tinkex,
  metrics_enabled: true,
  metrics_latency_buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

# Monitor via Telemetry
:telemetry.attach(
  "tinkex-monitor",
  [:tinkex, :http, :request, :stop],
  &MyApp.Telemetry.handle_event/4,
  nil
)

# Or use built-in metrics
snapshot = Tinkex.Metrics.snapshot()
IO.inspect(snapshot.counters, label: "request counts")
IO.inspect(snapshot.histograms[:tinkex_request_duration_ms], label: "latency")
```

### 7. Graceful Shutdown

Ensure sessions are cleaned up:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children
      {MyApp.TinkexSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule MyApp.TinkexSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    config = Tinkex.Config.new()

    children = [
      {Tinkex.ServiceClient, config: config, name: MyApp.TinkexService}
    ]

    # :one_for_one ensures proper cleanup on shutdown
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### 8. Resource Limits

Set appropriate limits to prevent resource exhaustion:

```elixir
# Limit concurrent requests
{:ok, pool} = Tinkex.SamplingClient.create_async(config,
  base_model: "meta-llama/Llama-3.1-8B",
  max_concurrency: 10  # Application-level limit
)

# Monitor pool capacity
Finch.pool_status(Tinkex.HTTP.Pool)
```

### 9. Health Checks

Implement health checks for your service:

```elixir
defmodule MyApp.HealthCheck do
  def check_tinkex do
    config = Tinkex.Config.new()

    case Tinkex.ServiceClient.start_link(config: config) do
      {:ok, service} ->
        case Tinkex.ServiceClient.create_rest_client(service) do
          {:ok, rest} ->
            # Simple list query to verify connectivity
            case Tinkex.RestClient.list_sessions(rest, limit: 1, timeout: 5_000) do
              {:ok, _} ->
                GenServer.stop(service)
                {:ok, :healthy}
              {:error, error} ->
                GenServer.stop(service)
                {:error, error}
            end
          {:error, error} ->
            GenServer.stop(service)
            {:error, error}
        end
      {:error, error} ->
        {:error, error}
    end
  end
end
```

### 10. Logging and Debugging

Configure appropriate log levels:

```elixir
# Development
config :logger, level: :debug

# Production
config :logger, level: :info

# Enable request logging in development
config :tinkex, log_requests: true  # If implemented
```

## Complete Examples

### Basic Configuration

```elixir
# Minimal setup using environment variables
config = Tinkex.Config.new()

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service,
  base_model: "meta-llama/Llama-3.1-8B"
)
```

### Multi-Tenant SaaS Application

```elixir
defmodule MyApp.TenantConfig do
  @spec for_tenant(String.t()) :: Tinkex.Config.t()
  def for_tenant(tenant_id) do
    tenant = MyApp.Tenants.get!(tenant_id)

    Tinkex.Config.new(
      api_key: tenant.tinkex_api_key,
      base_url: tenant.tinkex_base_url || default_base_url(),
      http_pool: :"tenant_#{tenant_id}_pool",
      timeout: tenant.request_timeout_ms || 120_000,
      user_metadata: %{
        tenant_id: tenant_id,
        tier: tenant.subscription_tier,
        environment: config_env()
      }
    )
  end

  defp default_base_url do
    "https://tinker.thinkingmachines.dev/services/tinker-prod"
  end
end

# Usage
config = MyApp.TenantConfig.for_tenant("tenant-123")
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
```

### High-Throughput Batch Processing

```elixir
defmodule MyApp.BatchProcessor do
  def process_batch(prompts) do
    config = Tinkex.Config.new(
      timeout: 60_000,
      max_retries: 3,
      user_metadata: %{
        batch_id: Ecto.UUID.generate(),
        batch_size: length(prompts)
      }
    )

    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service,
      base_model: "meta-llama/Llama-3.1-8B"
    )

    params = %Tinkex.Types.SamplingParams{
      max_tokens: 64,
      temperature: 0.7
    }

    # Process in parallel with Task.async_stream
    results =
      prompts
      |> Task.async_stream(
        fn prompt ->
          {:ok, model_input} = Tinkex.Types.ModelInput.from_text(prompt,
            model_name: "meta-llama/Llama-3.1-8B"
          )

          {:ok, task} = Tinkex.SamplingClient.sample(sampler, model_input, params)
          Task.await(task, 120_000)
        end,
        max_concurrency: 50,
        timeout: 180_000
      )
      |> Enum.to_list()

    GenServer.stop(service)
    results
  end
end
```

### Development with Local Mock Server

```elixir
# config/dev.exs
config :tinkex,
  api_key: "tml-dev-key",
  base_url: "http://localhost:4000",
  timeout: 5_000,
  max_retries: 0,  # Fail fast in development
  heartbeat_interval_ms: 60_000

# Usage remains the same
config = Tinkex.Config.new()
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
```

## Troubleshooting

### Pool Mismatch Warning

```
Config base_url differs from Application config.
Requests will use Finch's default pool.
```

**Cause**: Your runtime `base_url` doesn't match the URL configured in `Tinkex.Application`.

**Solution 1**: Align base URLs
```elixir
# config/config.exs
config :tinkex, base_url: "https://custom.api.com"

# Runtime
config = Tinkex.Config.new(base_url: "https://custom.api.com")
```

**Solution 2**: Suppress warning in multi-tenant scenarios
```elixir
config :tinkex, suppress_base_url_warning: true
```

**Solution 3**: Create custom pools
```elixir
# Disable automatic pool
config :tinkex, enable_http_pools: false

# Create your own pools in application supervisor
{Finch, name: :custom_pool, pools: %{default: [...]}}
```

### Timeout Issues

See `docs/guides/troubleshooting.md` for detailed timeout debugging.

### API Key Not Found

```
api_key is required. Pass :api_key option or set TINKER_API_KEY env var
```

**Solution**: Set the environment variable
```bash
export TINKER_API_KEY="tml-your-key-here"
```

Or pass explicitly:
```elixir
config = Tinkex.Config.new(api_key: "tml-your-key")
```

## Further Reading

- [Getting Started Guide](getting_started.md) - Basic setup and first requests
- [API Reference](api_reference.md) - Complete API documentation
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [Finch Documentation](https://hexdocs.pm/finch/) - HTTP client details
