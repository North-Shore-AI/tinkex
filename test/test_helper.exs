defmodule Tinkex.TestTelemetryHandler do
  require Logger

  def handle(_event, %{duration_ms: duration}, metadata, _config) do
    Logger.info(
      "[supertester] #{metadata.scenario_id} finished in #{duration}ms (#{metadata[:status] || :ok})"
    )
  end
end

ExUnit.start()
{:ok, _} = Application.ensure_all_started(:supertester)
{:ok, _} = Application.ensure_all_started(:tinkex)

ExUnit.configure(exclude: [slow: true])

System.put_env("TINKER_TELEMETRY", "0")

Code.require_file("support/http_case.ex", __DIR__)
Code.require_file("support/api_worker.ex", __DIR__)
Code.require_file("support/recovery_stubs.exs", __DIR__)
Code.require_file("support/recovery_mocks.exs", __DIR__)

telemetry_handler = "supertester-phase2"
event_name = [:supertester, :concurrent, :scenario, :stop]

case :telemetry.attach(telemetry_handler, event_name, &Tinkex.TestTelemetryHandler.handle/4, nil) do
  :ok -> :ok
  {:error, :already_exists} -> :ok
end
