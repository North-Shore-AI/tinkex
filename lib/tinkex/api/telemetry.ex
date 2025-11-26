defmodule Tinkex.API.Telemetry do
  @moduledoc """
  Telemetry reporting endpoints.

  Uses :telemetry pool to prevent telemetry from starving critical operations.
  Pool size: 5 connections.

  ## Task Supervision

  Tasks spawned by `send/2` are not supervised. Failures are logged
  and ignored. This is intentional - telemetry should never block or
  fail critical operations.
  """

  require Logger

  @default_timeout_ms 5_000

  @doc """
  Send telemetry asynchronously (fire and forget).

  Spawns a Task to send telemetry without blocking the caller.
  Returns :ok immediately; failures are logged but not propagated.

  Options:
    * `:config` - Tinkex.Config.t() (required)
    * `:timeout` - HTTP timeout in milliseconds (default: 5000)
  """
  @spec send(map(), keyword()) :: :ok
  def send(request, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    Task.start(fn ->
      try do
        opts =
          opts
          |> Keyword.put(:pool_type, :telemetry)
          |> Keyword.put(:max_retries, 1)
          |> Keyword.put(:timeout, timeout)

        case Tinkex.API.post("/api/v1/telemetry", request, opts) do
          {:ok, _} ->
            :ok

          {:error, error} ->
            Logger.warning("Telemetry send failed: #{inspect(error)}")
        end
      rescue
        exception ->
          Logger.error(
            "Telemetry task crashed: #{Exception.format(:error, exception, __STACKTRACE__)}"
          )
      end
    end)

    :ok
  end

  @doc """
  Send telemetry synchronously (for testing or flush operations).

  Blocks until the telemetry request completes. Use this in tests
  to verify telemetry behavior or during graceful shutdown.

  Options:
    * `:config` - Tinkex.Config.t() (required)
    * `:timeout` - HTTP timeout in milliseconds (default: 5000)
  """
  @spec send_sync(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def send_sync(request, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    opts =
      opts
      |> Keyword.put(:pool_type, :telemetry)
      |> Keyword.put(:max_retries, 1)
      |> Keyword.put(:timeout, timeout)

    Tinkex.API.post("/api/v1/telemetry", request, opts)
  end
end
