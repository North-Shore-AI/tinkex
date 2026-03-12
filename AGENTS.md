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

## Hexagonal Refactor Progress (Phase 1-2)

### Changes
- Replaced retry/circuit breaker/rate limiter/semaphores with Foundation modules; removed Tinkex wrappers.
- Replaced NotGiven/Transform with Sinter equivalents; removed Tinkex modules.
- Replaced multipart encoding with `multipart_ex` (`Multipart.Form` + `Multipart.Encoder`); removed `lib/tinkex/multipart/`.

### New module locations
- Retry/backoff: `Foundation.Retry`, `Foundation.Retry.HTTP`, `Foundation.Backoff.Policy`.
- Circuit breaker: `Foundation.CircuitBreaker`, `Foundation.CircuitBreaker.Registry`.
- Rate limiting: `Foundation.RateLimit.BackoffWindow`.
- Semaphores: `Foundation.Semaphore.Counting`, `Foundation.Semaphore.Weighted`.
- NotGiven/Transform: `Sinter.NotGiven`, `Sinter.Transform`.
- Multipart: `Multipart.Form`, `Multipart.Encoder`.

### Commands
- Phase 2 verification: `mix test`, `mix test --seed 12345`, `mix test --seed 99999`, `mix test --seed 1`, `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors`.

### Gotchas
- `mix test` still emits existing warnings about `preferred_cli_env` and test load filters.
- Multipart form serialization uses `nil: :empty` to match prior nil-to-empty-string behavior.
- Log-capture tests should filter by session id to avoid cross-test log noise.
- Local deps are wired via `../../n/{foundation,sinter,multipart_ex}` paths.

### Phase 3 (in progress)
- Added ports under `lib/tinkex/ports/`, adapters under `lib/tinkex/adapters/`, and `lib/tinkex/context.ex` scaffolding.
- Moved domain clients to `lib/tinkex/domain/` with thin wrappers: sampling, training, futures, rest, custom_loss.
- SamplingClient now builds retry/backoff via Context (retry/rate_limiter/semaphore adapters); Context includes `semaphore`.
- Retry port now exposes `build_policy/1` + `build_backoff/1`; added `FoundationSemaphore` adapter + semaphore port.
- Refactored `Tinkex.API` into `lib/tinkex/api/client.ex` with ports/context and removed legacy API layer files.
- Reintroduced `Tinkex.API.Response`, `Tinkex.API.StreamResponse`, `Tinkex.API.Helpers`, `Tinkex.API.Telemetry` as thin wrappers in new files.
- Sampling API streaming now uses Context + Streaming port for SSE parsing.

### Phase 4 (completed)
- Ran `mix test`, `mix test --seed 12345`, `mix test --seed 99999`, `mix test --seed 1`.
- Ran `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors`.
- Verified no infrastructure imports in `lib/tinkex/domain/` (no Finch/Foundation/Jason matches).
- Re-validated Phase 4 suite after API refactor; no new issues observed.

### Phase 4 (re-validated)
- Stabilized ETS-backed registries (Foundation circuit breaker + rate limit) with heir ownership + validity checks.
- Fixed request payload handling (no-body GET), stream error handling, and multipart content-type via Context header changes.
- Restored error categorization defaults and added header dump logging with redaction in `Tinkex.API`.
- Re-ran Phase 4 suite: `mix test`, seeds 12345/99999/1, `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors`.
- Verified pristine + foundation: `mix test`, `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors`.

## Hexagonal Refactor Progress (Phase 5-6)

### Changes
- Removed `lib/tinkex/ports/`, `lib/tinkex/adapters/`, and `lib/tinkex/context.ex`; Tinkex now builds `Pristine.Core.Context` via `Tinkex.Config.context/2`.
- Added manifest-driven client: `lib/tinkex/manifest.yaml` (JSON content) + `lib/tinkex/generated/` (`Tinkex.Generated` namespace).
- Moved domain-only modules to `lib/tinkex/domain/{tokenizer,byte_estimator,model_input}.ex`; removed legacy API/CLI/recovery code.
- Added `Tinkex.Config.client/2` convenience for generated client creation.
- Pruned tests to config/env/error/domain/types; removed legacy API/CLI/telemetry/recovery coverage.
- Simplified tokenizer implementation (no ETS cache; Kimi requires local model/config paths).

### New module locations
- Context: `Pristine.Core.Context` (built via `Tinkex.Config.context/2`).
- Generated API client/resources/types: `lib/tinkex/generated/`.
- Domain-specific code: `lib/tinkex/domain/`.

### Commands
- Regenerate client: `mix pristine.generate --manifest lib/tinkex/manifest.yaml --output lib/tinkex/generated --namespace Tinkex.Generated`
- Phase 6 verification (tinkex): `mix test`, `mix test --seed 12345`, `mix test --seed 99999`, `mix test --seed 1`, `mix dialyzer`, `mix credo --strict`, `mix compile --warnings-as-errors`
- Pristine/foundation verification: run the same suite in `../../n/pristine` and `../../n/foundation`.

### Gotchas
- `manifest.yaml` is JSON; keep it valid JSON even with `.yaml` suffix.
- Kimi tokenization requires `:tiktoken_model_path` + `:tokenizer_config_path` (no HuggingFace download fallback).
- OTel header propagation is optional via `TINKEX_OTEL_PROPAGATE`; headers are injected in `Tinkex.Config`.

## Manifest Reimagining Docs (2026-01-06)

### Changes
- Added manifest design series under `docs/20260106/manifest-reimagining/` with context, surface inventory, feature decomposition, manifest schema proposal, Pristine architecture plan, generation/compat guidance, and TDD plan.
- Added Pristine review + full implementation plan under `docs/20260106/manifest-reimagining/pristine-implementation/`.

### New docs
- `docs/20260106/manifest-reimagining/00_context_and_goals.md`
- `docs/20260106/manifest-reimagining/01_surface_inventory.md`
- `docs/20260106/manifest-reimagining/02_feature_decomposition.md`
- `docs/20260106/manifest-reimagining/03_manifest_schema.md`
- `docs/20260106/manifest-reimagining/04_pristine_architecture.md`
- `docs/20260106/manifest-reimagining/05_generation_and_compat.md`
- `docs/20260106/manifest-reimagining/06_tdd_and_validation.md`
- `docs/20260106/manifest-reimagining/pristine-implementation/plan.md`
