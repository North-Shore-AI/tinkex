defmodule Tinkex.Examples.WeightsInspection do
  @moduledoc """
  Example demonstrating training run and checkpoint inspection APIs.

  Shows how to:
  - List and inspect training runs
  - List checkpoints for training runs
  - Get checkpoint archive URLs for downloads
  - Resolve training runs directly from checkpoint tinker paths
  - Inspect samplers and validate LoRA rank expectations
  - Inspect richer weights metadata including train flags
  """

  alias Tinkex.{ServiceClient, RestClient, Config}

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
    first_run_id = list_training_runs(rest_client)

    # List user checkpoints
    first_checkpoint_path = list_user_checkpoints(rest_client)

    # If a training run ID is provided, list its checkpoints
    if run_id = System.get_env("TINKER_RUN_ID") || first_run_id do
      list_run_checkpoints(rest_client, run_id)
    end

    checkpoint_path = System.get_env("TINKER_CHECKPOINT_PATH") || first_checkpoint_path

    if checkpoint_path do
      inspect_checkpoint_workflow(
        rest_client,
        checkpoint_path,
        parse_optional_int(System.get_env("TINKER_EXPECTED_RANK"))
      )
    end

    if sampler_id = System.get_env("TINKER_SAMPLER_ID") do
      inspect_sampler(rest_client, sampler_id)
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp list_training_runs(rest_client) do
    IO.puts("--- Training Runs ---")

    case RestClient.list_training_runs(
           rest_client,
           limit: 10,
           offset: 0,
           access_scope: "accessible"
         ) do
      {:ok, %Tinkex.Types.TrainingRunsResponse{} = response} ->
        runs = response.training_runs || []
        IO.puts("Found #{length(runs)} training runs:\n")

        Enum.each(runs, fn %Tinkex.Types.TrainingRun{} = run ->
          IO.puts("  #{run.training_run_id}")
          IO.puts("    Base Model: #{run.base_model || "N/A"}")
          IO.puts("    Is LoRA: #{run.is_lora}, Rank: #{run.lora_rank || "N/A"}")
          IO.puts("    Corrupted: #{run.corrupted || false}")
          IO.puts("    Last Checkpoint: #{format_checkpoint(run.last_checkpoint)}")
          IO.puts("    Owner: #{run.model_owner || "N/A"}")
          IO.puts("")
        end)

        if length(runs) > 0 do
          inspect_training_run(rest_client, hd(runs).training_run_id)
          hd(runs).training_run_id
        else
          nil
        end

      {:ok, response} ->
        runs = response["training_runs"] || response[:training_runs] || []
        IO.puts("Found #{length(runs)} training runs:\n")

        Enum.each(runs, fn run ->
          IO.puts("  #{run["training_run_id"] || run[:training_run_id]}")
        end)

        runs
        |> List.first()
        |> case do
          nil -> nil
          run -> run["training_run_id"] || run[:training_run_id]
        end

      {:error, error} ->
        IO.puts("Error listing training runs: #{inspect(error)}")
        nil
    end
  end

  defp inspect_training_run(rest_client, run_id) do
    IO.puts("\n--- Training Run Details: #{run_id} ---")

    case RestClient.get_training_run(rest_client, run_id, access_scope: "accessible") do
      {:ok, %Tinkex.Types.TrainingRun{} = run} ->
        IO.puts("  ID: #{run.training_run_id}")
        IO.puts("  Base Model: #{run.base_model || "N/A"}")
        IO.puts("  Is LoRA: #{run.is_lora}")
        IO.puts("  LoRA Rank: #{run.lora_rank || "N/A"}")
        IO.puts("  Corrupted: #{run.corrupted || false}")
        IO.puts("  Last Checkpoint: #{format_checkpoint(run.last_checkpoint)}")
        IO.puts("  Last Sampler Checkpoint: #{format_checkpoint(run.last_sampler_checkpoint)}")
        IO.puts("  Last Request: #{run.last_request_time || "N/A"}")
        IO.puts("  Owner: #{run.model_owner || "N/A"}")

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
          IO.puts("    Expires: #{checkpoint.expires_at || "never"}")
          IO.puts("")
        end)

        case checkpoints do
          [first | _] -> first.tinker_path
          _ -> nil
        end

      {:error, error} ->
        IO.puts("Error listing checkpoints: #{inspect(error)}")
        nil
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

          IO.puts("    Expires: #{checkpoint.expires_at || "never"}")
          IO.puts("")
        end)

      {:error, error} ->
        IO.puts("Error listing run checkpoints: #{inspect(error)}")
    end
  end

  defp format_checkpoint(nil), do: "none"
  defp format_checkpoint(%Tinkex.Types.Checkpoint{} = ckpt), do: ckpt.tinker_path
  defp format_checkpoint(other), do: inspect(other)

  defp inspect_checkpoint_workflow(rest_client, path, expected_rank) do
    inspect_weights_metadata(rest_client, path, expected_rank)
    inspect_training_run_by_checkpoint(rest_client, path)
    inspect_archive_url(rest_client, path)
  end

  defp inspect_weights_metadata(rest_client, path, expected_rank) do
    IO.puts("\n--- Weights Metadata: #{path} ---")

    case RestClient.get_weights_info_by_tinker_path(rest_client, path) do
      {:ok, info} ->
        IO.puts("  Base Model: #{info.base_model}")
        IO.puts("  Is LoRA: #{info.is_lora}")
        IO.puts("  LoRA Rank: #{info.lora_rank || "N/A"}")
        IO.puts("  Train attention: #{inspect(info.train_attn)}")
        IO.puts("  Train MLP: #{inspect(info.train_mlp)}")
        IO.puts("  Train unembed: #{inspect(info.train_unembed)}")
        validate_expected_rank(expected_rank, info.lora_rank)

      {:error, error} ->
        IO.puts("Error getting weights metadata: #{inspect(error)}")
    end
  end

  defp inspect_training_run_by_checkpoint(rest_client, path) do
    IO.puts("\n--- Training Run From Checkpoint Path ---")

    case RestClient.get_training_run_by_tinker_path(
           rest_client,
           path,
           access_scope: "accessible"
         ) do
      {:ok, run} ->
        IO.puts("  Run ID: #{run.training_run_id}")
        IO.puts("  Owner: #{run.model_owner || "N/A"}")
        IO.puts("  Last Checkpoint: #{format_checkpoint(run.last_checkpoint)}")
        IO.puts("  Last Sampler Checkpoint: #{format_checkpoint(run.last_sampler_checkpoint)}")

      {:error, error} ->
        IO.puts("Error resolving training run from checkpoint path: #{inspect(error)}")
    end
  end

  defp inspect_archive_url(rest_client, path) do
    IO.puts("\n--- Archive URL ---")

    case RestClient.get_checkpoint_archive_url_by_tinker_path(rest_client, path) do
      {:ok, response} ->
        IO.puts("  URL: #{response.url}")
        IO.puts("  Expires: #{inspect(response.expires)}")

      {:error, error} ->
        IO.puts("Error fetching archive URL: #{inspect(error)}")
    end
  end

  defp inspect_sampler(rest_client, sampler_id) do
    IO.puts("\n--- Sampler Metadata: #{sampler_id} ---")

    case RestClient.get_sampler(rest_client, sampler_id) do
      {:ok, sampler} ->
        IO.puts("  Base Model: #{sampler.base_model}")
        IO.puts("  Model Path: #{sampler.model_path || "none"}")

      {:error, error} ->
        IO.puts("Error fetching sampler metadata: #{inspect(error)}")
    end
  end

  defp validate_expected_rank(nil, _actual), do: :ok

  defp validate_expected_rank(expected, actual) when expected == actual do
    IO.puts("  Rank validation: expected #{expected}, got #{actual} (match)")
  end

  defp validate_expected_rank(expected, actual) do
    IO.puts("  Rank validation: expected #{expected}, got #{inspect(actual)} (mismatch)")
  end

  defp parse_optional_int(nil), do: nil

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end

Tinkex.Examples.WeightsInspection.run()
