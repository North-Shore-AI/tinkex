# Agent Execution Prompt: Implement ADRs 001-006 + Operational Addendum

**Run from repo root (`/home/home/p/g/North-Shore-AI/tinkex`).**  
Primary codebase: Elixir SDK (current version 0.1.13). Python SDK lives in `./tinker` for reference.

## Required Reading (pre-work)
- Project docs:
  - `./docs/20251202/00_INDEX.md`
  - `./docs/20251202/ADR-001_optimizer_resume.md`
  - `./docs/20251202/ADR-002_image_chunks_expected_tokens.md`
  - `./docs/20251202/ADR-003_chunk_counting.md`
  - `./docs/20251202/ADR-004_cli_multi_delete.md`
  - `./docs/20251202/ADR-005_retry_timeout.md`
  - `./docs/20251202/ADR-006_llama3_tokenizer.md`
  - `./docs/20251202/multimodal_viability.md`
  - `./docs/20251202/operational_addendum.md`
- Supertester TDD guide: `~/p/g/n/supertester/README.md`
- Reference code (for parity): Python SDK files in `./tinker/src/tinker/...` as cited in ADRs.

## Deliverables (must-haves)
1. **ADR-002 Image schema parity**
   - `lib/tinkex/types/image_chunk.ex`: remove height/width/tokens; add `expected_tokens`; `.length/1` raises if nil; encoder matches Python (data, format, expected_tokens?, type).
   - `lib/tinkex/types/image_asset_pointer_chunk.ex`: same removals; add `expected_tokens`; `.length/1` raises if nil; encoder matches Python.
   - Update any docs/examples that reference old fields.
2. **ADR-003 Counting heuristics**
   - `lib/tinkex/training_client.ex`: add `_estimate_number_count_in_chunk` matching Python (byte_size(data) for ImageChunk, byte_size(location) for ImageAssetPointerChunk, otherwise chunk.length); use it in batching.
   - Align `lib/tinkex/types/model_input.ex` length behavior with the new chunks (no reliance on tokens).
3. **ADR-005 Retry timeout**
   - Set default progress timeout to 120 minutes (7_200_000 ms) in `lib/tinkex/retry_handler.ex` and `lib/tinkex/retry_config.ex`; tests updated.
4. **Operational addendum: retry cap**
   - Align with Python’s time-bounded retries: remove/raise the retry cap so retries continue until progress timeout rather than stopping at 10. Update defaults, logic, and tests accordingly; document behavior.
5. **ADR-006 Tokenizer override**
   - Update Llama-3 tokenizer override to `thinkingmachineslabinc/meta-llama-3-tokenizer` in `lib/tinkex/tokenizer.ex`; update docs/CHANGELOG.
6. **ADR-001 Optimizer resume helper**
   - Add `ServiceClient.create_training_client_from_state_with_optimizer/3` and async variant; document weights-only vs weights+optimizer; keep existing behavior for `create_training_client_from_state/3`.
7. **ADR-004 CLI multi-delete**
   - `lib/tinkex/cli.ex`: accept multiple checkpoint paths for delete, validate all, single confirmation (with count), progress indicator, aggregate/report failures while continuing deletions.
8. **Examples**
   - Add runnable example(s) in `examples/` covering new functionality (at minimum: multimodal input construction with `expected_tokens`, resume with optimizer, CLI multi-delete usage note). Examples must run via `mix run` and require only `TINKER_API_KEY` in env.
   - Update `examples/run_al.sh`, `examples/README.md`, and root `README.md` to include the new example(s).
9. **Versioning & changelog**
   - Bump version in `mix.exs` (x.y.z → x.y.(z+1)) and reflect in README.
   - Add a new changelog entry dated `2025-12-02` summarizing all changes above.

## TDD / Testing Requirements
- Follow `~/p/g/n/supertester/README.md` principles.
- Add/modify tests before code changes when feasible.
- Required test runs (all must pass, no warnings):
  - `mix test`
  - `mix dialyzer` (no dialyzer errors)
  - Any supertester-instructed tasks from the README.
- Ensure no compiler warnings.

## Implementation Notes
- Schema changes are breaking: update docs/examples accordingly.
- ADR-002 and ADR-003 must land together to avoid crashes.
- Retry behavior: prefer time-bounded (progress-timeout) retries over fixed-attempt caps; adjust defaults/tests to reflect this.
- Keep backward-compatible ergonomics where possible (existing APIs keep working; new helpers add parity).

## Finalization Checklist
- Code + tests updated; all tests passing; no warnings/dialyzer errors.
- Examples runnable with `mix run` and only `TINKER_API_KEY` required.
- Docs updated (README, examples/README, CHANGELOG, any in-tree guides touched by schema/behavior changes).
- Version bumped in `mix.exs` and reflected in README.
- New changelog entry dated `2025-12-02` describing the implemented items.
