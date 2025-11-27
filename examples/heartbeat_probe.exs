#!/usr/bin/env elixir

api_key = System.get_env("TINKER_API_KEY")

base_url =
  System.get_env("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod")

unless api_key do
  IO.puts("TINKER_API_KEY is required to run the heartbeat probe.")
  System.halt(1)
end

{:ok, _} = Application.ensure_all_started(:tinkex)

config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

session_request = %{
  tags: ["tinkex-elixir", "heartbeat-probe"],
  user_metadata: %{},
  sdk_version: Tinkex.Version.current(),
  type: "create_session"
}

with {:ok, %{"session_id" => session_id}} <-
       Tinkex.API.Session.create(session_request, config: config) do
  IO.puts("Created session: #{session_id}")

  heartbeat_body = %{session_id: session_id, type: "session_heartbeat"}
  opts = [config: config, pool_type: :session, max_retries: 0]

  case Tinkex.API.post("/api/v1/session_heartbeat", heartbeat_body, opts) do
    {:ok, _} ->
      IO.puts("/api/v1/session_heartbeat => 200 (ok)")

    other ->
      IO.puts("Unexpected response from /api/v1/session_heartbeat: #{inspect(other)}")
      System.halt(1)
  end

  case Tinkex.API.post("/api/v1/heartbeat", heartbeat_body, opts) do
    {:error, %Tinkex.Error{status: 404}} ->
      IO.puts("/api/v1/heartbeat => 404 (expected)")

    {:ok, _} ->
      IO.puts("/api/v1/heartbeat unexpectedly returned 200")
      System.halt(1)

    {:error, %Tinkex.Error{status: status} = error} ->
      IO.puts("/api/v1/heartbeat returned #{status}: #{Tinkex.Error.format(error)}")
      System.halt(1)

    other ->
      IO.puts("Unexpected response from /api/v1/heartbeat: #{inspect(other)}")
      System.halt(1)
  end
else
  other ->
    IO.puts("Failed to create session: #{inspect(other)}")
    System.halt(1)
end
