# Environment parity: Python vs Elixir

Purpose: capture environment variable usage in the Python SDK, compare with Elixir, and highlight gaps that affect parity and operability (including Cloudflare Access per ADR-002).

## Python SDK env vars
- `TINKER_API_KEY`: default API key (AsyncTinker constructor, default headers).
- `TINKER_BASE_URL`: optional override for base URL.
- `TINKER_TAGS`: comma-separated session tags attached at create_session.
- `TINKER_TELEMETRY`: on/off toggle for telemetry pipeline.
- `TINKER_FEATURE_GATES`: feature gate list for sampling client (defaults to `async_sampling`).
- `TINKER_LOG`: logging verbosity (`debug`/`info`).
- `CLOUDFLARE_ACCESS_CLIENT_ID` / `CLOUDFLARE_ACCESS_CLIENT_SECRET`: injected into default headers for Cloudflare Access (see ADR-002).

## Elixir SDK env vars (current)
- `TINKER_API_KEY`: pulled in `Tinkex.Config.new/1` if not provided.
- `TINKER_BASE_URL`: optional override for base URL (falls back to default prod URL).
- `TINKER_TAGS`: comma-separated session tags, defaulting to `["tinkex-elixir"]` when unset.
- `TINKER_FEATURE_GATES`: feature gate list for sampling client.
- `TINKER_TELEMETRY`: on/off toggle for telemetry and reporter startup (defaults to on).
- `TINKER_LOG`: logging verbosity (`debug`/`info`/`warn`/`error`).
- `TINKEX_DUMP_HEADERS`: dumps HTTP headers for debugging.
- `CLOUDFLARE_ACCESS_CLIENT_ID` / `CLOUDFLARE_ACCESS_CLIENT_SECRET`: injected into default headers for Cloudflare Access (ADR-002).
- Centralized in `Tinkex.Env` and fed into `Tinkex.Config` + HTTP headers with inspect/redaction helpers.

## Status
- Python/Elixir env knobs now match (including Cloudflare Access, base URL override, tags, feature gates, log level, telemetry, and dump headers) and are centralized via `Tinkex.Env` per ADR-002.
