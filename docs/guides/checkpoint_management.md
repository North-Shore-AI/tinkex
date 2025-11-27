# Checkpoint Management

This guide covers checkpoint and training run management in Tinkex, including listing, inspecting, downloading, and publishing checkpoints.

## Overview

Checkpoints are snapshots of model weights saved during training. Tinkex provides comprehensive APIs to:

- List and inspect checkpoints and training runs
- Get detailed checkpoint information (base model, LoRA configuration)
- Download checkpoint archives
- Publish/unpublish checkpoints for sharing
- Delete old checkpoints
- Save and load training checkpoints (with optional optimizer state)

All checkpoints are referenced using the **Tinker path format**: `tinker://run-id/weights/checkpoint-id`

## Prerequisites

```elixir
{:ok, _} = Application.ensure_all_started(:tinkex)

config =
  Tinkex.Config.new(
    api_key: System.fetch_env!("TINKER_API_KEY"),
    base_url: System.get_env("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod")
  )

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, rest_client} = Tinkex.ServiceClient.create_rest_client(service)
```

## Saving and Loading Training Checkpoints

Save a named checkpoint during training:

```elixir
{:ok, task} = Tinkex.TrainingClient.save_state(training_client, "checkpoint-001")
{:ok, %Tinkex.Types.SaveWeightsResponse{path: checkpoint_path}} = Task.await(task)
```

Load weights (without optimizer state) for transfer learning or evaluation:

```elixir
{:ok, task} =
  Tinkex.TrainingClient.load_state(training_client, "tinker://run-id/weights/checkpoint-001")

{:ok, _} = Task.await(task)
```

Resume training with optimizer state preserved:

```elixir
{:ok, task} =
  Tinkex.TrainingClient.load_state_with_optimizer(
    training_client,
    "tinker://run-id/weights/checkpoint-001"
  )

{:ok, _} = Task.await(task)
```

Create a new training client directly from a checkpoint:

```elixir
{:ok, training_client} =
  Tinkex.ServiceClient.create_training_client_from_state(
    service,
    "tinker://run-id/weights/checkpoint-001"
  )
```

## Tinker Path Format

Checkpoints use a structured URI format:

```
tinker://run-id/weights/checkpoint-id
```

**Examples:**
- `tinker://run-abc123/weights/0001`
- `tinker://session-xyz/weights/checkpoint-final`

This format uniquely identifies a checkpoint and is used throughout the API.

## Listing Checkpoints

### List All User Checkpoints

Get all checkpoints for the current user with pagination:

```elixir
{:ok, response} = Tinkex.RestClient.list_user_checkpoints(rest_client, limit: 50, offset: 0)

Enum.each(response.checkpoints, fn checkpoint ->
  IO.puts("Path: #{checkpoint.tinker_path}")
  IO.puts("Type: #{checkpoint.checkpoint_type}")
  IO.puts("Size: #{checkpoint.size_bytes} bytes")
  IO.puts("Public: #{checkpoint.public}")
  IO.puts("Created: #{checkpoint.time}")
  IO.puts("")
end)
```

**Options:**
- `:limit` - Maximum number of checkpoints to return (default: 50)
- `:offset` - Offset for pagination (default: 0)

### List Checkpoints for a Training Run

Get all checkpoints associated with a specific training run:

```elixir
{:ok, response} = Tinkex.RestClient.list_checkpoints(rest_client, "run-abc123")

Enum.each(response.checkpoints, fn checkpoint ->
  IO.puts("Checkpoint: #{checkpoint.tinker_path}")
  IO.puts("ID: #{checkpoint.checkpoint_id}")

  if checkpoint.size_bytes do
    size_mb = checkpoint.size_bytes / (1024 * 1024)
    IO.puts("Size: #{Float.round(size_mb, 2)} MB")
  end
end)
```

## Training Runs

### List Training Runs

Get all training runs with pagination:

