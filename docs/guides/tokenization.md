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

## Incremental prompt building

For scenarios where you build prompts token-by-token or combine text with images,
use the builder helpers:

```elixir
alias Tinkex.Types.{ModelInput, EncodedTextChunk, ImageChunk}

# Start empty and append chunks
input =
  ModelInput.empty()
  |> ModelInput.append(%EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"})
  |> ModelInput.append(ImageChunk.new(image_bytes, :png, expected_tokens: 256))
  |> ModelInput.append(%EncodedTextChunk{tokens: [4, 5], type: "encoded_text"})

# Or build token-by-token (extends last text chunk when possible)
input =
  ModelInput.empty()
  |> ModelInput.append_int(101)   # creates new EncodedTextChunk
  |> ModelInput.append_int(102)   # extends same chunk → [101, 102]
  |> ModelInput.append_int(103)   # extends same chunk → [101, 102, 103]

# After an image, append_int creates a new text chunk
input =
  ModelInput.from_ints([1, 2])
  |> ModelInput.append(ImageChunk.new(img, :png, expected_tokens: 10))
  |> ModelInput.append_int(99)    # new chunk after image

ModelInput.to_ints(input)  # raises if input contains image chunks
ModelInput.length(input)   # total tokens (requires expected_tokens on images)
```

## TensorData conversions

`TensorData` wraps numerical arrays for the training API. Convert to/from Nx tensors:

```elixir
alias Tinkex.Types.TensorData

# From Nx tensor (casts to backend-compatible dtypes)
tensor = Nx.tensor([1.0, 2.0, 3.0])
td = TensorData.from_nx(tensor)

# Back to Nx
tensor = TensorData.to_nx(td)

# Get flat list (Python parity)
TensorData.tolist(td)  # => [1.0, 2.0, 3.0]
```
