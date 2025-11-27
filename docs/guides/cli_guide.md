# CLI Reference Guide

Complete reference for the Tinkex command-line interface. The CLI provides a thin wrapper over the SDK for quick checkpoint management, text generation, and API exploration without writing Elixir code.

## Overview

The Tinkex CLI is distributed as an escript executable that bundles the entire application into a single file. It supports three main command groups:

- `checkpoint` - Save and manage model checkpoints
- `run` - Generate text completions and manage training runs
- `version` - Display version information

All commands support a consistent set of global options for API configuration, and most operations return structured output that can be saved to files or piped to other tools.

## Installation

Build the escript from source:

```bash
cd tinkex
MIX_ENV=prod mix escript.build   # emits ./tinkex
```

Optionally install to your PATH:

```bash
mix escript.install ./tinkex     # installs to ~/.mix/escripts
```

Verify the installation:

```bash
./tinkex version
# or if installed:
tinkex version
```

## Global Options

These options are available for all commands that interact with the Tinker API:

- `--api-key <key>` - API key for authentication (required, or set `TINKER_API_KEY` env var)
- `--base-url <url>` - API base URL (defaults to production endpoint)
- `--timeout <ms>` - Request timeout in milliseconds (default: 120000)

Example using global options:

```bash
./tinkex run \
  --api-key "$TINKER_API_KEY" \
  --base-url "https://tinker.thinkingmachines.dev/services/tinker-prod" \
  --timeout 60000 \
  --prompt "Hello"
```

## `tinkex checkpoint` - Checkpoint Management

The `checkpoint` command provides two modes: saving new checkpoints and managing existing ones.

### Save Checkpoints

Create and save a checkpoint for a model configuration:

```bash
./tinkex checkpoint \
  --base-model meta-llama/Llama-3.1-8B \
  --rank 32 \
  --output ./checkpoint.json \
  --api-key "$TINKER_API_KEY"
```

#### Options

**Model Configuration:**
- `--base-model <id>` - Base model identifier (required, e.g., `meta-llama/Llama-3.1-8B`)
- `--model-path <path>` - Local model path (alternative to `--base-model`)

**Output:**
- `--output <path>` - Path to write checkpoint metadata JSON (required)

**LoRA Configuration:**
- `--rank <int>` - LoRA rank (default: 32)
- `--seed <int>` - Random seed for reproducibility
- `--train-mlp` - Enable MLP training (default: true)
- `--train-attn` - Enable attention training (default: true)
- `--train-unembed` - Enable unembedding training (default: true)

#### Checkpoint Metadata Format

The checkpoint command writes a JSON metadata file to the specified `--output` path:

```json
{
  "base_model": "meta-llama/Llama-3.1-8B",
  "model_id": "run-abc123/weights/0001",
  "weights_path": "/path/to/weights",
  "saved_at": "2024-11-26T12:34:56Z",
  "response": {
    "model_id": "run-abc123/weights/0001",
    "path": "/path/to/weights"
  }
}
```

**Note:** The actual model weights are stored on the Tinker service. The local metadata file contains references and timestamps for tracking purposes.

#### Example: Save Checkpoint with Custom LoRA Config

```bash
./tinkex checkpoint \
  --base-model Qwen/Qwen2.5-7B \
  --rank 64 \
  --seed 42 \
  --train-mlp \
  --train-attn \
  --output checkpoints/qwen-lora-64.json \
  --api-key "$TINKER_API_KEY"
```

### List Checkpoints

List all user checkpoints with pagination:

```bash
./tinkex checkpoint list [--limit <int>] [--offset <int>]
```

**Options:**
- `--limit <int>` - Maximum number of checkpoints to return (default: 20)
- `--offset <int>` - Number of checkpoints to skip (default: 0)

**Output Format:**
```
checkpoint-id-1    tinker://run-123/weights/0001
checkpoint-id-2    tinker://run-124/weights/0002
```

**Example:**

```bash
# List first 10 checkpoints
./tinkex checkpoint list --limit 10 --api-key "$TINKER_API_KEY"

# List next page
./tinkex checkpoint list --limit 10 --offset 10 --api-key "$TINKER_API_KEY"
```

### Get Checkpoint Info

Retrieve detailed information about a specific checkpoint:

```bash
./tinkex checkpoint info <tinker_path>
```

