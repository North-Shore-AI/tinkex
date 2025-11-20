# Getting Started

Follow this guide to install Tinkex, configure credentials, and run your first requests through the CLI or SDK. Examples assume Elixir 1.18+ and a valid `TINKER_API_KEY`.

## Install the SDK

Add the dependency and fetch packages:

```elixir
# mix.exs
def deps do
  [
    {:tinkex, "~> 0.1.0"}
  ]
end
```

```bash
mix deps.get
```

To build the CLI locally:

```bash
MIX_ENV=prod mix escript.build   # emits ./tinkex
# optional: install to PATH
mix escript.install ./tinkex
```

## Configure credentials

Tinkex reads configuration from `Tinkex.Config.new/1`, pulling fallbacks from the application env and environment variables:

- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (defaults to the production base URL)
- Optional per-request overrides: `:timeout`, `:max_retries`, `:http_pool`, `:user_metadata`

```elixir
config =
  Tinkex.Config.new(
    api_key: System.fetch_env!("TINKER_API_KEY"),
    base_url: System.get_env("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod")
  )
```

## First sampling request (SDK)

```elixir
{:ok, _} = Application.ensure_all_started(:tinkex)

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: "Qwen/Qwen2.5-7B")

{:ok, prompt} =
  Tinkex.Types.ModelInput.from_text("Hello there", model_name: "Qwen/Qwen2.5-7B")

params = %Tinkex.Types.SamplingParams{max_tokens: 64, temperature: 0.7, top_p: 0.9}

{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 1)
{:ok, response} = Task.await(task, 10_000)
IO.inspect(response.samples, label: "samples")
```

`SamplingClient.sample/4` returns a `Task.t()` so you can await, stream, or supervise requests alongside other work.

## CLI checkpoints and runs

After `MIX_ENV=prod mix escript.build`, invoke the CLI:

```bash
# Save weights metadata for a base model
./tinkex checkpoint \
  --base-model Qwen/Qwen2.5-7B \
  --rank 32 \
  --output ./checkpoint.json \
  --api-key "$TINKER_API_KEY"

# Generate text with configurable sampling params
./tinkex run \
  --base-model Qwen/Qwen2.5-7B \
  --prompt "Hello there" \
  --max-tokens 64 \
  --temperature 0.7 \
  --num-samples 2 \
  --api-key "$TINKER_API_KEY"
```

Flags to know:

- `--prompt-file <path>` reads a prompt from disk (plain text or JSON array of token IDs).
- `--json` prints the full response payload instead of decoded text.
- `--output <path>` writes generation output to a file.

See `./tinkex checkpoint --help` and `./tinkex run --help` for the full option set, plus the troubleshooting guide for timeout/backoff tips.

## Tokenization helpers

Tinkex wraps the `tokenizers` NIF and caches handles in ETS:

```elixir
{:ok, ids} = Tinkex.Tokenizer.encode_text("Hello", "gpt2")
{:ok, text} = Tinkex.Tokenizer.decode(ids, "gpt2")
{:ok, model_input} = Tinkex.Types.ModelInput.from_text("Chat prompt", model_name: "gpt2")
```

Tokenizer resolution honors metadata from `TrainingClient.get_info/1` if provided and applies the Llama-3 gating workaround automatically.

## What to read next

- API overview: `docs/guides/api_reference.md`
- Troubleshooting tips and common errors: `docs/guides/troubleshooting.md`
- End-to-end training loop: `docs/guides/training_loop.md`
- Tokenization details: `docs/guides/tokenization.md`
