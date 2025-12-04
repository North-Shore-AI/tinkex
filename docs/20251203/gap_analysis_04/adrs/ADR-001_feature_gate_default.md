# ADR-001: Feature gate default parity (`TINKER_FEATURE_GATES`)

Status: Proposed  
Date: 2025-12-03  
Owners: Elixir SDK parity

## Context
- Python `SamplingClient` seeds `feature_gates` with `{"async_sampling"}` when the env var is unset (`TINKER_FEATURE_GATES` defaults to `"async_sampling"`).
- Tinkex currently leaves `feature_gates` empty unless explicitly set (`Tinkex.Env.feature_gates/1` → `[]`, `Tinkex.Config` carries that through). This diverges from Python and could disable backend feature toggles the server expects to see by default.
- We already normalize env access via `Tinkex.Env` and merge through `Tinkex.Config` with the documented precedence (opts > app config > env > defaults).

## Decision
- Align the default feature gate set with Python by seeding `["async_sampling"]` when neither opts nor app config nor env provide a value.
- Keep override behavior intact:
  - `opts[:feature_gates]` wins.
  - App config wins over env.
  - Env (`TINKER_FEATURE_GATES`, comma-separated) wins over the built-in default.
- Continue using `Tinkex.Env` for all env reads; do not introduce ad-hoc `System.get_env/1` calls.

## Consequences
- Parity with Python for sampling behavior and any backend feature toggles tied to `async_sampling`.
- Existing users relying on an implicit empty feature gate set will start sending `["async_sampling"]`; this matches the Python contract but is a behavioral change. Document it in the changelog.

## Action Items
1) Update `Tinkex.Env.feature_gates/1` (or `Tinkex.Config` fallback) to return `["async_sampling"]` when the source is nil/empty.  
2) Add/adjust tests:
   - Env snapshot default includes `"async_sampling"`.
   - Explicit env/app/opts still override the default.  
3) Update docs (`environment_configuration`, changelog) to note the default gate.  
4) Verify sampling client initialization and any queue observers still tolerate the populated default list.
