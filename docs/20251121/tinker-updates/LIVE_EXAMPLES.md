# Live Examples for Tinkex New Features

## Overview

These examples demonstrate real usage of the new Tinkex features against the Tinker API.

**Requirements:**
- `TINKER_API_KEY` environment variable
- Network access to Tinker API

---

## Example 1: Session Management

### File: `examples/sessions_management.exs`

```elixir
defmodule Tinkex.Examples.SessionsManagement do
  @moduledoc """
  Example demonstrating session management APIs.

  Shows how to:
  - Create a RestClient
  - List all sessions
  - Get session details
  """

  alias Tinkex.{ServiceClient, RestClient, Config}

  def run do
    IO.puts("=== Tinkex Session Management Example ===\n")

    # Ensure application is started
    {:ok, _} = Application.ensure_all_started(:tinkex)

    # Create config from environment
    config = Config.new(
      api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
      base_url: System.get_env("TINKER_BASE_URL", "https://api.thinkingmachines.ai")
    )

    # Start ServiceClient
    IO.puts("Starting ServiceClient...")
    {:ok, service_pid} = ServiceClient.start_link(config: config)

    # Create RestClient
    IO.puts("Creating RestClient...")
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    # List sessions
    IO.puts("\n--- Listing Sessions ---")
    case RestClient.list_sessions(rest_client, limit: 10) do
      {:ok, response} ->
        IO.puts("Found #{length(response.sessions)} sessions:")
        Enum.each(response.sessions, fn session_id ->
          IO.puts("  • #{session_id}")
        end)

        # Get details for first session if available
        if length(response.sessions) > 0 do
          [first_session | _] = response.sessions
          get_session_details(rest_client, first_session)
        end

      {:error, error} ->
        IO.puts("Error listing sessions: #{inspect(error)}")
    end

    # Cleanup
    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp get_session_details(rest_client, session_id) do
    IO.puts("\n--- Session Details: #{session_id} ---")

    case RestClient.get_session(rest_client, session_id) do
      {:ok, response} ->
        IO.puts("Training Runs: #{length(response.training_run_ids)}")
        Enum.each(response.training_run_ids, fn run_id ->
          IO.puts("  • #{run_id}")
        end)

        IO.puts("Samplers: #{length(response.sampler_ids)}")
        Enum.each(response.sampler_ids, fn sampler_id ->
          IO.puts("  • #{sampler_id}")
        end)

      {:error, error} ->
        IO.puts("Error getting session: #{inspect(error)}")
    end
  end
end

Tinkex.Examples.SessionsManagement.run()
```

**Run:** `mix run examples/sessions_management.exs`

---

## Example 2: Checkpoint Management

### File: `examples/checkpoints_management.exs`

```elixir
defmodule Tinkex.Examples.CheckpointsManagement do
  @moduledoc """
  Example demonstrating checkpoint management APIs.

  Shows how to:
  - List all user checkpoints
  - List checkpoints for a specific run
  - View checkpoint details
  """

  alias Tinkex.{ServiceClient, RestClient, Config}

  def run do
    IO.puts("=== Tinkex Checkpoint Management Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    config = Config.new(
      api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
      base_url: System.get_env("TINKER_BASE_URL", "https://api.thinkingmachines.ai")
    )

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    # List all user checkpoints
    list_all_checkpoints(rest_client)

    # If run_id is provided, list checkpoints for that run
    if run_id = System.get_env("TINKER_RUN_ID") do
      list_run_checkpoints(rest_client, run_id)
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp list_all_checkpoints(rest_client) do
    IO.puts("--- All User Checkpoints ---")

    case RestClient.list_user_checkpoints(rest_client, limit: 20) do
      {:ok, response} ->
        total = if response.cursor, do: response.cursor.total_count, else: length(response.checkpoints)
        IO.puts("Found #{length(response.checkpoints)} of #{total} checkpoints:\n")

        Enum.each(response.checkpoints, fn ckpt ->
          size = if ckpt.size_bytes, do: format_size(ckpt.size_bytes), else: "N/A"
          IO.puts("  #{ckpt.checkpoint_id}")
          IO.puts("    Path: #{ckpt.tinker_path}")
          IO.puts("    Type: #{ckpt.checkpoint_type}")
          IO.puts("    Size: #{size}")
          IO.puts("    Public: #{ckpt.public}")
          IO.puts("    Created: #{ckpt.time}")
          IO.puts("")
        end)

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end

  defp list_run_checkpoints(rest_client, run_id) do
    IO.puts("\n--- Checkpoints for Run: #{run_id} ---")

    case RestClient.list_checkpoints(rest_client, run_id) do
      {:ok, response} ->
        IO.puts("Found #{length(response.checkpoints)} checkpoints:")

        Enum.each(response.checkpoints, fn ckpt ->
          IO.puts("  • #{ckpt.tinker_path}")
        end)

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"
end

Tinkex.Examples.CheckpointsManagement.run()
```