**Arguments:**
- `<tinker_path>` - Checkpoint path (e.g., `tinker://run-123/weights/0001`)

**Output:**
```
Base model: meta-llama/Llama-3.1-8B
LoRA: true
LoRA rank: 32
```

**Example:**

```bash
./tinkex checkpoint info tinker://run-abc123/weights/0001 \
  --api-key "$TINKER_API_KEY"
```

### Publish Checkpoint

Make a checkpoint publicly accessible:

```bash
./tinkex checkpoint publish <tinker_path>
```

**Example:**

```bash
./tinkex checkpoint publish tinker://run-123/weights/0001 \
  --api-key "$TINKER_API_KEY"
# Output: Published tinker://run-123/weights/0001
```

### Unpublish Checkpoint

Remove public access from a checkpoint:

```bash
./tinkex checkpoint unpublish <tinker_path>
```

**Example:**

```bash
./tinkex checkpoint unpublish tinker://run-123/weights/0001 \
  --api-key "$TINKER_API_KEY"
# Output: Unpublished tinker://run-123/weights/0001
```

### Delete Checkpoint

Permanently delete a checkpoint:

```bash
./tinkex checkpoint delete <tinker_path>
```

**Warning:** This operation is irreversible. Ensure you have backups if needed.

**Example:**

```bash
./tinkex checkpoint delete tinker://run-old/weights/0001 \
  --api-key "$TINKER_API_KEY"
# Output: Deleted tinker://run-old/weights/0001
```

### Download Checkpoint

Download and extract checkpoint files locally:

```bash
./tinkex checkpoint download <tinker_path> [--output <dir>] [--force]
```

**Options:**
- `--output <dir>` - Output directory for extracted files (default: current directory)
- `--force` - Overwrite existing files if present

**Example:**

```bash
./tinkex checkpoint download tinker://run-123/weights/0001 \
  --output ./models/checkpoint-001 \
  --force \
  --api-key "$TINKER_API_KEY"
# Output: Downloaded to ./models/checkpoint-001
```

### Help for Checkpoint Commands

```bash
./tinkex checkpoint --help
./tinkex checkpoint list --help
```

## `tinkex run` - Text Generation

The `run` command generates text completions using the Tinker sampling API and manages training runs.

### Generate Text

Sample text completions from a model:

```bash
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Hello there" \
  --max-tokens 64 \
  --temperature 0.7 \
  --num-samples 2 \
  --api-key "$TINKER_API_KEY"
```

#### Options

**Model Configuration:**
- `--base-model <id>` - Base model identifier (required, e.g., `meta-llama/Llama-3.1-8B`)
- `--model-path <path>` - Local model path (alternative to `--base-model`)

