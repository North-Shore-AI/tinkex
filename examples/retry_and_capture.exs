defmodule Tinkex.RetryAndCaptureExample do
  @moduledoc false

  alias Tinkex.{Config, Error, Retry, RetryHandler, ServiceClient}
  alias Tinkex.Telemetry.Capture
  alias Tinkex.Telemetry.Reporter
  require Tinkex.Telemetry.Capture

  def run do
    handler_id = attach_retry_logger()
    {service, reporter} = start_service_and_reporter()

    try do
      result =
        Capture.capture_exceptions reporter: reporter, fatal?: true do
          Retry.with_retry(&flaky_operation/0,
            handler: RetryHandler.new(base_delay_ms: 200, jitter_pct: 0.0, max_retries: 2),
            telemetry_metadata: %{operation: "retry_and_capture"}
          )
          |> unwrap_retry_result()
        end

      IO.puts("Final result: #{inspect(result)}")
    after
      stop_service(service)
      Reporter.stop(reporter)
      detach(handler_id)
    end
  end

  defp flaky_operation do
    attempt = Process.get(:retry_demo_attempt, 0) + 1
    Process.put(:retry_demo_attempt, attempt)

    case attempt do
      n when n < 3 ->
        {:error, Error.new(:api_status, "synthetic 500 for retry demo", status: 500)}

      _ ->
        {:ok, "succeeded on attempt #{attempt}"}
    end
  end

  defp unwrap_retry_result({:ok, value}), do: value

  defp unwrap_retry_result({:error, %Error{} = error}) do
    raise "Retries exhausted: #{Error.format(error)}"
  end

  defp attach_retry_logger do
    handler_id = "tinkex-retry-demo-#{System.unique_integer([:positive])}"

    events = [
      [:tinkex, :retry, :attempt, :start],
      [:tinkex, :retry, :attempt, :retry],
      [:tinkex, :retry, :attempt, :stop],
      [:tinkex, :retry, :attempt, :failed]
    ]

    :telemetry.attach_many(handler_id, events, &__MODULE__.handle_retry_event/4, nil)

    handler_id
  end

  def handle_retry_event(event, measurements, metadata, _config) do
    IO.puts(format_retry_event(event, measurements, metadata))
  end

  defp format_retry_event(event, measurements, metadata) do
    duration_ms =
      case measurements do
        %{duration: duration} -> System.convert_time_unit(duration, :native, :millisecond)
        _ -> nil
      end

    delay =
      case measurements do
        %{delay_ms: delay_ms} -> " delay=#{delay_ms}ms"
        _ -> ""
      end

    result =
      cond do
        is_struct(metadata[:error], Error) -> " error=#{Error.format(metadata.error)}"
        metadata[:exception] -> " exception=#{Exception.message(metadata.exception)}"
        metadata[:result] -> " result=#{metadata.result}"
        true -> ""
      end

    duration_part = if duration_ms, do: " duration=#{duration_ms}ms", else: ""
    "[retry #{List.last(event)}] attempt=#{metadata.attempt}#{delay}#{duration_part}#{result}"
  end

  defp detach(handler_id), do: :telemetry.detach(handler_id)

  defp start_service_and_reporter do
    with api_key when is_binary(api_key) <- System.get_env("TINKER_API_KEY"),
         {:ok, config} <- build_config(api_key),
         {:ok, service} <- ServiceClient.start_link(config: config) do
      reporter =
        case ServiceClient.telemetry_reporter(service) do
          {:ok, pid} ->
            IO.puts("Telemetry reporter started for live session.")
            pid

          {:error, :disabled} ->
            IO.puts("Telemetry reporter disabled by TINKER_TELEMETRY=0.")
            nil
        end

      {service, reporter}
    else
      nil ->
        IO.puts("Telemetry reporter skipped (set TINKER_API_KEY to enable backend telemetry).")
        {nil, nil}

      {:error, reason} ->
        IO.puts("Telemetry reporter unavailable: #{inspect(reason)}")
        {nil, nil}
    end
  rescue
    exception ->
      IO.puts("Telemetry reporter skipped: #{Exception.message(exception)}")
      {nil, nil}
  end

  defp build_config(api_key) do
    base_url = System.get_env("TINKER_BASE_URL")
    {:ok, Config.new(api_key: api_key, base_url: base_url)}
  rescue
    exception -> {:error, exception}
  end

  defp stop_service(nil), do: :ok

  defp stop_service(pid) when is_pid(pid) do
    try do
      GenServer.stop(pid, :normal, 5_000)
    catch
      :exit, _ -> :ok
    end
  end
end

Tinkex.RetryAndCaptureExample.run()
