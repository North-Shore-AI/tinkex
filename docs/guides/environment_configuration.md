# Environment Configuration

Centralized environment handling is provided by `Tinkex.Env` and fed into `Tinkex.Config` so runtime options, application config, and env vars stay consistent. This guide lists the supported knobs, defaults, and precedence.

## Precedence

`Tinkex.Config.new/1` resolves values in this order:

1. Runtime options (`Tinkex.Config.new(api_key: ..., dump_headers?: true, ...)`)
2. Application config (`config :tinkex, ...`)
3. Environment variables (via `Tinkex.Env`)
4. Built-in defaults

## Supported environment variables

- `TINKER_API_KEY` (required): API key. Masked in inspect output.
- `TINKER_BASE_URL`: Base URL override. Default: `https://tinker.thinkingmachines.dev/services/tinker-prod`.
- `TINKER_TAGS`: Comma-separated tags. Default: `["tinkex-elixir"]`.
- `TINKER_FEATURE_GATES`: Comma-separated feature gates. Default: `[]`.
- `TINKER_TELEMETRY`: Telemetry toggle (truthy: `1/true/yes/on`, falsey: `0/false/no/off`). Default: `true`.
- `TINKER_LOG`: Log level (`debug` | `info` | `warn` | `warning` | `error`). Default: unset.
- `TINKEX_DUMP_HEADERS`: HTTP dump toggle (same truthy/falsey parsing). Default: `false`; sensitive headers are redacted.
- `TINKEX_PROXY`: Proxy URL for HTTP/HTTPS connections (e.g., `http://proxy.company.com:8080` or `http://user:pass@proxy.company.com:8080`). Default: none.
- `TINKEX_PROXY_HEADERS`: JSON array of proxy headers (e.g., `[["proxy-authorization", "Basic abc123"]]`). Default: `[]`.
- `CLOUDFLARE_ACCESS_CLIENT_ID` / `CLOUDFLARE_ACCESS_CLIENT_SECRET`: Forwarded on every request per ADR-002; secret is redacted in logs/inspect.

`Tinkex.Env.snapshot/0` returns all parsed values; booleans are normalized using the truthy/falsey lists above, and lists are split on commas with trimming.

## Application config example

App config is a stable place to set shared defaults while keeping secrets in env vars:

```elixir
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: System.get_env("TINKER_BASE_URL"),
  tags: System.get_env("TINKER_TAGS"),
  feature_gates: System.get_env("TINKER_FEATURE_GATES"),
  telemetry_enabled?: true,
  log_level: :info,
  dump_headers?: false,
  cf_access_client_id: System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"),
  cf_access_client_secret: System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET"),
  proxy: {:http, "proxy.company.com", 8080, []},
  proxy_headers: [{"proxy-authorization", "Basic " <> Base.encode64("user:pass")}]
```

## Runtime overrides

Pass options to override everything else for a specific client:

```elixir
config = Tinkex.Config.new(
  api_key: "override-key",
  base_url: "https://staging.example.com",
  telemetry_enabled?: false,
  dump_headers?: true,
  log_level: :debug,
  tags: ["staging", "canary"],
  proxy: "http://user:pass@proxy.example.com:8080"
)
```

## Proxy configuration

Tinkex supports HTTP/HTTPS proxies for all network connections. Proxy configuration can be provided through environment variables, application config, or runtime options.

### Environment variable configuration

Set the `TINKEX_PROXY` environment variable to a proxy URL:

```bash
# Without authentication
export TINKEX_PROXY="http://proxy.company.com:8080"

# With authentication (credentials will be converted to proxy-authorization header)
export TINKEX_PROXY="http://user:pass@proxy.company.com:8080"

# HTTPS proxy
export TINKEX_PROXY="https://secure-proxy.company.com:443"
```

For custom proxy headers (e.g., non-Basic authentication):

```bash
export TINKEX_PROXY_HEADERS='[["proxy-authorization", "Bearer token123"], ["custom-header", "value"]]'
```

### Application config

Configure proxy settings in your application config:

```elixir
# config/config.exs
config :tinkex,
  proxy: {:http, "proxy.company.com", 8080, []},
  proxy_headers: [{"proxy-authorization", "Basic " <> Base.encode64("user:pass")}]
```

### Runtime configuration

Override proxy settings at runtime when creating a config:

```elixir
# String URL format (recommended for simplicity)
config = Tinkex.Config.new(
  api_key: "your-key",
  proxy: "http://user:pass@proxy.example.com:8080"
)

# Tuple format (for advanced use cases)
config = Tinkex.Config.new(
  api_key: "your-key",
  proxy: {:http, "proxy.example.com", 8080, []},
  proxy_headers: [{"proxy-authorization", "Basic abc123"}]
)
```

### Proxy format

Proxy can be specified in two formats:

1. **URL string**: `"http://proxy.example.com:8080"` or `"http://user:pass@proxy.example.com:8080"`
   - Scheme must be `http` or `https`
   - Port is optional (defaults to 80 for http, 443 for https)
   - Credentials in URL are automatically converted to `proxy-authorization` header

2. **Tuple format**: `{:http | :https, host :: String.t(), port :: 1..65535, opts :: keyword()}`
   - More control over connection options
   - Use with `proxy_headers` for custom authentication

### How it works

Proxy configuration is passed to Finch's connection pool via the `:conn_opts` option. The proxy settings apply to all HTTP connections made through the Tinkex SDK, including:

- Sampling requests
- Training operations
- Checkpoint downloads
- Session management
- Telemetry and metrics

## Redaction and logging

- `Inspect` on `Tinkex.Config` masks the API key and Cloudflare secret.
- HTTP dump logging (`TINKEX_DUMP_HEADERS` or `dump_headers?: true`) redacts `x-api-key` and `cf-access-client-secret`.
- Use `Tinkex.Env.mask_secret/1` to redact other secrets when logging snapshots.
