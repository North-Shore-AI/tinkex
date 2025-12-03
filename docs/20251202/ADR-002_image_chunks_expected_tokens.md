# ADR-002: Image chunk contract (`expected_tokens`)

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Upstream Python removed `height`, `width`, and `tokens` from both `ImageChunk` and `ImageAssetPointerChunk`; the only advisory count is now `expected_tokens`.
- `.length` now raises unless `expected_tokens` is provided; the backend computes the true token count and can reject mismatches early.
- Elixir still enforces/serializes `height`, `width`, and `tokens` in `lib/tinkex/types/image_chunk.ex` and `image_asset_pointer_chunk.ex`, and uses `tokens` for `.length`. This shape will diverge from the backend and the Python SDK.

## Decision
- Align the Elixir types to the new contract:
  - Drop `height`, `width`, and `tokens` from both structs and wire encoding.
  - Add optional `expected_tokens :: non_neg_integer | nil`; `.length` should raise when it is `nil` to match Python’s guardrail.
  - Keep `format` and `location`/`data` as-is.
- Treat `expected_tokens` as advisory only; do not attempt to derive or trust it if absent.

## Consequences
- Breaking change for any caller constructing image chunks with the old fields; requires a migration guide and version bump.
- Prevents silent undercount/overcount when the backend rejects requests due to token mismatches.
- Avoids sending unused metadata (height/width) to the API.

## Integration plan (Elixir)
1) Update `lib/tinkex/types/image_chunk.ex`:
   - Struct fields: `data`, `format`, `expected_tokens`, `type`.
   - Remove `height/width/tokens` enforcement and encoder output.
   - `length/1` should raise if `expected_tokens` is `nil`.
2) Update `lib/tinkex/types/image_asset_pointer_chunk.ex` similarly: `location`, `format`, `expected_tokens`, `type`, with `length/1` guard.
3) Adjust `Tinkex.Types.ModelInput.chunk_length/1` to use the new `length/1` implementations.
4) Update docs/guides and examples that build image chunks to supply `expected_tokens` (or explain the advisory nature).
5) Add regression tests to ensure JSON shape matches Python and that `length/1` raises when expected tokens are missing.

## Viability
- No known server dependency on height/width; backend computes token counts itself.
- Elixir code currently depends on `tokens` for length; this ADR must be paired with ADR-003 (batch counting) to avoid regressions in chunking logic.
