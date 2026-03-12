# Phase 5++ Implementation Guide (Ports/Adapters Extract + Manifest Codegen)

## Purpose
Complete the hexagonal refactor by moving all infrastructure into Pristine and leaving Tinkex as a thin, manifest-driven SDK. This guide is the authoritative Phase 5+ execution plan.

## Required Reading
- `docs/20260106/hexagonal-refactor/plan.md`
- `docs/20260106/hexagonal-refactor/CHECKLIST.md`
- `docs/20260106/hexagonal-refactor/REPLACEMENT_MAP.md`
- `AGENTS.md`
- `../../n/pristine/CLAUDE.md`
- Ignore `../../n/pristine/examples/`.

## TDD Workflow (Non-Negotiable)
1. **Red**: Add failing tests for any new behavior (manifest wiring, codegen outputs, header injection, retry policy).
2. **Green**: Implement the smallest change to pass.
3. **Refactor**: Clean up and keep tests green.

## Phase 5: Move Ports/Adapters/Context to Pristine

### 5.1 Ports
- **Source:** `lib/tinkex/ports/*.ex`
- **Target:** `../../n/pristine/lib/pristine/ports/*.ex`
- **Action:** Copy any missing ports into Pristine and update module names to `Pristine.Ports.*`.
- **Note:** If the port already exists in Pristine, reconcile/merge to avoid duplication.
- **Status:** Complete; Tinkex ports removed, Pristine ports aligned.

### 5.2 Adapters
- **Source:** `lib/tinkex/adapters/*.ex`
- **Target:** `../../n/pristine/lib/pristine/adapters/` (see naming map below)
- **Rename Map:**
  - `Tinkex.Adapters.FinchTransport` -> `Pristine.Adapters.Transport.Finch`
  - `Tinkex.Adapters.FoundationRetry` -> `Pristine.Adapters.Retry.Foundation`
  - `Tinkex.Adapters.FoundationCB` -> `Pristine.Adapters.CircuitBreaker.Foundation`
  - `Tinkex.Adapters.FoundationRate` -> `Pristine.Adapters.RateLimit.BackoffWindow`
  - `Tinkex.Adapters.JasonSerializer` -> `Pristine.Adapters.Serializer.JSON`
  - `Tinkex.Adapters.SSEStreaming` -> `Pristine.Adapters.Streaming.SSE`
  - `Tinkex.Adapters.DefaultTelemetry` -> `Pristine.Adapters.Telemetry.Raw`
  - `Tinkex.Adapters.PoolManager` -> `Pristine.Adapters.PoolManager`
  - `Tinkex.Adapters.FoundationSemaphore` -> `Pristine.Adapters.Semaphore.Counting`
- **Status:** Complete; Tinkex adapters removed, Pristine adapters in place.

### 5.3 Context
- **Source:** `lib/tinkex/context.ex`
- **Target:** `../../n/pristine/lib/pristine/core/context.ex` (or a new wrapper module if needed)
- **Action:** Ensure Pristine context exposes all fields used by Tinkex (headers, telemetry, transport, retry, rate limit, pool manager, etc).
- **Status:** Complete; `Tinkex.Config.context/2` now builds `Pristine.Core.Context`.

### 5.4 Update Tinkex Imports
- Replace `Tinkex.*` ports/adapters/context references with `Pristine.*`.
- Remove any remaining `Tinkex.Ports.*` or `Tinkex.Adapters.*` references.
- **Status:** Complete; `Tinkex.Config` now uses `Pristine.*` adapters and context.

## Phase 5: Manifest Wiring

### 5.5 Ensure Full Manifest Coverage
- Add all API endpoints from `REPLACEMENT_MAP.md` to `lib/tinkex/manifest.yaml`.
- Include endpoint IDs, methods, paths, and stream settings.
- Define retry policies, circuit breaker options, and pool types.
- Ensure types are defined for request/response schemas where applicable.
- **Status:** Complete; manifest is JSON content stored in `lib/tinkex/manifest.yaml`.
- **Tooling:** `scripts/manifest_update.exs` can be used to re-sync types/endpoints.

### 5.6 Test Targets (Red)
- Endpoint mapping tests (IDs -> correct path/method).
- Retry policy + Retry-After handling tests.
- Streaming status handling tests.
- Multipart handling tests.

## Phase 6: Codegen + Cleanup

### 6.1 Generate Client
```
mix pristine.generate --manifest lib/tinkex/manifest.yaml --output lib/tinkex/generated --namespace Tinkex.Generated
```

### 6.2 Remove Infrastructure from Tinkex
Delete from Tinkex (after successful generation):
- `lib/tinkex/ports/`
- `lib/tinkex/adapters/`
- `lib/tinkex/context.ex`
- **Status:** Complete; Tinkex now contains only domain + config/env/error + generated code.

### 6.3 Keep Domain-Specific Code Only
- `lib/tinkex/domain/` (tokenizer, byte estimator, model input)
- `lib/tinkex/config.ex`
- `lib/tinkex/error.ex`
- `lib/tinkex/types/` (domain-specific)

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

## Progress Tracking
- Update `AGENTS.md` after each phase.
- Check off items in `docs/20260106/hexagonal-refactor/CHECKLIST.md` as they complete.
