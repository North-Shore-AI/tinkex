# Multimodal support viability (Python vs Elixir)

## What Python is doing today
- Types: `ModelInputChunk` is a discriminator union of `EncodedTextChunk`, `ImageChunk`, and `ImageAssetPointerChunk` (`src/tinker/types/model_input_chunk.py`).
- Image payloads:
  - `ImageChunk` stores bytes, base64-serializes on output, decodes base64 on input, and requires `expected_tokens` for `.length` (`src/tinker/types/image_chunk.py`).
  - `ImageAssetPointerChunk` carries `location`, `format`, optional `expected_tokens`; `.length` raises if missing (`src/tinker/types/image_asset_pointer_chunk.py`).
- Requests: `Datum` embeds `ModelInput` and `loss_fn_inputs`; forward/backward requests wrap lists of `Datum` and flow through `client.training.forward/forward_backward` with no text-only gating.
- Batching/counting: `TrainingClient._estimate_number_count_in_chunk` counts images by `len(data)` (base64 string length) and image pointers by `len(location)`, avoiding `chunk.length` for images; other chunks use `.length` (`src/tinker/lib/public_interfaces/training_client.py`).
- Sampling: `SamplingClient` uses the same `types.ModelInput` surface, so multimodal inputs are accepted on the sampling path as well.
- Net: Multimodal is fully wired end-to-end in Python (type system, serialization, batching, and client calls).

## Elixir state vs. Python
- Types still expose the old shape: `ImageChunk` / `ImageAssetPointerChunk` include `height`, `width`, `tokens`, and use `tokens` for `.length` (`lib/tinkex/types/image_chunk.ex`, `image_asset_pointer_chunk.ex`). No `expected_tokens` field exists.
- Batching relies on `ModelInput.length/1` → chunk `.length` (uses `tokens`), so once we drop `tokens` the current logic would crash or miscount.
- Serialization currently sends height/width/tokens; backend + Python now expect `expected_tokens` only and will compute true token counts server-side.
- Tokenizer override and retry defaults also lag Python (captured in ADR-005/006); not blocking for multimodal but worth aligning.

## Integration viability
- Server-side shape matches Python; Elixir can safely align by implementing ADR-002 (image chunks) and ADR-003 (counting heuristics). No backend changes needed.
- Transport already handles arbitrary structs via `Tinkex.Transform`; once the structs match Python, JSON will align.
- Sampling and training client entry points already accept `ModelInput`, so no public API expansion is required—just type/schema updates and counting fixes.

## Recommended next steps
1) Apply ADR-002: remove height/width/tokens, add `expected_tokens`, update `.length/1` to raise if nil; adjust JSON encoders accordingly.
2) Apply ADR-003: mirror Python counting in `Tinkex.TrainingClient` (image chunks by `byte_size(data)` of base64 string; asset pointers by `byte_size(location)`; others by `.length`).
3) Update `Tinkex.Types.ModelInput.length/1` to either use the new counting helper or handle `expected_tokens` consistently.
4) Update docs/examples to pass `expected_tokens` (advisory) and explain server-side validation; add regression tests with mixed text + image chunks through forward/backward and sampling.
5) After type changes, run a quick wire test against the API with image data to confirm backend acceptance using the Elixir client.
