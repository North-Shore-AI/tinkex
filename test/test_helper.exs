require Logger

ExUnit.start()
{:ok, _} = Application.ensure_all_started(:supertester)

telemetry_handler = "supertester-phase2"
event_name = [:supertester, :concurrent, :scenario, :stop]

handler = fn _event, %{duration_ms: duration}, metadata, _ ->
  Logger.info(
    "[supertester] #{metadata.scenario_id} finished in #{duration}ms (#{metadata[:status] || :ok})"
  )
end

case :telemetry.attach(telemetry_handler, event_name, handler, nil) do
  :ok -> :ok
  {:error, :already_exists} -> :ok
end
