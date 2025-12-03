# ADR-003: Chunk counting heuristics for batching

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Python changed `TrainingClient` batching to avoid `chunk.length` for images (since image chunks no longer carry `tokens`):
  - Image chunk count = `len(chunk.data)` (base64 string length).
  - Image asset pointer count = `len(chunk.location)`.
  - Other chunks use their `length`.
- Elixir currently chunks data via `Tinkex.TrainingClient.chunk_data/1` using `estimate_number_count/1`, which calls `Tinkex.Types.ModelInput.length/1`. That, in turn, calls `.length` on each chunk and depends on `tokens` for images (`lib/tinkex/types/image_chunk.ex`, `image_asset_pointer_chunk.ex`).
- With ADR-002 removing `tokens` and making `.length` raise unless `expected_tokens` is set, the current counting logic would either crash or miscount images, leading to incorrect batch sizing.

## Decision
- Mirror Python’s heuristic counting in Elixir:
  - For `%Tinkex.Types.ImageChunk{}`: use `byte_size(data)` (or `String.length/1` on the base64 string) as the estimate.
  - For `%Tinkex.Types.ImageAssetPointerChunk{}`: use `byte_size(location)`.
  - For other chunks: use their `length/1`.
  - Loss inputs remain `length(data)` for lists, as today.
- Keep the existing chunk limits (`@max_chunk_len`, `@max_chunk_number_count`) but ensure they operate on the new estimates so we don’t split batches incorrectly or raise due to missing `expected_tokens`.

## Consequences
- Prevents crashes when `expected_tokens` is absent while still giving a deterministic batching heuristic for images.
- Counting becomes approximate (string length) but matches Python’s behavior and avoids relying on server tokenization at client chunk time.
- Requires test updates that assert the new counting path for image chunks.

## Integration plan (Elixir)
1) Add a private helper (e.g., `_estimate_number_count_in_chunk/1`) in `lib/tinkex/training_client.ex` that pattern matches chunk types and applies the heuristic above.
2) Update `estimate_number_count/1` to iterate over `datum.model_input.chunks` with the new helper instead of `ModelInput.length/1`.
3) Consider updating `ModelInput.length/1` to use the same helper (or delegate) so callers outside the batching path see consistent behavior, while still allowing `.length` to raise for missing `expected_tokens` when explicitly called.
4) Add tests covering mixed text + image inputs to confirm chunk boundaries stay within `@max_chunk_number_count`.

## Viability
- Changes are localized to `lib/tinkex/training_client.ex` (and optionally `lib/tinkex/types/model_input.ex`) with no server impact.
- Depends on ADR-002 to ensure image chunk structs match Python’s shape; otherwise the heuristic cannot pattern match correctly.
