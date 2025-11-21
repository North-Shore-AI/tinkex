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
        total =
          if response.cursor,
            do: response.cursor["total_count"],
            else: length(response.checkpoints)

        IO.puts("Found #{length(response.checkpoints)} of #{total || "?"} checkpoints:\n")

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

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"
end

Tinkex.Examples.CheckpointsManagement.run()
