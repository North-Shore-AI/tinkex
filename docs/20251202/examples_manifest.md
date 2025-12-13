# Examples Plan (2025-12-02 refresh)

## Goals
- All runnable examples hit the live Tinker API (no mocks/fakes).
- Only required env var: `TINKER_API_KEY`. Everything else is optional with sensible defaults.
- Cover new behaviors: multimodal image inputs, optimizer resume helper, CLI multi-delete UX, retry defaults, and Llama-3 tokenizer override.
- Default checkpoint path: cache the first available `tinker://` path at `tmp/checkpoints/default.path` (gitignored).

## Coverage
- **Multimodal (image + text)**: `examples/multimodal_resume_and_cleanup.exs`
  - Loads a bundled PNG (`examples/assets/vision_sample.png`) by default (override via `TINKER_IMAGE_PATH`), builds a mixed `ModelInput`, and sends a live sampling request when a vision-capable model is advertised.
  - `expected_tokens` can be supplied via `TINKER_IMAGE_EXPECTED_TOKENS` when you know the backend's image tokenization for that asset (otherwise omit it to avoid mismatches).
  - Uses `Config.new/0` (pulls `TINKER_API_KEY` from env), picks a vision-capable model from live capabilities when available, and logs/skips sampling if none are advertised (override via `TINKER_BASE_MODEL` to force a known vision model).
- **Optimizer resume helper**: same example calls `ServiceClient.create_training_client_from_state_with_optimizer/3` using:
  - `TINKER_CHECKPOINT_PATH` env override, else cached path from `tmp/checkpoints/default.path`, else first checkpoint from `RestClient.list_user_checkpoints/2`. Cache is written back to the same gitignored file.
- **CLI multi-delete (live)**: `examples/checkpoint_multi_delete_live.exs` saves two checkpoints via `save_state/2`, caches their paths under `tmp/checkpoints/default.path`, then deletes both in one CLI invocation (`--yes` avoids interactive confirmation).
- **Tokenizer override (live)**: `examples/llama3_tokenizer_override_live.exs` runs a live Llama-3 sample, prints the resolved tokenizer id (`thinkingmachineslabinc/meta-llama-3-tokenizer`), and shows encode/decode on the prompt/output.
- **Retry defaults**: examples rely on `Config.new/0` so the 120m progress timeout and uncapped retries apply automatically to clients.

## Requirements
- `TINKER_API_KEY` must be set; all other envs optional.
- `examples/run_all.sh` continues to check for the API key only.
- Assets: `examples/assets/vision_sample.png` (32x32 PNG) for multimodal sampling (override via `TINKER_IMAGE_PATH`).
- Checkpoint cache dir: `tmp/checkpoints/` (already gitignored).

## Notes
- If no checkpoints exist for the account, the optimizer-resume portion of the multimodal example logs and skips instead of failing.
- Sampling outputs tokens for visibility without requiring decode; users can layer `Tokenizer.decode/3` if desired.***