**Run:** `mix run examples/checkpoints_management.exs`
**With run ID:** `TINKER_RUN_ID=run-123 mix run examples/checkpoints_management.exs`

---

## Example 3: Checkpoint Download

### File: `examples/checkpoint_download.exs`

```elixir
defmodule Tinkex.Examples.CheckpointDownload do
  @moduledoc """
  Example demonstrating checkpoint download functionality.

  Shows how to:
  - Get download URL for a checkpoint
  - Download and extract checkpoint archive
  - Track progress during download
  """

  alias Tinkex.{ServiceClient, RestClient, CheckpointDownload, Config}

  def run do
    IO.puts("=== Tinkex Checkpoint Download Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    checkpoint_path = System.get_env("TINKER_CHECKPOINT_PATH") ||
      raise "TINKER_CHECKPOINT_PATH required (e.g., tinker://run-123/weights/0001)"

    output_dir = System.get_env("TINKER_OUTPUT_DIR", File.cwd!())

    config = Config.new(
      api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
      base_url: System.get_env("TINKER_BASE_URL", "https://api.thinkingmachines.ai")
    )

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    IO.puts("Downloading checkpoint: #{checkpoint_path}")
    IO.puts("Output directory: #{output_dir}\n")

    # Progress callback
    progress_fn = fn downloaded, total ->
      percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
      IO.write("\rProgress: #{percent}% (#{format_size(downloaded)} / #{format_size(total)})")
    end

    case CheckpointDownload.download(rest_client, checkpoint_path,
      output_dir: output_dir,
      force: System.get_env("FORCE") == "true",
      progress: progress_fn
    ) do
      {:ok, result} ->
        IO.puts("\n\nDownload complete!")
        IO.puts("Extracted to: #{result.destination}")

        # List extracted files
        files = File.ls!(result.destination)
        IO.puts("\nExtracted files (#{length(files)}):")
        Enum.each(files, fn file ->
          path = Path.join(result.destination, file)
          size = File.stat!(path).size
          IO.puts("  • #{file} (#{format_size(size)})")
        end)

      {:error, {:exists, path}} ->
        IO.puts("\nError: Directory already exists: #{path}")
        IO.puts("Use FORCE=true to overwrite")

      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"
end

Tinkex.Examples.CheckpointDownload.run()
```

**Run:**
```bash
TINKER_CHECKPOINT_PATH="tinker://run-123/weights/0001" \
  mix run examples/checkpoint_download.exs

# With custom output and force overwrite
TINKER_CHECKPOINT_PATH="tinker://run-123/weights/0001" \
  TINKER_OUTPUT_DIR="./models" \
  FORCE=true \
  mix run examples/checkpoint_download.exs
```

---

## Example 4: Async Client Creation

### File: `examples/async_client_creation.exs`

