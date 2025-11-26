defmodule Tinkex.Examples.WeightsInspection do
  @moduledoc """
  Example demonstrating training run and checkpoint inspection APIs.

  Shows how to:
  - List and inspect training runs
  - List checkpoints for training runs
  - Get checkpoint archive URLs for downloads
  """

  alias Tinkex.{ServiceClient, RestClient, Config}
  alias Tinkex.API.Rest

  def run do
    IO.puts("=== Tinkex Weights Inspection Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    base_url =
      System.get_env("TINKER_BASE_URL") ||
        Application.get_env(
          :tinkex,
          :base_url,
          "https://tinker.thinkingmachines.dev/services/tinker-prod"
        )

    config =
      Config.new(
        api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
        base_url: base_url
      )

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    # List training runs
    list_training_runs(config)

    # List user checkpoints
    list_user_checkpoints(rest_client)

    # If a training run ID is provided, list its checkpoints
    if run_id = System.get_env("TINKER_RUN_ID") do
      list_run_checkpoints(rest_client, run_id)
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp list_training_runs(config) do
    IO.puts("--- Training Runs ---")

    case Rest.list_training_runs(config, 10, 0) do
      {:ok, response} ->
        runs = response["training_runs"] || response[:training_runs] || []
        IO.puts("Found #{length(runs)} training runs:\n")

        Enum.each(runs, fn run ->
          run_id = run["training_run_id"] || run[:training_run_id]
          base_model = run["base_model"] || run[:base_model]
          is_lora = run["is_lora"] || run[:is_lora]
          lora_rank = run["lora_rank"] || run[:lora_rank]
          corrupted = run["corrupted"] || run[:corrupted]
          last_checkpoint = run["last_checkpoint"] || run[:last_checkpoint]
          model_owner = run["model_owner"] || run[:model_owner]

          IO.puts("  #{run_id}")
          IO.puts("    Base Model: #{base_model || "N/A"}")
          IO.puts("    Is LoRA: #{is_lora}, Rank: #{lora_rank || "N/A"}")
          IO.puts("    Corrupted: #{corrupted || false}")
          IO.puts("    Last Checkpoint: #{last_checkpoint || "none"}")
          IO.puts("    Owner: #{model_owner || "N/A"}")
          IO.puts("")
        end)

        # Inspect first run in detail if available
        if length(runs) > 0 do
          first_run = hd(runs)
          run_id = first_run["training_run_id"] || first_run[:training_run_id]
          inspect_training_run(config, run_id)
        end

      {:error, error} ->
        IO.puts("Error listing training runs: #{inspect(error)}")
    end
  end

  defp inspect_training_run(config, run_id) do
    IO.puts("\n--- Training Run Details: #{run_id} ---")

    case Rest.get_training_run(config, run_id) do
      {:ok, run} ->
        IO.puts("  ID: #{run["training_run_id"] || run[:training_run_id]}")
        IO.puts("  Base Model: #{run["base_model"] || run[:base_model] || "N/A"}")
        IO.puts("  Is LoRA: #{run["is_lora"] || run[:is_lora]}")
        IO.puts("  LoRA Rank: #{run["lora_rank"] || run[:lora_rank] || "N/A"}")
        IO.puts("  Corrupted: #{run["corrupted"] || run[:corrupted] || false}")
        IO.puts("  Last Checkpoint: #{run["last_checkpoint"] || run[:last_checkpoint] || "none"}")

        IO.puts(
          "  Last Sampler Checkpoint: #{run["last_sampler_checkpoint"] || run[:last_sampler_checkpoint] || "none"}"
        )

        IO.puts("  Last Request: #{run["last_request_time"] || run[:last_request_time] || "N/A"}")
        IO.puts("  Owner: #{run["model_owner"] || run[:model_owner] || "N/A"}")

      {:error, error} ->
        IO.puts("Error getting training run: #{inspect(error)}")
    end
  end

  defp list_user_checkpoints(rest_client) do
    IO.puts("\n--- User Checkpoints ---")

    case RestClient.list_user_checkpoints(rest_client, limit: 10) do
      {:ok, response} ->
        checkpoints = response.checkpoints || []
        IO.puts("Found #{length(checkpoints)} checkpoint(s):\n")

        Enum.each(checkpoints, fn checkpoint ->
          IO.puts("  #{checkpoint.tinker_path}")
          IO.puts("    Type: #{checkpoint.checkpoint_type}")
          IO.puts("    ID: #{checkpoint.checkpoint_id}")

          if checkpoint.size_bytes do
            size_mb = checkpoint.size_bytes / (1024 * 1024)
            IO.puts("    Size: #{Float.round(size_mb, 2)} MB")
          end

          IO.puts("    Time: #{checkpoint.time}")
          IO.puts("")
        end)

      {:error, error} ->
        IO.puts("Error listing checkpoints: #{inspect(error)}")
    end
  end

  defp list_run_checkpoints(rest_client, run_id) do
    IO.puts("\n--- Checkpoints for Run: #{run_id} ---")

    case RestClient.list_checkpoints(rest_client, run_id) do
      {:ok, response} ->
        checkpoints = response.checkpoints || []
        IO.puts("Found #{length(checkpoints)} checkpoint(s):\n")

        Enum.each(checkpoints, fn checkpoint ->
          IO.puts("  #{checkpoint.checkpoint_id}")
          IO.puts("    Path: #{checkpoint.tinker_path}")
          IO.puts("    Type: #{checkpoint.checkpoint_type}")

          if checkpoint.size_bytes do
            size_mb = checkpoint.size_bytes / (1024 * 1024)
            IO.puts("    Size: #{Float.round(size_mb, 2)} MB")
          end

          IO.puts("")
        end)

      {:error, error} ->
        IO.puts("Error listing run checkpoints: #{inspect(error)}")
    end
  end
end

Tinkex.Examples.WeightsInspection.run()
