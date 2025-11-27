# Environment handling centralization (Elixir)

Objective: avoid scattered `System.get_env/1` calls and align with Python env behavior (including Cloudflare per ADR-002). This is a design note; no code changes yet.

## Goals
- Single, auditable source for env-driven defaults.
- Parity with Python env knobs where relevant (API key, base URL, tags, telemetry, feature gates, logging, Cloudflare Access).
- Support config/opts overrides while keeping env as a fallback.
- Keep secrets masked in logs/inspect.

## Proposed shape
- Introduce `Tinkex.Env` (or `Tinkex.Config.Env`) module responsible for:
  - Reading known env vars with defaults and normalization.
  - Returning a struct/map used by `Tinkex.Config.new/1` to seed defaults.
  - Providing helpers for headers (e.g., Cloudflare Access) so HTTP layer doesn’t call `System.get_env/1` directly.
- Extend `Tinkex.Config` to include CF credentials and optional default headers, fed by `Tinkex.Env`.
- Update `Tinkex.API` header builder to consume config/default headers, not env directly.
- Centralize telemetry toggle reading (TINKER_TELEMETRY) into this module; reuse in telemetry/reporter.

## Env surface to cover (from Python)
- `TINKER_API_KEY`
- `TINKER_BASE_URL`
- `TINKER_TAGS`
- `TINKER_TELEMETRY`
- `TINKER_FEATURE_GATES`
- `TINKER_LOG`
- `CLOUDFLARE_ACCESS_CLIENT_ID` / `CLOUDFLARE_ACCESS_CLIENT_SECRET` (ADR-002)

## Transition plan (high level)
1. Add `Tinkex.Env` with read/normalize functions and tests.
2. Refactor `Tinkex.Config.new/1` to source defaults from `Tinkex.Env` (opts/app config still take priority).
3. Add config fields for CF headers (per ADR-002 option 2) and default headers; update header builder to consume config.
4. Replace direct `System.get_env/1` usages (telemetry, dump headers) with calls into `Tinkex.Env`.
5. Document env knobs and parity matrix; add tests to assert redaction and precedence (opts > app config > env > defaults).

## Notes on ADR-002 (Cloudflare)
- ADR-002 recommends config-based CF header support with env fallback. Centralizing env reads supports that plan and avoids new ad hoc `System.get_env` calls.
- Ensure CF secrets are redacted in logs/inspect and in `Tinkex.API` header redaction.

## Testing considerations
- Table-driven tests for env precedence and redaction.
- Header injection tests using captured telemetry/request metadata.
- Ensure no global env mutations leak across tests (use setup/teardown or sandboxed env helpers).
