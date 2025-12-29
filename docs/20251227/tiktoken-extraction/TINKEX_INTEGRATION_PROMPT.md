# Tinkex Integration Prompt (tiktoken_ex)

## Goal
Refactor Tinkex tokenization to use the completed `tiktoken_ex` HuggingFace
resolver and caching, and remove `Tinkex.HuggingFace`. Use TDD and preserve behavior.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/tiktoken-extraction/docs.md
- /home/home/p/g/North-Shore-AI/tiktoken_ex/README.md
- /home/home/p/g/North-Shore-AI/tiktoken_ex/lib
- /home/home/p/g/North-Shore-AI/tinkex/mix.exs
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/tokenization.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/kimi_k2_tokenization.md
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/huggingface.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer/http_client.ex

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tinkex`.
- Do not modify the `tiktoken_ex` repo.
- Replace `Tinkex.HuggingFace` usage with `TiktokenEx.HuggingFace`.
- Remove `lib/tinkex/huggingface.ex` after replacement.
- Keep model-id heuristics and TrainingClient logic in Tinkex.
- Update `mix.exs` dependency and docs to reference the new library.
- Use TDD: add tests before behavior changes; no network in tests (inject fetchers).
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
