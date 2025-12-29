# tiktoken_ex Extraction Prompt (Library-Only)

## Goal
Extract generic HuggingFace file resolution and caching from Tinkex into the
existing `tiktoken_ex` repo. Use TDD.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/tiktoken-extraction/docs.md
- /home/home/p/g/North-Shore-AI/tiktoken_ex/README.md
- /home/home/p/g/North-Shore-AI/tiktoken_ex/mix.exs
- /home/home/p/g/North-Shore-AI/tiktoken_ex/CHANGELOG.md
- /home/home/p/g/North-Shore-AI/tiktoken_ex/lib/tiktoken_ex.ex
- /home/home/p/g/North-Shore-AI/tiktoken_ex/lib/tiktoken_ex/encoding.ex
- /home/home/p/g/North-Shore-AI/tiktoken_ex/lib/tiktoken_ex/kimi.ex
- /home/home/p/g/North-Shore-AI/tiktoken_ex/test

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tiktoken_ex`.
- Do not modify any other repo (including Tinkex).
- Implement HuggingFace resolution + cache as described.
- Add `from_hf_repo/2` for Kimi and optional ETS encoding cache.
- Use TDD: add tests before behavior changes; no network in tests (inject fetchers).
- Update `README.md` and any docs/guides in the repo.
- Bump version to the next `0.x++.y` in `mix.exs` and `README.md`.
- Add a `CHANGELOG.md` entry for 2025-12-27.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