```elixir
defmodule Tinkex.Examples.AsyncClientCreation do
  @moduledoc """
  Example demonstrating async client creation patterns.

  Shows how to:
  - Create multiple sampling clients concurrently
  - Use Task.await_many for parallel operations
  """

  alias Tinkex.{ServiceClient, SamplingClient, Config}

  def run do
    IO.puts("=== Tinkex Async Client Creation Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    config = Config.new(
      api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
      base_url: System.get_env("TINKER_BASE_URL", "https://api.thinkingmachines.ai")
    )

    # Get checkpoint paths from environment or use defaults
    checkpoint_paths = case System.get_env("TINKER_CHECKPOINT_PATHS") do
      nil ->
        IO.puts("No TINKER_CHECKPOINT_PATHS provided, using demo with base model")
        []
      paths ->
        String.split(paths, ",")
    end

    {:ok, service_pid} = ServiceClient.start_link(config: config)

    if length(checkpoint_paths) > 0 do
      create_multiple_clients(service_pid, checkpoint_paths)
    else
      create_single_client_async(service_pid)
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp create_single_client_async(service_pid) do
    IO.puts("Creating sampling client asynchronously...")

    base_model = System.get_env("TINKER_BASE_MODEL", "meta-llama/Llama-3.2-1B")

    task = ServiceClient.create_sampling_client_async(service_pid, base_model: base_model)

    IO.puts("Task created, awaiting result...")

    case Task.await(task, 30_000) do
      {:ok, pid} ->
        IO.puts("✓ Sampling client created: #{inspect(pid)}")
        GenServer.stop(pid)

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}")
    end
  end

  defp create_multiple_clients(service_pid, checkpoint_paths) do
    IO.puts("Creating #{length(checkpoint_paths)} sampling clients concurrently...\n")

    # Start timing
    start_time = System.monotonic_time(:millisecond)

    # Create tasks for all clients
    tasks = Enum.map(checkpoint_paths, fn path ->
      IO.puts("  Starting task for: #{path}")
      SamplingClient.create_async(service_pid, model_path: path)
    end)

    # Wait for all to complete
    IO.puts("\nAwaiting all tasks...")
    results = Task.await_many(tasks, 60_000)

    # Calculate time
    elapsed = System.monotonic_time(:millisecond) - start_time

    # Report results
    IO.puts("\nResults (#{elapsed}ms total):")

    Enum.zip(checkpoint_paths, results)
    |> Enum.each(fn {path, result} ->
      case result do
        {:ok, pid} ->
          IO.puts("  ✓ #{path} -> #{inspect(pid)}")
          GenServer.stop(pid)

        {:error, reason} ->
          IO.puts("  ✗ #{path} -> #{inspect(reason)}")
      end
    end)

    successes = Enum.count(results, fn {:ok, _} -> true; _ -> false end)
    IO.puts("\nSuccess: #{successes}/#{length(results)}")
  end
end

Tinkex.Examples.AsyncClientCreation.run()
```

**Run:**
```bash
# Single client with base model
mix run examples/async_client_creation.exs

# Multiple clients concurrently
TINKER_CHECKPOINT_PATHS="tinker://run-1/weights/0001,tinker://run-2/weights/0001,tinker://run-3/weights/0001" \
  mix run examples/async_client_creation.exs
```

---

## Example 5: Complete Workflow

### File: `examples/complete_workflow.exs`