```elixir
{:ok, response} = Tinkex.RestClient.list_training_runs(rest_client, limit: 20, offset: 0)

Enum.each(response.training_runs, fn run ->
  IO.puts("Run ID: #{run.training_run_id}")
  IO.puts("Base Model: #{run.base_model}")
  IO.puts("Is LoRA: #{run.is_lora}")
  IO.puts("LoRA Rank: #{run.lora_rank || "N/A"}")
  IO.puts("Corrupted: #{run.corrupted || false}")
  IO.puts("Last Checkpoint: #{run.last_checkpoint && run.last_checkpoint.tinker_path}")
  IO.puts("Owner: #{run.model_owner}")
  IO.puts("")
end)
```

**Options:**
- `:limit` - Maximum number of runs to return (default: 20)
- `:offset` - Offset for pagination (default: 0)

### Get Training Run Details

Retrieve detailed information about a specific training run:

```elixir
{:ok, run} = Tinkex.RestClient.get_training_run(rest_client, "run-abc123")

IO.puts("Base Model: #{run.base_model}")
IO.puts("Is LoRA: #{run.is_lora}")
IO.puts("LoRA Rank: #{run.lora_rank}")
IO.puts("Last Checkpoint: #{run.last_checkpoint && run.last_checkpoint.tinker_path}")
IO.puts("Last Sampler Checkpoint: #{run.last_sampler_checkpoint && run.last_sampler_checkpoint.tinker_path}")
IO.puts("Last Request Time: #{run.last_request_time}")
```

You can also resolve the run directly from a checkpoint tinker path:

```elixir
{:ok, run} =
  Tinkex.RestClient.get_training_run_by_tinker_path(
    rest_client,
    "tinker://run-abc123/weights/0001"
  )
```

## Checkpoint Information

### Get Checkpoint Metadata

Get detailed information about a checkpoint, including base model and LoRA configuration:

```elixir
{:ok, weights_info} =
  Tinkex.RestClient.get_weights_info_by_tinker_path(
    rest_client,
    "tinker://run-abc123/weights/0001"
  )

IO.puts("Base Model: #{weights_info.base_model}")
IO.puts("Is LoRA: #{weights_info.is_lora}")
IO.puts("LoRA Rank: #{weights_info.lora_rank}")
```

### Validate Checkpoint Compatibility

Check if a checkpoint matches expected configuration:

```elixir
def validate_checkpoint(rest_client, path, expected_rank) do
  case Tinkex.RestClient.get_weights_info_by_tinker_path(rest_client, path) do
    {:ok, %{is_lora: true, lora_rank: ^expected_rank}} ->
      :ok

    {:ok, %{is_lora: true, lora_rank: actual}} ->
      {:error, {:rank_mismatch, expected: expected_rank, actual: actual}}

    {:ok, %{is_lora: false}} ->
      {:error, :not_lora}

    {:error, _} = error ->
      error
  end
end
```

## Downloading Checkpoints

### Basic Download

Download and extract a checkpoint archive:

```elixir
{:ok, result} = Tinkex.CheckpointDownload.download(
  rest_client,
  "tinker://run-abc123/weights/0001",
  output_dir: "./models",
  force: false
)

IO.puts("Downloaded to: #{result.destination}")
```

**Options:**
- `:output_dir` - Parent directory for extraction (default: current directory)
- `:force` - Overwrite existing directory if it exists (default: false)
- `:progress` - Progress callback function (see below)

### Download with Progress Tracking

Monitor download progress with a callback:

```elixir
progress_fn = fn downloaded, total ->
  percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
  IO.write("\rProgress: #{percent}% (#{downloaded} / #{total} bytes)")
end

{:ok, result} = Tinkex.CheckpointDownload.download(
  rest_client,
  "tinker://run-abc123/weights/0001",
  output_dir: "./models",
  force: true,
  progress: progress_fn
)

IO.puts("\n\nDownload complete!")
IO.puts("Extracted to: #{result.destination}")
```

### Get Archive URL

Get a signed URL for downloading the checkpoint archive directly:

```elixir
{:ok, url_response} =
  Tinkex.RestClient.get_checkpoint_archive_url_by_tinker_path(
    rest_client,
    "tinker://run-abc123/weights/0001"
  )

IO.puts("Download URL: #{url_response.url}")
```

This URL can be used with external download tools or for programmatic access.

## Using Downloaded Weights

After downloading, checkpoint files are extracted to a local directory:

```elixir
{:ok, result} = Tinkex.CheckpointDownload.download(
  rest_client,
  "tinker://run-abc123/weights/0001",
  output_dir: "./models"
)

# List extracted files
files = File.ls!(result.destination)
IO.puts("Extracted files: #{inspect(files)}")

# Examine file sizes
Enum.each(files, fn file ->
  path = Path.join(result.destination, file)
  stat = File.stat!(path)
  size_mb = stat.size / (1024 * 1024)
  IO.puts("  #{file}: #{Float.round(size_mb, 2)} MB")
end)
```

The checkpoint directory typically contains:
- Model weight files (`.safetensors`, `.bin`, or similar)
- Configuration files (`config.json`)
- Tokenizer files (if applicable)
- LoRA adapter files (for LoRA checkpoints)

## Publishing Checkpoints

### Make a Checkpoint Public

Publish a checkpoint to make it accessible to others:

```elixir
{:ok, _} = Tinkex.RestClient.publish_checkpoint(
  rest_client,
  "tinker://run-abc123/weights/0001"
)

IO.puts("Checkpoint published successfully")
```

### Make a Checkpoint Private

Unpublish a checkpoint to restrict access:

```elixir
{:ok, _} = Tinkex.RestClient.unpublish_checkpoint(
  rest_client,
  "tinker://run-abc123/weights/0001"
)

IO.puts("Checkpoint unpublished successfully")
```

## Deleting Checkpoints

Remove a checkpoint permanently:

```elixir
{:ok, _} = Tinkex.RestClient.delete_checkpoint(
  rest_client,
  "tinker://run-abc123/weights/0001"
)

IO.puts("Checkpoint deleted")
```

**Warning:** Deletion is permanent and cannot be undone. Ensure you have backups if needed.

## Sessions and Checkpoints

### Get Session Information

Sessions group related training runs and samplers:

```elixir
{:ok, session} = Tinkex.RestClient.get_session(rest_client, "session-xyz")

IO.puts("Training Runs: #{inspect(session.training_run_ids)}")
IO.puts("Samplers: #{inspect(session.sampler_ids)}")
```

### List Sessions

Get all sessions with pagination:

```elixir
{:ok, response} = Tinkex.RestClient.list_sessions(rest_client, limit: 20, offset: 0)

Enum.each(response.sessions, fn session ->
  IO.puts("Session ID: #{session.session_id}")
end)
```

## Complete Example: Checkpoint Workflow

Here's a complete workflow for managing checkpoints:

```elixir
# 1. List available training runs
{:ok, runs_response} = Tinkex.RestClient.list_training_runs(rest_client, limit: 10)

case runs_response.training_runs do
  [] ->
    IO.puts("No training runs found")

  [run | _] ->
    IO.puts("Inspecting run: #{run.training_run_id}")
    IO.puts("Base Model: #{run.base_model}")
    IO.puts("Is LoRA: #{run.is_lora}, Rank: #{run.lora_rank}")

    # 2. List checkpoints for this run
    {:ok, ckpt_response} = Tinkex.RestClient.list_checkpoints(rest_client, run.training_run_id)

    case ckpt_response.checkpoints do
      [] ->
        IO.puts("No checkpoints found for this run")

      [checkpoint | _] ->
        IO.puts("\nCheckpoint: #{checkpoint.tinker_path}")

        # 3. Get checkpoint metadata
        {:ok, weights_info} =
          Tinkex.RestClient.get_weights_info_by_tinker_path(
            rest_client,
            checkpoint.tinker_path
          )

        IO.puts("Checkpoint Base Model: #{weights_info.base_model}")
        IO.puts("Checkpoint LoRA Rank: #{weights_info.lora_rank}")

        # 4. Download the checkpoint
        {:ok, download} = Tinkex.CheckpointDownload.download(
          rest_client,
          checkpoint.tinker_path,
          output_dir: "./downloaded_models",
          force: true,
          progress: fn downloaded, total ->
            percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
            IO.write("\rDownloading: #{percent}%")
          end
        )

        IO.puts("\n\nDownloaded to: #{download.destination}")

        # 5. List extracted files
        files = File.ls!(download.destination)
        IO.puts("\nExtracted #{length(files)} file(s):")

        Enum.each(files, fn file ->
          path = Path.join(download.destination, file)
          stat = File.stat!(path)
          size_mb = stat.size / (1024 * 1024)
          IO.puts("  • #{file} (#{Float.round(size_mb, 2)} MB)")
        end)
    end
end
```

