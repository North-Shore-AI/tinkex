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
  cf_access_client_secret: System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
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
  tags: ["staging", "canary"]
)
```

## Redaction and logging

- `Inspect` on `Tinkex.Config` masks the API key and Cloudflare secret.
- HTTP dump logging (`TINKEX_DUMP_HEADERS` or `dump_headers?: true`) redacts `x-api-key` and `cf-access-client-secret`.
- Use `Tinkex.Env.mask_secret/1` to redact other secrets when logging snapshots.