```elixir
defmodule Tinkex.Examples.CompleteWorkflow do
  @moduledoc """
  Complete example demonstrating full workflow:
  1. List sessions
  2. List checkpoints
  3. Download a checkpoint
  4. Create sampling client from checkpoint
  5. Sample text
  """

  alias Tinkex.{ServiceClient, RestClient, SamplingClient, CheckpointDownload, Config}

  def run do
    IO.puts("=== Tinkex Complete Workflow Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    config = Config.new(
      api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
      base_url: System.get_env("TINKER_BASE_URL", "https://api.thinkingmachines.ai")
    )

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    # Step 1: List sessions
    IO.puts("Step 1: Listing sessions...")
    {:ok, sessions} = RestClient.list_sessions(rest_client, limit: 5)
    IO.puts("  Found #{length(sessions.sessions)} sessions\n")

    # Step 2: List checkpoints
    IO.puts("Step 2: Listing checkpoints...")
    {:ok, checkpoints} = RestClient.list_user_checkpoints(rest_client, limit: 5)
    IO.puts("  Found #{length(checkpoints.checkpoints)} checkpoints\n")

    if length(checkpoints.checkpoints) > 0 do
      # Step 3: Get first checkpoint details
      [checkpoint | _] = checkpoints.checkpoints
      IO.puts("Step 3: Using checkpoint: #{checkpoint.tinker_path}\n")

      # Step 4: Create sampling client
      IO.puts("Step 4: Creating sampling client...")
      {:ok, sampling_pid} = ServiceClient.create_sampling_client(
        service_pid,
        model_path: checkpoint.tinker_path
      )
      IO.puts("  Sampling client created\n")

      # Step 5: Sample text
      IO.puts("Step 5: Sampling text...")
      prompt = System.get_env("TINKER_PROMPT", "Hello, world!")

      task = SamplingClient.sample(sampling_pid, prompt, %{
        max_tokens: 50,
        temperature: 0.7
      })

      case Task.await(task, 30_000) do
        {:ok, response} ->
          IO.puts("  Prompt: #{prompt}")
          IO.puts("  Response: #{response.text}")

        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end

      GenServer.stop(sampling_pid)
    else
      IO.puts("No checkpoints found to sample from")
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end
end

Tinkex.Examples.CompleteWorkflow.run()
```

**Run:** `mix run examples/complete_workflow.exs`

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TINKER_API_KEY` | Yes | - | Tinker API key |
| `TINKER_BASE_URL` | No | `https://api.thinkingmachines.ai` | API base URL |
| `TINKER_RUN_ID` | No | - | Specific run ID for filtering |
| `TINKER_CHECKPOINT_PATH` | For download | - | Checkpoint path to download |
| `TINKER_CHECKPOINT_PATHS` | No | - | Comma-separated checkpoint paths |
| `TINKER_OUTPUT_DIR` | No | Current directory | Download output directory |
| `TINKER_BASE_MODEL` | No | `meta-llama/Llama-3.2-1B` | Base model for sampling |
| `TINKER_PROMPT` | No | `Hello, world!` | Prompt for sampling |
| `FORCE` | No | `false` | Overwrite existing downloads |

---

## Running Examples

```bash
# Set API key first
export TINKER_API_KEY="your-api-key"

# Run individual examples
mix run examples/sessions_management.exs
mix run examples/checkpoints_management.exs
mix run examples/checkpoint_download.exs
mix run examples/async_client_creation.exs
mix run examples/complete_workflow.exs

# Run all examples
for f in examples/*.exs; do
  echo "Running $f..."
  mix run "$f"
  echo ""
done
```

---

## Example Output

### sessions_management.exs
```
=== Tinkex Session Management Example ===

Starting ServiceClient...
Creating RestClient...

--- Listing Sessions ---
Found 3 sessions:
  • session-abc123
  • session-def456
  • session-ghi789

--- Session Details: session-abc123 ---
Training Runs: 2
  • model-1
  • model-2
Samplers: 1
  • sampler-1

=== Example Complete ===
```

### checkpoints_management.exs
```
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 5 of 23 checkpoints:

  ckpt-001
    Path: tinker://run-1/weights/0001
    Type: weights
    Size: 125.3 MB
    Public: false
    Created: 2025-11-20T10:00:00Z

  ckpt-002
    Path: tinker://run-1/weights/0002
    Type: weights
    Size: 125.4 MB
    Public: false
    Created: 2025-11-20T11:00:00Z

=== Example Complete ===
```
