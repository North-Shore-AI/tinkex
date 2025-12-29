# tiktoken_ex Extraction Plan (HF Resolution + Caching)

## Status
- Draft: 2025-12-27
- Target repo: `/home/home/p/g/North-Shore-AI/tiktoken_ex` (existing, not in `/home/home/p/g/n`)
- Source inventory: `lib/tinkex/tokenizer.ex`, `lib/tinkex/huggingface.ex`

## Problem Statement
Tinkex currently owns HuggingFace file resolution, caching, and tokenizer
heuristics that are partly generic and partly product-specific. This inflates
Tinkex and makes `tiktoken_ex` less self-sufficient. We should extract the
**generic** parts (HF file resolution + cache) into `tiktoken_ex`, while keeping
product heuristics (e.g., Llama-3 gating and TrainingClient lookups) in Tinkex.

## Current State Inventory
### In Tinkex
- `lib/tinkex/huggingface.ex`: `resolve_file/4` with cache + `:httpc` fetch.
- `lib/tinkex/tokenizer.ex`:
  - ETS-based tokenizer cache
  - Model-id heuristics (Llama-3, repo trimming)
  - Kimi-specific HF downloads via `Tinkex.HuggingFace`

### In tiktoken_ex
- `lib/tiktoken_ex/encoding.ex`: BPE + regex tokenization
- `lib/tiktoken_ex/kimi.ex`: Kimi-specific `pat_str` translation and
  `from_hf_files/1` (local file paths only)

## Extraction Decision
- **Move to tiktoken_ex**: HuggingFace file resolution + caching (generic).
- **Keep in Tinkex**: Model-id heuristics and TrainingClient-based resolution
  (product-specific to Tinkex).

## Proposed Additions to tiktoken_ex
### `TiktokenEx.HuggingFace` (generic)
- `resolve_file(repo_id, revision, filename, opts)` -> cached local path.
- `fetch_file/4` uses `:httpc` by default; allow `:fetch_fun` injection.
- Cache root: `:filename.basedir(:user_cache, "tiktoken_ex")`.
- Sanitized repo ids to prevent path traversal.
- Atomic writes: download to temp file then rename.

### `TiktokenEx.Kimi.from_hf_repo/2`
- `from_hf_repo(repo_id, opts)`:
  - Resolve `tiktoken.model` + `tokenizer_config.json` via `TiktokenEx.HuggingFace`.
  - Delegate to existing `from_hf_files/1`.

### Optional `TiktokenEx.Cache`
- ETS cache for `TiktokenEx.Encoding` keyed by `{repo_id, revision, pat_str}`.
- Opt-in via `TiktokenEx.Cache.get_or_load/2`.

## Tinkex Refactor Plan
1. Replace `Tinkex.HuggingFace` usage with `TiktokenEx.HuggingFace`.
2. Remove `lib/tinkex/huggingface.ex` once migration completes.
3. Keep model-id heuristics inside `Tinkex.Tokenizer` (still needed for
   TrainingClient and Llama-3 gating).
4. Optionally replace Tinkex ETS cache with `TiktokenEx.Cache` when mature.

## Testing Plan
- No network in tests: inject `:fetch_fun` and use local fixtures.
- Cache tests: existing file short-circuits download.
- Concurrency tests: simultaneous resolve calls do not corrupt cache.
- Path sanitization tests.

## Risks and Mitigations
- **Dependency creep**: keep `tiktoken_ex` dependency-free by using `:httpc`.
- **Breaking changes**: add new APIs without changing existing `from_hf_files/1`.
- **Cache corruption**: use temp file + rename for atomic writes.

## Open Questions
- Should `TiktokenEx.HuggingFace` support auth tokens for private repos?
- Do we want to share cache with `huggingface_hub` if it exists later?
- Should `TiktokenEx.Cache` live in a separate optional app?
