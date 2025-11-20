# Tokenization Guide

Tinkex ships a thin wrapper around HuggingFace `tokenizers` for converting plain
text to token IDs. The helpers return tuples (`{:ok, ...} | {:error, ...}`) to
keep error handling explicit; use the bang variants if you prefer exceptions.

## Encoding text

```elixir
{:ok, ids} = Tinkex.Tokenizer.encode_text("hello", "gpt2")
# or, with training client metadata-driven resolution:
# {:ok, ids} = Tinkex.Tokenizer.encode_text("hello", "gpt2", training_client: training_client)
```

## Building ModelInput for training or sampling

Use `Tinkex.Types.ModelInput.from_text/2` to prepare prompts or training data:

```elixir
{:ok, prompt} =
  Tinkex.Types.ModelInput.from_text("Translate to French: hello", model_name: "gpt2")

datum = %Tinkex.Types.Datum{
  model_input: prompt,
  loss_fn_inputs: %{target_tokens: [/* labels */]}
}
```

If you prefer to raise on errors, call `ModelInput.from_text!/2` with the same
options. Chat templates are **not** applied by the SDK—provide the fully
formatted text you want to tokenize.
