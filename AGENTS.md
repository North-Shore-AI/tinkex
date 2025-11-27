# Agent Notes: Environment Handling & Parity

## Overview
- Elixir now has a centralized env module: `lib/tinkex/env.ex`.
- Purpose: avoid scattered `System.get_env/1`; normalize values, support parity with Python SDK env knobs, and mask secrets.

## Usage
- Prefer `Tinkex.Env` helpers instead of `System.get_env/1`.
- For defaults in config: use `Tinkex.Config.new/1` (wired to `Tinkex.Env` for API key, base_url, telemetry toggle, tags/feature gates, dump-headers flag, log level, Cloudflare Access creds).
- HTTP headers: build from config; CF headers come from config (env → app config → opts precedence). Redact CF secret in any dumps.

## Env knobs (Python parity)
- API/URL: `TINKER_API_KEY`, `TINKER_BASE_URL`
- Session tags: `TINKER_TAGS`
- Feature gates: `TINKER_FEATURE_GATES`
- Telemetry toggle: `TINKER_TELEMETRY`
- Logging level: `TINKER_LOG`
- Debug headers: `TINKEX_DUMP_HEADERS`
- Cloudflare Access: `CLOUDFLARE_ACCESS_CLIENT_ID`, `CLOUDFLARE_ACCESS_CLIENT_SECRET`

## Precedence
- opts > app config > env (via `Tinkex.Env`) > built-in defaults.

## Do/Don’t
- Do: add new env-driven behavior via `Tinkex.Env`; mask secrets using `Tinkex.Env.mask_secret/1`.
- Do: update header redaction when introducing new secrets.
- Don’t: call `System.get_env/1` directly in new code.

## Testing
- `test/tinkex/env_test.exs` covers normalization/redaction.
- Add precedence/header injection tests when touching config/HTTP layers.

## Supertester testing standards
- Use `Supertester.ExUnitFoundation` with isolation (`:full_isolation` etc.) for tests that start processes/supervisors; avoid `async: false` unless necessary.
- Avoid `Process.sleep/1`; prefer Supertester sync helpers (`cast_and_sync/2`, `setup_isolated_genserver/3`, `setup_isolated_supervisor/3`).
- For concurrent/process-heavy scenarios, use `Supertester.ConcurrentHarness` (supports chaos/perf/mailbox hooks) or `MessageHarness` for mailbox tracing.
- Ensure supervised children are started via `start_supervised/1` or Supertester helpers to prevent name clashes; clean up with provided teardown.
- Capture telemetry/logs deterministically (e.g., attach handlers, use `capture_log`) instead of timing assumptions.
