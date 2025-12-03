# 2025-12-02 ADR Index (upstream commit 0622760)

Upstream Python SDK changes pulled on 2025-12-03 are captured here with Elixir parity decisions and integration notes. Each ADR is currently **Draft** until the corresponding changes land in `tinkex`.

- `ADR-001_optimizer_resume.md` — Convenience helpers for loading checkpoints with optimizer state.
- `ADR-002_image_chunks_expected_tokens.md` — Image chunk contract change to `expected_tokens` and removal of width/height/tokens.
- `ADR-003_chunk_counting.md` — Batching/counting heuristics for mixed text/image data.
- `ADR-004_cli_multi_delete.md` — Multi-checkpoint delete CLI UX.
- `ADR-005_retry_timeout.md` — Longer progress timeout (120m) for retries.
- `ADR-006_llama3_tokenizer.md` — Llama 3 tokenizer override update.

Scope note: Version bump in Python (`0.6.3`) is observed but not an ADR-worthy decision; Elixir remains `0.1.13` until we align releases.
