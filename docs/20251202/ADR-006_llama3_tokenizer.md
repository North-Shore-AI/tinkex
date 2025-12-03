# ADR-006: Llama-3 tokenizer override update

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Python changed the Llama-3 tokenizer override from `baseten/Meta-Llama-3-tokenizer` to `thinkingmachineslabinc/meta-llama-3-tokenizer` to avoid gating.
- Elixir used `@llama3_tokenizer "baseten/Meta-Llama-3-tokenizer"` in `lib/tinkex/tokenizer.ex`, returned whenever `model_name` starts with `"meta-llama/Llama-3"`.
- Mismatch may lead to gated downloads or inconsistent tokenization behavior relative to Python. This ADR updates the override to the ungated repo.

## Decision
- Update the override constant to `thinkingmachineslabinc/meta-llama-3-tokenizer` and keep the same heuristic trigger (`meta-llama/Llama-3*` model names).
- Preserve other tokenizer heuristics (two-slash fallback, explicit `tokenizer_id` from model info).

## Consequences
- Aligns tokenization across SDKs and reduces risk of gated model fetches.
- Requires updating tests that assert the override string and clearing any cached tokenizer artifacts if the repo name differs.

## Integration plan (Elixir)
1) Change `@llama3_tokenizer` in `lib/tinkex/tokenizer.ex` to the new repo name.
2) Update tests (if any) that assert the heuristic output for Llama-3 models.
3) Add a note to docs/CHANGELOG explaining the override change and advising users to clear cached tokenizers if necessary.

## Viability
- Simple constant change; no server-side impact.
- Need to verify the new tokenizer repo is accessible in the deployment environment; otherwise provide a fallback or error message.