## Error Handling

### Common Errors

**Checkpoint Already Downloaded:**
```elixir
case Tinkex.CheckpointDownload.download(rest_client, path, output_dir: "./models") do
  {:error, {:exists, existing_path}} ->
    IO.puts("Directory already exists: #{existing_path}")
    IO.puts("Use force: true to overwrite")

  {:ok, result} ->
    IO.puts("Downloaded successfully")
end
```

**Invalid Tinker Path:**
```elixir
case Tinkex.CheckpointDownload.download(rest_client, "invalid-path") do
  {:error, {:invalid_path, message}} ->
    IO.puts("Invalid path: #{message}")
    IO.puts("Path must start with 'tinker://'")

  {:ok, result} ->
    IO.puts("Downloaded successfully")
end
```

**Checkpoint Not Found:**
```elixir
case Tinkex.RestClient.get_checkpoint_archive_url_by_tinker_path(rest_client, path) do
  {:error, %Tinkex.Error{status: 404}} ->
    IO.puts("Checkpoint not found or no longer exists")

  {:error, %Tinkex.Error{status: 403}} ->
    IO.puts("Access denied to this checkpoint")

  {:ok, url_response} ->
    IO.puts("Archive URL: #{url_response.url}")
end
```

## Best Practices

### 1. Check Availability Before Downloading

```elixir
# Verify checkpoint exists before downloading
case Tinkex.RestClient.get_checkpoint_archive_url_by_tinker_path(rest_client, checkpoint_path) do
  {:ok, _url_response} ->
    # Proceed with download
    Tinkex.CheckpointDownload.download(rest_client, checkpoint_path, output_dir: "./models")

  {:error, error} ->
    IO.puts("Checkpoint not available: #{inspect(error)}")
end
```

### 2. Use Pagination for Large Collections

```elixir
def fetch_all_checkpoints(rest_client, limit \\ 50) do
  fetch_page(rest_client, limit, 0, [])
end

defp fetch_page(rest_client, limit, offset, acc) do
  case Tinkex.RestClient.list_user_checkpoints(rest_client, limit: limit, offset: offset) do
    {:ok, response} when response.checkpoints == [] ->
      {:ok, Enum.reverse(acc)}

    {:ok, response} ->
      new_acc = response.checkpoints ++ acc
      fetch_page(rest_client, limit, offset + limit, new_acc)

    {:error, error} ->
      {:error, error}
  end
end
```

### 3. Clean Up Old Checkpoints

```elixir
def cleanup_old_checkpoints(rest_client, keep_count \\ 5) do
  {:ok, response} = Tinkex.RestClient.list_user_checkpoints(rest_client, limit: 100)

  # Sort by time (assuming ISO8601 format)
  sorted = Enum.sort_by(response.checkpoints, & &1.time, :desc)

  # Keep the newest ones
  {_keep, delete} = Enum.split(sorted, keep_count)

  # Delete old checkpoints
  Enum.each(delete, fn checkpoint ->
    case Tinkex.RestClient.delete_checkpoint(rest_client, checkpoint.tinker_path) do
      {:ok, _} ->
        IO.puts("Deleted: #{checkpoint.tinker_path}")

      {:error, error} ->
        IO.puts("Failed to delete #{checkpoint.tinker_path}: #{inspect(error)}")
    end
  end)
end
```

### 4. Verify Download Integrity

```elixir
def verify_download(result) do
  if File.exists?(result.destination) do
    files = File.ls!(result.destination)

    if length(files) > 0 do
      {:ok, :verified}
    else
      {:error, :empty_directory}
    end
  else
    {:error, :directory_not_found}
  end
end
```

## What to Read Next

- API overview: `docs/guides/api_reference.md`
- Training loop guide: `docs/guides/training_loop.md`
- Troubleshooting: `docs/guides/troubleshooting.md`
- Getting started: `docs/guides/getting_started.md`
