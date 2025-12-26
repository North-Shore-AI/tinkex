# Model Registry Plan (Tinkex)

## Background
- The SDK currently relies on live server capabilities (`/api/v1/get_server_capabilities`) and ad hoc docs lists.
- There is no local registry, no context window metadata, and no consistent place to check model traits.
- We want a lightweight registry that improves discovery and validation without blocking new models.

## Goals
- Provide a single, structured place to store model metadata (context length, training type, architecture, size, features).
- Keep behavior opt-in and non-blocking by default; allow unknown models to pass through.
- Merge multiple sources (built-in list, server capabilities, optional user file) with clear precedence.
- Integrate with ServiceClient, SamplingClient, TrainingClient, and CLI outputs.
- Preserve forward compatibility if the server adds new fields.

## Recommendation (Critical)
- Defer a full registry until the backend or official SDK exposes authoritative model metadata (especially context limits).
- If we build anything now, keep it optional and non-authoritative:
  - No default enforcement.
  - Treat context limits as observations with provenance (not guarantees).
  - Avoid becoming a new "source of truth" that can drift from the server.
  - Keep scope limited to internal troubleshooting needs.

## Non-Goals
- No hard whitelist by default.
- No remote registry service or auto-sync outside of existing API calls.
- No complicated versioning or schema migration system.
- No replacement for server truth; registry is advisory only.

## Design Principles
- Lightweight data model; plain structs and maps.
- Unknown models are allowed; at most warn unless explicitly enforced.
- Registry should never block valid server-side behavior.
- Make it easy to update without code changes (optional file override).

## Proposed Data Model
Introduce `Tinkex.ModelRegistry.ModelSpec`:
- `model_name` (string, required)
- `model_id` (string, optional)
- `training_type` (enum: base|instruction|reasoning|hybrid|vision)
- `architecture` (enum: dense|moe)
- `size` (enum: compact|small|medium|large)
- `max_context_length` (integer, optional, advisory)
- `context_limit_source` (string, optional: "server" | "docs" | "probe" | "manual")
- `context_limit_observed_at` (string, optional ISO8601)
- `features` (list of strings, optional)
- `available?` (boolean, derived from server capabilities)
- `source` (enum: builtin|server|file|override)
- `metadata` (map for any extra fields)

Keep this minimal and tolerate missing fields.

## Registry Sources and Precedence
Registry is built by merging sources in this order:
1) Built-in seed list (static JSON or Elixir map in `priv/`).
2) Server capabilities (`get_server_capabilities`) to mark `available?` and add unknown models.
3) Optional registry file (local JSON, user-provided).
4) Per-call overrides (opts).

Per-model merge rules:
- Non-nil fields from later sources override earlier values.
- Unknown fields go into `metadata`.
- If a model appears only in server capabilities, create a minimal `ModelSpec` with `model_name` and `available?`.

## Registry Behavior (No Hard Whitelist)
Add `model_registry_mode` with three modes:
- `:off` (default): no validation, no warnings.
- `:warn`: log when model is unknown.
- `:enforce`: reject unknown models unless explicitly allowed.

Add per-call override:
- `allow_unknown_model?: true` bypasses enforcement for that call.

This meets the requirement to use models not in the registry.

## Risks / Why Defer
- Context limits appear to be lower on Tinker than official model specs; registry values can mislead.
- Probing limits is slow, expensive, and environment-dependent.
- If clients treat registry values as truth, support complexity increases.

## Integration Points
1) `Tinkex.Config`
   - Add fields:
     - `model_registry` (map of model_name -> ModelSpec)
     - `model_registry_mode` (:off|:warn|:enforce)
   - Use `Tinkex.Env` for env parsing and precedence:
     - `TINKEX_MODEL_REGISTRY_MODE`
     - `TINKEX_MODEL_REGISTRY_PATH`

2) `ServiceClient`
   - When creating training/sampling clients:
     - Look up model in registry.
     - Warn or enforce based on `model_registry_mode`.
   - Provide helper `ServiceClient.refresh_model_registry/1` to re-fetch capabilities.

3) `SamplingClient` and `TrainingClient`
   - Log a warning once per session when using an unknown model (mode :warn).

4) CLI / Examples
   - Optional `tinkex models` command that shows:
     - model_name, availability, max_context_length, training_type, architecture, size.
   - Keep CLI optional to avoid overengineering.

## File Format (Optional User Registry)
JSON array of objects:
```
[
  {
    "model_name": "Qwen/Qwen3-235B-A22B-Instruct-2507",
    "training_type": "instruction",
    "architecture": "moe",
    "size": "large",
    "max_context_length": 32768,
    "features": ["sampling", "training"]
  }
]
```

## API Sketch
- `Tinkex.ModelRegistry.build/1` -> `%{models: %{name => ModelSpec}, sources: [...]}`.
- `Tinkex.ModelRegistry.get/2` -> `{:ok, ModelSpec} | :unknown`.
- `Tinkex.ModelRegistry.known?/2` -> boolean.
- `Tinkex.ModelRegistry.merge/2` -> merge helper for tests.

## Implementation Plan
Phase 1: Core registry
- Add `ModelSpec` struct and registry build/merge functions.
- Add optional seed list in `priv/model_registry.json`.
- Add env parsing in `Tinkex.Env` and config wiring in `Tinkex.Config`.

Phase 2: Integrations
- Wire registry checks into `ServiceClient.create_sampling_client/2` and `create_lora_training_client/3`.
- Add per-call `allow_unknown_model?` override.
- Add warning logging for unknown models in `SamplingClient`/`TrainingClient`.

Phase 3: Docs + optional CLI
- Document registry behavior, env vars, and allow-unknown override.
- Optional CLI command for listing registry contents.

## Test Plan
- Unit tests for registry merge and precedence.
- Integration tests for enforcement modes:
  - `:off` allows unknown.
  - `:warn` logs once.
  - `:enforce` rejects unless override is true.
- Use Supertester isolation for any process tests (ServiceClient/SamplingClient).

## Open Questions
- Should we keep the seed list in `priv/` or inline Elixir map?
- Do we want to expose `max_context_length` in outputs immediately or keep it optional until confirmed?