**Prompt Input (choose one):**
- `--prompt <text>` - Prompt text directly on command line
- `--prompt-file <path>` - Path to file containing prompt (see [Prompt Input Formats](#prompt-input-formats))

**Sampling Parameters:**
- `--max-tokens <int>` - Maximum tokens to generate
- `--temperature <float>` - Sampling temperature (default: 1.0)
- `--top-k <int>` - Top-k sampling parameter (default: -1, disabled)
- `--top-p <float>` - Nucleus sampling parameter (default: 1.0)
- `--num-samples <int>` - Number of samples to return (default: 1)

**Output Control:**
- `--output <path>` - Write output to file instead of stdout
- `--json` - Output full response as JSON instead of plain text

**Advanced:**
- `--http-pool <name>` - HTTP pool name to use for connection pooling

#### Plain Text Output

By default, `tinkex run` decodes tokens and prints human-readable text:

```bash
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "The capital of France is" \
  --max-tokens 10 \
  --api-key "$TINKER_API_KEY"
```

**Output:**
```
Starting sampling...
Sample 1:
Paris, which is located in the northern

stop_reason=length | avg_logprob=-1.234
Sampling complete (1 sequences)
```

#### JSON Output

Use `--json` to get the full structured response:

```bash
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Hello" \
  --max-tokens 5 \
  --json \
  --api-key "$TINKER_API_KEY"
```

**Output:**
```json
{
  "sequences": [
    {
      "tokens": [1245, 345, 678, 901, 234],
      "logprobs": [-0.123, -0.456, -0.789, -0.234, -0.567],
      "stop_reason": "length"
    }
  ],
  "prompt_logprobs": null,
  "topk_prompt_logprobs": null,
  "type": "sample"
}
```

#### Prompt Input Formats

The CLI supports multiple prompt input formats via `--prompt-file`:

**Plain Text File:**

```bash
# Create a text file
echo "Write a haiku about coding" > prompt.txt

./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt-file prompt.txt \
  --max-tokens 50 \
  --api-key "$TINKER_API_KEY"
```

**JSON Token Array:**

For precise control, provide pre-tokenized input as a JSON array of integers:

```bash
# Create a JSON file with token IDs
echo '[1, 2, 3, 4, 5]' > tokens.json

./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt-file tokens.json \
  --max-tokens 20 \
  --api-key "$TINKER_API_KEY"
```

**JSON Token Object:**

Alternatively, wrap tokens in an object:

```json
{
  "tokens": [1, 2, 3, 4, 5]
}
```

The CLI automatically detects the format:
- If the file parses as JSON and contains an integer array (or `{"tokens": [...]}`), it's treated as token IDs
- Otherwise, it's treated as plain text

#### Writing Output to Files

Use `--output` to write results to a file instead of stdout:

```bash
# Plain text output
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Generate a story" \
  --max-tokens 200 \
  --output story.txt \
  --api-key "$TINKER_API_KEY"

# JSON output
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Hello world" \
  --max-tokens 50 \
  --json \
  --output response.json \
  --api-key "$TINKER_API_KEY"
```

#### Multiple Samples

Generate multiple completions in a single request:

```bash
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Once upon a time" \
  --max-tokens 50 \
  --num-samples 3 \
  --temperature 0.9 \
  --api-key "$TINKER_API_KEY"
```

**Output:**
```
Starting sampling...
Sample 1:
, there was a brave knight...
stop_reason=length | avg_logprob=-1.234

Sample 2:
, in a land far away...
stop_reason=length | avg_logprob=-1.456

Sample 3:
, a young wizard discovered...
stop_reason=length | avg_logprob=-1.123

Sampling complete (3 sequences)
```

### List Training Runs

List all training runs with pagination:

```bash
./tinkex run list [--limit <int>] [--offset <int>]
```

**Options:**
- `--limit <int>` - Maximum number of runs to return (default: 20)
- `--offset <int>` - Number of runs to skip (default: 0)

**Output Format:**
```
run-123    meta-llama/Llama-3.1-8B
run-124    Qwen/Qwen2.5-7B
```

**Example:**

```bash
./tinkex run list --limit 10 --api-key "$TINKER_API_KEY"
```

### Get Training Run Info

Retrieve detailed information about a specific training run:

```bash
./tinkex run info <run_id>
```

**Arguments:**
- `<run_id>` - Training run identifier

**Output:**
```
run-abc123 (meta-llama/Llama-3.1-8B)
Owner: user@example.com
```

**Example:**

```bash
./tinkex run info run-abc123 --api-key "$TINKER_API_KEY"
```

### Help for Run Commands

```bash
./tinkex run --help
./tinkex run list --help
```

## `tinkex version` - Version Information

Display version and build information:

```bash
./tinkex version
# Output: tinkex 0.1.8 (abc1234)

./tinkex --version  # alias
```

### JSON Output

Get structured version information:

```bash
./tinkex version --json
```

**Output:**
```json
{
  "version": "0.1.8",
  "commit": "abc1234"
}
```

The commit hash is the short Git SHA from the build environment (7 characters). If Git is unavailable or the build is not from a Git repository, the commit field will be `null`.

## Programmatic CLI Invocation

You can invoke the CLI from Elixir scripts using `Tinkex.CLI.run/1`:

```elixir
# examples/cli_run_text.exs
defmodule MyScript do
  alias Tinkex.CLI

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    args = [
      "run",
      "--base-model", "meta-llama/Llama-3.1-8B",
      "--prompt", "Hello from Elixir",
      "--max-tokens", "64",
      "--temperature", "0.7",
      "--api-key", System.fetch_env!("TINKER_API_KEY")
    ]

    case CLI.run(args) do
      {:ok, %{response: response}} ->
        IO.inspect(response, label: "sampling response")

      {:error, reason} ->
        IO.puts(:stderr, "CLI failed: #{inspect(reason)}")
    end
  end
end

MyScript.run()
```

### Using Prompt Files Programmatically

```elixir
# examples/cli_run_prompt_file.exs
defmodule MyScript do
  alias Tinkex.CLI

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    # Create temporary prompt file
    tmp_dir = System.tmp_dir!()
    prompt_path = Path.join(tmp_dir, "prompt.txt")
    output_path = Path.join(tmp_dir, "output.json")

    File.write!(prompt_path, "Hello from a prompt file")

    args = [
      "run",
      "--base-model", "meta-llama/Llama-3.1-8B",
      "--prompt-file", prompt_path,
      "--json",
      "--output", output_path,
      "--api-key", System.fetch_env!("TINKER_API_KEY")
    ]

    case CLI.run(args) do
      {:ok, _} ->
        IO.puts("JSON output written to #{output_path}")
        IO.puts(File.read!(output_path))

      {:error, reason} ->
        IO.puts(:stderr, "CLI failed: #{inspect(reason)}")
    end
  end
end

MyScript.run()
```

### Return Values

`Tinkex.CLI.run/1` returns:

- `{:ok, result}` - Success, where `result` is a map with command-specific data
- `{:error, reason}` - Failure, with error details

The `result` map structure varies by command:

**Checkpoint save:**
```elixir
{:ok, %{
  command: :checkpoint,
  metadata: %{
    "base_model" => "meta-llama/Llama-3.1-8B",
    "model_id" => "run-123/weights/0001",
    "saved_at" => "2024-11-26T12:34:56Z",
    ...
  }
}}
```

**Run (sampling):**
```elixir
{:ok, %{
  command: :run,
  response: %Tinkex.Types.SampleResponse{
    sequences: [...],
    ...
  }
}}
```

**Version:**
```elixir
{:ok, %{
  command: :version,
  version: "0.1.8",
  commit: "abc1234",
  options: %{json: false}
}}
```

## Complete Examples

### Example 1: Save Checkpoint and Generate Text

```bash
#!/bin/bash
set -e

API_KEY="$TINKER_API_KEY"
MODEL="meta-llama/Llama-3.1-8B"

# Save checkpoint
echo "Saving checkpoint..."
./tinkex checkpoint \
  --base-model "$MODEL" \
  --rank 32 \
  --output checkpoint.json \
  --api-key "$API_KEY"

# Generate text
echo "Generating text..."
./tinkex run \
  --base-model "$MODEL" \
  --prompt "The meaning of life is" \
  --max-tokens 100 \
  --temperature 0.8 \
  --output generation.txt \
  --api-key "$API_KEY"

echo "Done! Check checkpoint.json and generation.txt"
```

### Example 2: Batch Text Generation with JSON Output

```bash
#!/bin/bash
API_KEY="$TINKER_API_KEY"
MODEL="meta-llama/Llama-3.1-8B"

# Create prompts directory
mkdir -p prompts outputs

# Create multiple prompt files
echo "Write a haiku about code" > prompts/haiku.txt
echo "Explain recursion simply" > prompts/recursion.txt
echo "List 5 programming languages" > prompts/languages.txt

# Process each prompt
for prompt_file in prompts/*.txt; do
  base=$(basename "$prompt_file" .txt)
  echo "Processing: $base"

  ./tinkex run \
    --base-model "$MODEL" \
    --prompt-file "$prompt_file" \
    --max-tokens 100 \
    --temperature 0.7 \
    --json \
    --output "outputs/${base}.json" \
    --api-key "$API_KEY"
done

echo "All prompts processed! Results in outputs/"
```

### Example 3: Checkpoint Management Workflow

```bash
#!/bin/bash
API_KEY="$TINKER_API_KEY"

# List all checkpoints
echo "=== Your Checkpoints ==="
./tinkex checkpoint list --limit 20 --api-key "$API_KEY"

# Get info on specific checkpoint
CHECKPOINT_PATH="tinker://run-123/weights/0001"
echo ""
echo "=== Checkpoint Info ==="
./tinkex checkpoint info "$CHECKPOINT_PATH" --api-key "$API_KEY"

# Download checkpoint
echo ""
echo "=== Downloading Checkpoint ==="
./tinkex checkpoint download "$CHECKPOINT_PATH" \
  --output ./models/checkpoint-001 \
  --force \
  --api-key "$API_KEY"

echo ""
echo "Checkpoint saved to ./models/checkpoint-001"
```

### Example 4: Using Token IDs for Precise Control

```bash
#!/bin/bash
API_KEY="$TINKER_API_KEY"
MODEL="meta-llama/Llama-3.1-8B"

# Create a JSON file with specific token IDs
# (These would be actual token IDs from your tokenizer)
cat > tokens.json <<EOF
{
  "tokens": [1, 450, 3783, 315, 2324, 374]
}
EOF

# Generate text from token IDs
./tinkex run \
  --base-model "$MODEL" \
  --prompt-file tokens.json \
  --max-tokens 50 \
  --temperature 0.7 \
  --json \
  --output output.json \
  --api-key "$API_KEY"

echo "Generated text from token IDs:"
cat output.json | jq .
```

### Example 5: Environment-Based Configuration

```bash
#!/bin/bash
# Set environment variables for cleaner command lines
export TINKER_API_KEY="your-api-key"
export TINKER_BASE_URL="https://tinker.thinkingmachines.dev/services/tinker-prod"

# Now you can omit --api-key and --base-url
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Hello world" \
  --max-tokens 20

# Or use them programmatically
./tinkex checkpoint \
  --base-model Qwen/Qwen2.5-7B \
  --output checkpoint.json
```

## Error Handling

The CLI provides clear error messages for common issues:

**Missing API Key:**
```
Checkpoint failed. Please check your inputs: Missing --api-key
```

**Missing Required Options:**
```
Checkpoint failed. Please check your inputs: --output is required for checkpoint command
```

**Invalid Options:**
```
Invalid option(s) for {:checkpoint, :save}: --invalid-flag
```

**Server Errors:**
```
Sampling failed due to server or transient error. Consider retrying: API request failed
```

**Timeout:**
```
Sampling failed due to server or transient error. Consider retrying: Timed out while awaiting sampling
```

## Exit Codes

The CLI uses standard exit codes:

- `0` - Success
- `1` - Error (validation, server error, or timeout)

This allows for shell scripting:

```bash
#!/bin/bash
if ./tinkex run --prompt "Test" --base-model meta-llama/Llama-3.1-8B; then
  echo "Success!"
else
  echo "Failed with exit code: $?"
  exit 1
fi
```

## Performance Tips

1. **Connection Pooling**: The CLI automatically uses HTTP/2 connection pools. For batch operations, consider using the SDK directly with `ServiceClient` to reuse connections.

2. **Timeouts**: Adjust `--timeout` for large generation requests:
   ```bash
   ./tinkex run --timeout 300000 --max-tokens 2000 ...
   ```

3. **Parallel Processing**: For multiple independent requests, use shell parallelization:
   ```bash
   # Generate 4 samples in parallel
   for i in {1..4}; do
     ./tinkex run --prompt "Sample $i" ... &
   done
   wait
   ```

4. **Output Formats**: Use `--json` when you need to parse output programmatically. Plain text is more efficient for human reading.

## Troubleshooting

### Command Not Found

If `tinkex` is not found after building:

```bash
# Use relative path
./tinkex version

# Or add to PATH
export PATH="$PATH:$PWD"
tinkex version

# Or install globally
mix escript.install ./tinkex
# Then ensure ~/.mix/escripts is in PATH
export PATH="$PATH:$HOME/.mix/escripts"
```

### SSL/TLS Errors

If you encounter certificate verification errors:

```bash
# Set base URL explicitly
./tinkex run \
  --base-url "https://tinker.thinkingmachines.dev/services/tinker-prod" \
  ...
```

### Large Prompts

For very large prompts, use `--prompt-file` instead of `--prompt`:

```bash
# This may fail if the prompt is too large for command line
./tinkex run --prompt "$(cat large_prompt.txt)" ...

# Use prompt file instead
./tinkex run --prompt-file large_prompt.txt ...
```

### JSON Parsing

When using `--json`, ensure you have `jq` or similar tools for parsing:

```bash
./tinkex run --json ... | jq '.sequences[0].tokens'
```

## See Also

- [Getting Started Guide](getting_started.md) - Installation and setup
- [API Reference](api_reference.md) - SDK API documentation
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [Training Loop Guide](training_loop.md) - End-to-end training workflows
- Examples Directory (`examples/`) - Runnable example scripts

## Help Commands

All commands support `--help` or `-h`:

```bash
./tinkex --help
./tinkex checkpoint --help
./tinkex checkpoint list --help
./tinkex run --help
./tinkex run list --help
./tinkex version --help
```
