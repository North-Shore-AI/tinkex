# Hexagonal Refactor Phase 5+ (Pristine Extract + Manifest Codegen)

## Goal
Make Tinkex a thin, manifest-driven SDK and move all general infrastructure into Pristine. The end state is ~200-500 lines of handwritten, domain-specific Tinkex code plus generated API client code from the manifest.

## Required Reading (Do This First)
1. `docs/20260106/hexagonal-refactor/plan.md`
2. `docs/20260106/hexagonal-refactor/CHECKLIST.md`
3. `docs/20260106/hexagonal-refactor/REPLACEMENT_MAP.md`
4. `AGENTS.md` (or `CLAUDE.md` if present)
5. `../../n/pristine/CLAUDE.md`
6. Ignore `../../n/pristine/examples/` entirely.

## Current State Summary
- Phase 1-4 are complete: Foundation/Sinter/multipart_ex integrated, ports/adapters created, domain modules moved, and Phase 4 stabilization verified.
- Phase 5-6 are largely complete: ports/adapters/context are removed from Tinkex and live in Pristine, and a manifest-driven client is generated.
- Tinkex uses `lib/tinkex/manifest.ex` + `lib/tinkex/manifest.yaml` (JSON content) and `lib/tinkex/generated/` (namespace `Tinkex.Generated`).
- `Tinkex.Config.context/2` builds `Pristine.Core.Context`, and `Tinkex.Config.client/2` returns `%Tinkex.Generated.Client{}`.
- Hand-written Tinkex code is now limited to config/env/error + domain utilities.

## Architecture Targets
- **Pristine** owns: ports, adapters, context, pipeline, runtime, streaming, retry, circuit breaker, rate limit, serialization, telemetry, multipart.
- **Tinkex** owns: config/env, error types, domain-specific utilities (tokenizer/byte estimation/model input), manifest + generated client code.

## Phase 5+ Checklist (High-Level)
1. **Move/Align Ports & Adapters**: Ensure Pristine contains all port/adapters created in Phase 3 and that module names reflect `Pristine.*` naming.
2. **Update Tinkex Imports**: Replace any Tinkex ports/adapters/context usage with Pristine equivalents.
3. **Manifest Wiring**: Ensure the manifest defines all endpoints, retry policies, circuit breaker settings, pools, and types. Use explicit endpoint IDs from `REPLACEMENT_MAP.md`.
4. **Codegen**: Run `mix pristine.generate --manifest lib/tinkex/manifest.yaml --output lib/tinkex/generated --namespace Tinkex.Generated` and validate generated APIs.
5. **Cleanup**: Delete `lib/tinkex/ports/`, `lib/tinkex/adapters/`, `lib/tinkex/context.ex` (moved to Pristine).
6. **Prune Tests**: Remove legacy API/CLI/recovery tests; keep config/env/error/domain/type tests.

## TDD Workflow (Required)
Use Red-Green-Refactor for any new behavior:
1. **Red**: Add or update tests that describe the new behavior (endpoint mapping, headers, retries, streaming, codegen API).
2. **Green**: Implement the minimal change to pass tests.
3. **Refactor**: Clean up implementation without changing behavior.

### TDD Targets
- Manifest-driven endpoint resolution (path/query/body type).
- Header construction and secret redaction.
- Retry policy and backoff behavior (429/5xx/Retry-After).
- Streaming status handling (non-2xx returns error).
- Multipart handling (content-type, form fields, file payloads).

## Verification (Must Pass)
From `tinkex/`:
- `mix test`
- `mix test --seed 12345`
- `mix test --seed 99999`
- `mix test --seed 1`
- `mix dialyzer`
- `mix credo --strict`
- `mix compile --warnings-as-errors`
- `mix format`

From `../../n/pristine/`:
- `mix test`
- `mix dialyzer`
- `mix credo --strict`
- `mix compile --warnings-as-errors`
- `mix format`

From `../../n/foundation/`:
- `mix test`
- `mix dialyzer`
- `mix credo --strict`
- `mix compile --warnings-as-errors`
- `mix format`

## Gotchas
- Do not call `System.get_env/1` directly; use `Tinkex.Env`.
- Cloudflare Access headers must be redacted via `Tinkex.Env.mask_secret/1`.
- Manifest files are JSON content stored in `.yaml`; keep valid JSON.
- Ignore `pristine/examples/` entirely.
- Update `AGENTS.md` and `docs/20260106/hexagonal-refactor/CHECKLIST.md` after each phase.

## Deliverables
- `lib/tinkex/manifest.yaml` with all endpoints and types.
- `lib/tinkex/generated/` from Pristine codegen.
- Tinkex reduced to domain-specific code and config + manifest.
