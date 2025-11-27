# GAP: TrainingClient Tokenizer Helper

## Status
- **Python**: `TrainingClient.get_tokenizer()` (tinker/src/tinker/lib/public_interfaces/training_client.py:725-741) returns a cached HuggingFace tokenizer for the current model, using model metadata + holder cache.
- **Elixir**: No `Tinkex.TrainingClient.get_tokenizer/1` or helper exists. `lib/tinkex/tokenizer.ex` provides `get_tokenizer_id/3`, `get_or_load_tokenizer/2`, `encode/3`, and `decode/3`, but callers must wire it manually and fetch model info themselves.

## Why It Matters
- **Parity/Migration**: Python users can call `training_client.get_tokenizer()`; Elixir users must orchestrate `TrainingClient.get_info/1` + `Tinkex.Tokenizer.get_tokenizer_id/3` + `get_or_load_tokenizer/2`.
- **DX & Safety**: Without a helper, it is easier to pass inconsistent model names vs. the actual training client’s tokenizer_id. The Llama-3 tokenizer override in `Tinkex.Tokenizer` is unreachable if callers never use the helper.
- **Docs Consistency**: Examples that say “get the tokenizer from the training client” cannot be ported verbatim.

## Evidence
- Elixir training client lacks any tokenizer APIs (grep `get_tokenizer` → no hits in `lib/tinkex/training_client.ex`).
- Tokenizer module comments explicitly say “Used by tokenizer resolution to obtain `model_data.tokenizer_id`,” but the training client does not expose a convenience.

## Proposed Solution (Elixir)
1. **Add Helper**: `TrainingClient.get_tokenizer/2` (opts include `:load_fun` passthrough to `Tokenizer.get_or_load_tokenizer/2`).
   - Internally: call `TrainingClient.get_info/1` to obtain `model_data.tokenizer_id`; fallback to `model_name` heuristics via `Tokenizer.get_tokenizer_id/3`; reuse ETS cache.
2. **Expose Encode/Decode Convenience**:
   - `TrainingClient.encode/3` and `decode/3` thin wrappers around `Tinkex.Tokenizer.encode/3` and `decode/3`, defaulting training_client context.
3. **Docs**:
   - Add examples showing `{:ok, tokenizer} = TrainingClient.get_tokenizer(client)` and `TrainingClient.encode/3`.
4. **Tests**:
   - Unit test with a stubbed `info_fun` returning a tokenizer_id.
   - Test cache reuse and the Llama-3 heuristic path.
   - Ensure errors propagate as `{:error, %Tinkex.Error{}}`.

## Effort
- Estimated ~1 hour including tests and doc updates.
