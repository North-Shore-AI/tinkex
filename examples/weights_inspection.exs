defmodule Tinkex.Examples.WeightsInspection do
  @moduledoc """
  Example demonstrating weights and sampler inspection APIs.

  Shows how to:
  - Inspect checkpoint metadata (base model, LoRA rank, etc.)
  - Query sampler state and loaded weights
  - List and inspect training runs
  - Validate checkpoint compatibility before loading
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

    # If a checkpoint path is provided, inspect it
    if checkpoint_path = System.get_env("TINKER_CHECKPOINT_PATH") do
      inspect_checkpoint(config, checkpoint_path)
    else
      # Try to find a checkpoint to inspect
      maybe_inspect_first_checkpoint(rest_client, config)
    end

    # If a sampler ID is provided, query its state
    if sampler_id = System.get_env("TINKER_SAMPLER_ID") do
      inspect_sampler(config, sampler_id)
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
          run_id = run["id"] || run[:id]
          status = run["status"] || run[:status]
          base_model = run["base_model"] || run[:base_model]

          IO.puts("  #{run_id}")
          IO.puts("    Status: #{status || "N/A"}")
          IO.puts("    Base Model: #{base_model || "N/A"}")
          IO.puts("")
        end)

        # Inspect first run in detail if available
        if length(runs) > 0 do
          first_run = hd(runs)
          run_id = first_run["id"] || first_run[:id]
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
        IO.puts("  ID: #{run["id"] || run[:id]}")
        IO.puts("  Status: #{run["status"] || run[:status] || "N/A"}")
        IO.puts("  Base Model: #{run["base_model"] || run[:base_model] || "N/A"}")
        IO.puts("  Created: #{run["created_at"] || run[:created_at] || "N/A"}")

        if lora_rank = run["lora_rank"] || run[:lora_rank] do
          IO.puts("  LoRA Rank: #{lora_rank}")
        end

      {:error, error} ->
        IO.puts("Error getting training run: #{inspect(error)}")
    end
  end

  defp maybe_inspect_first_checkpoint(rest_client, config) do
    IO.puts("\n--- Looking for checkpoints to inspect ---")

    case RestClient.list_user_checkpoints(rest_client, limit: 5) do
      {:ok, response} ->
        checkpoints = response.checkpoints || []

        if length(checkpoints) > 0 do
          first = hd(checkpoints)
          IO.puts("Found #{length(checkpoints)} checkpoint(s), inspecting first one...")
          inspect_checkpoint(config, first.tinker_path)
        else
          IO.puts(
            "No checkpoints found. Set TINKER_CHECKPOINT_PATH to inspect a specific checkpoint."
          )
        end

      {:error, error} ->
        IO.puts("Error listing checkpoints: #{inspect(error)}")
    end
  end

  defp inspect_checkpoint(config, tinker_path) do
    IO.puts("\n--- Checkpoint Inspection: #{tinker_path} ---")

    case Rest.get_weights_info_by_tinker_path(config, tinker_path) do
      {:ok, weights_info} ->
        IO.puts("  Base Model: #{weights_info.base_model}")
        IO.puts("  Is LoRA: #{weights_info.is_lora}")

        if weights_info.lora_rank do
          IO.puts("  LoRA Rank: #{weights_info.lora_rank}")
        end

        # Example: Validate compatibility
        validate_compatibility(weights_info)

        # Also get training run info from the path
        inspect_training_run_from_path(config, tinker_path)

      {:error, error} ->
        IO.puts("Error inspecting checkpoint: #{inspect(error)}")
    end
  end

  defp validate_compatibility(weights_info) do
    IO.puts("\n  Compatibility Check:")

    expected_rank = System.get_env("TINKER_EXPECTED_RANK")

    cond do
      expected_rank == nil ->
        IO.puts("    (Set TINKER_EXPECTED_RANK to validate LoRA rank compatibility)")

      not weights_info.is_lora ->
        IO.puts("    WARNING: Checkpoint is not LoRA, cannot validate rank")

      weights_info.lora_rank == String.to_integer(expected_rank) ->
        IO.puts("    OK: LoRA rank #{weights_info.lora_rank} matches expected #{expected_rank}")

      true ->
        IO.puts("    MISMATCH: LoRA rank #{weights_info.lora_rank} != expected #{expected_rank}")
    end
  end

  defp inspect_training_run_from_path(config, tinker_path) do
    IO.puts("\n  Training Run (from path):")

    case Rest.get_training_run_by_tinker_path(config, tinker_path) do
      {:ok, run} ->
        IO.puts("    Run ID: #{run["id"] || run[:id]}")
        IO.puts("    Status: #{run["status"] || run[:status] || "N/A"}")

      {:error, error} ->
        IO.puts("    Could not fetch training run: #{inspect(error)}")
    end
  end

  defp inspect_sampler(config, sampler_id) do
    IO.puts("\n--- Sampler Inspection: #{sampler_id} ---")

    case Rest.get_sampler(config, sampler_id) do
      {:ok, sampler_info} ->
        IO.puts("  Sampler ID: #{sampler_info.sampler_id}")
        IO.puts("  Base Model: #{sampler_info.base_model}")

        if sampler_info.model_path do
          IO.puts("  Loaded Weights: #{sampler_info.model_path}")

          # If weights are loaded, we can inspect them too
          IO.puts("\n  Inspecting loaded weights...")
          inspect_checkpoint(config, sampler_info.model_path)
        else
          IO.puts("  Loaded Weights: (none - using base model)")
        end

      {:error, error} ->
        IO.puts("Error inspecting sampler: #{inspect(error)}")
    end
  end
end

Tinkex.Examples.WeightsInspection.run()
