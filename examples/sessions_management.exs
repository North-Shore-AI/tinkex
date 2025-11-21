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
