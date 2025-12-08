defmodule Tinkex.Telemetry.Reporter.Backoff do
  @moduledoc """
  Retry and backoff calculation logic for telemetry reporter.

  Implements exponential backoff with jitter for failed telemetry sends.
  """

  require Logger
  alias Tinkex.API.Telemetry, as: TelemetryAPI

  @doc """
  Send a batch of events with retry logic and exponential backoff.

  Attempts to send the request up to `max_retries` times. On failure,
  waits with exponential backoff before retrying.

  Parameters:
    * `request` - the telemetry request map
    * `state` - the reporter state (contains config, timeouts, retry settings)
    * `mode` - `:sync` or `:async` send mode
    * `attempt` - current attempt number (0-indexed, defaults to 0)

  Returns `:ok` on success, `:error` after all retries exhausted.
  """
  @spec send_batch_with_retry(map(), map(), :sync | :async, non_neg_integer()) ::
          :ok | :error
  def send_batch_with_retry(request, state, mode, attempt \\ 0) do
    result =
      try do
        opts = [config: state.config, timeout: state.http_timeout_ms]

        case mode do
          :sync -> TelemetryAPI.send_sync(request, opts)
          :async -> TelemetryAPI.send(request, opts)
        end
      rescue
        exception ->
          {:error, exception}
      end

    case result do
      {:ok, _} ->
        :ok

      :ok ->
        :ok

      {:error, reason} when attempt < state.max_retries ->
        delay = calculate_backoff_delay(attempt, state.retry_base_delay_ms)

        Logger.warning(
          "Telemetry send failed (attempt #{attempt + 1}), retrying in #{delay}ms: #{inspect(reason)}"
        )

        Process.sleep(delay)
        send_batch_with_retry(request, state, mode, attempt + 1)

      {:error, reason} ->
        Logger.warning(
          "Telemetry send failed after #{state.max_retries} retries: #{inspect(reason)}"
        )

        :error
    end
  end

  @doc """
  Calculate exponential backoff delay with jitter.

  Formula: `base_delay * 2^attempt + jitter`

  Where jitter is a random value up to 10% of the base delay.

  Examples:
    * attempt 0, base 1000ms -> 1000ms + (0-100ms jitter) = 1000-1100ms
    * attempt 1, base 1000ms -> 2000ms + (0-200ms jitter) = 2000-2200ms
    * attempt 2, base 1000ms -> 4000ms + (0-400ms jitter) = 4000-4400ms
  """
  @spec calculate_backoff_delay(non_neg_integer(), pos_integer()) :: pos_integer()
  def calculate_backoff_delay(attempt, base_delay_ms) do
    # Exponential backoff: base * 2^attempt with some jitter
    base = base_delay_ms * :math.pow(2, attempt)
    jitter = :rand.uniform(round(base * 0.1))
    round(base + jitter)
  end
end
