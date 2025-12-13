# Kimi K2 tokenization

MoonshotAI Kimi K2 HuggingFace repositories ship a TikToken-style tokenizer:

- `tiktoken.model` (mergeable ranks)
- `tokenizer_config.json` (special tokens + metadata)

They do **not** ship a HuggingFace `tokenizer.json`, so the standard `tokenizers`
loader cannot be used. Tinkex handles Kimi tokenization via `tiktoken_ex`.

## When `tiktoken_ex` is used

When `Tinkex.Tokenizer` resolves the tokenizer ID to `moonshotai/Kimi-K2-Thinking`,
it will:

1. Download (and cache) `tiktoken.model` and `tokenizer_config.json` from HuggingFace
2. Build a `TiktokenEx.Encoding` using Kimi’s `pat_str` (translated to PCRE-compatible syntax)
3. Cache the encoding handle in ETS for reuse

All higher-level APIs (`ModelInput.from_text/2`, CLI `tinkex run`, etc.) continue
to call into `Tinkex.Tokenizer`, so you typically don’t need to change call sites.

## Basic usage

```elixir
{:ok, ids} = Tinkex.Tokenizer.encode("Say hi", "moonshotai/Kimi-K2-Thinking")
{:ok, text} = Tinkex.Tokenizer.decode(ids, "moonshotai/Kimi-K2-Thinking")
```

To build a `ModelInput` (used for sampling and training):

```elixir
{:ok, prompt} =
  Tinkex.Types.ModelInput.from_text("Say hi", model_name: "moonshotai/Kimi-K2-Thinking")
```

## Live sampling (end-to-end)

See `examples/kimi_k2_sampling_live.exs` for a runnable script.

## Offline / controlled caching

To avoid HuggingFace downloads (or to control where files come from), pass file
paths explicitly:

```elixir
opts = [
  tiktoken_model_path: "/path/to/tiktoken.model",
  tokenizer_config_path: "/path/to/tokenizer_config.json"
]

{:ok, ids} = Tinkex.Tokenizer.encode("Say hi", "moonshotai/Kimi-K2-Thinking", opts)
```

To control the download cache location, pass `:cache_dir` (used for HuggingFace
artifact caching):

```elixir
{:ok, ids} =
  Tinkex.Tokenizer.encode("Say hi", "moonshotai/Kimi-K2-Thinking",
    cache_dir: "/tmp/tinkex_cache"
  )
```

## Special tokens

By default, special tokens are recognized (Python parity: `allowed_special="all"`).
To treat special tokens as plain text:

```elixir
{:ok, ids} =
  Tinkex.Tokenizer.encode("<|im_end|>", "moonshotai/Kimi-K2-Thinking",
    allow_special_tokens: false
  )
```

