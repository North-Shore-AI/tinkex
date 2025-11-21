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

    # Get checkpoint paths from environment or use single base model
    checkpoint_paths =
      case System.get_env("TINKER_CHECKPOINT_PATHS") do
        nil -> []
        paths -> String.split(paths, ",")
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

    base_model = System.get_env("TINKER_BASE_MODEL") || "meta-llama/Llama-3.2-1B"

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
    tasks =
      Enum.map(checkpoint_paths, fn path ->
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

    successes =
      Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    IO.puts("\nSuccess: #{successes}/#{length(results)}")
  end
end

Tinkex.Examples.AsyncClientCreation.run()
