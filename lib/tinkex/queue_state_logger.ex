defmodule Tinkex.QueueStateLogger do
  @moduledoc """
  Shared logging utilities for queue state changes.

  Provides human-readable messages matching Python SDK behavior,
  with debouncing to avoid log spam. Used by `SamplingClient` and
  `TrainingClient` to automatically log when queue state transitions
  indicate rate limiting or capacity issues. Server-supplied reasons
  take precedence when available.

  ## Debouncing

  Logs are rate-limited to once per 60 seconds (by default) per client
  to prevent spam during sustained rate limiting. The `maybe_log/5`
  function handles this automatically.

  ## Message Format

  Messages follow the Python SDK format:

      [warning] Sampling is paused for sampler abc-123. Reason: concurrent sampler weights limit hit
      [warning] Training is paused for model-xyz. Reason: Tinker backend is running short on capacity, please wait

  ## Client-Specific Reasons

  - **SamplingClient**: "concurrent sampler weights limit hit" for rate limits
  - **TrainingClient**: "concurrent training clients rate limit hit" for rate limits
  - Both use "Tinker backend is running short on capacity, please wait" for capacity limits
  """

  require Logger

  @log_interval_ms 60_000

  @type client_type :: :sampling | :training
  @type queue_state :: :active | :paused_rate_limit | :paused_capacity | :unknown

  @doc """
  Log a queue state change with appropriate human-readable reason.

  Does not log for `:active` state. For non-active states, logs a warning
  with a human-readable message including the identifier and reason. When
  provided, `server_reason` takes precedence over client defaults.

  ## Parameters

  - `queue_state` - One of `:active`, `:paused_rate_limit`, `:paused_capacity`, `:unknown`
  - `client_type` - Either `:sampling` or `:training`
  - `identifier` - Session ID for sampling, model ID for training
  - `server_reason` - Optional server-supplied reason string

  ## Examples

      iex> Tinkex.QueueStateLogger.log_state_change(:paused_rate_limit, :sampling, "session-123")
      :ok
      # Logs: [warning] Sampling is paused for session-123. Reason: concurrent sampler weights limit hit

  """
  @spec log_state_change(queue_state(), client_type(), String.t(), String.t() | nil) :: :ok
  def log_state_change(queue_state, client_type, identifier, server_reason \\ nil)

  def log_state_change(:active, _client_type, _identifier, _server_reason), do: :ok

  def log_state_change(queue_state, client_type, identifier, server_reason) do
    reason = resolve_reason(queue_state, client_type, server_reason)
    action = client_type_name(client_type)

    Logger.warning("#{action} is paused for #{identifier}. Reason: #{reason}")
  end

  @doc """
  Resolve reason string, preferring a non-empty server-supplied value.
  """
  @spec resolve_reason(queue_state(), client_type(), String.t() | nil) :: String.t()
  def resolve_reason(_queue_state, _client_type, reason)
      when is_binary(reason) and byte_size(reason) > 0 do
    reason
  end

  def resolve_reason(queue_state, client_type, _reason) do
    reason_for_state(queue_state, client_type)
  end

  @doc """
  Check if enough time has passed since last log.

  Returns `true` if logging should occur, `false` if still within debounce interval.

  ## Parameters

  - `last_logged` - Timestamp (monotonic milliseconds) of last log, or `nil` if never logged
  - `interval` - Minimum milliseconds between logs (default: 60,000)

  ## Examples

      iex> Tinkex.QueueStateLogger.should_log?(nil)
      true

      iex> old_time = System.monotonic_time(:millisecond) - 61_000
      iex> Tinkex.QueueStateLogger.should_log?(old_time)
      true

      iex> recent_time = System.monotonic_time(:millisecond) - 30_000
      iex> Tinkex.QueueStateLogger.should_log?(recent_time)
      false

  """
  @spec should_log?(integer() | nil, integer()) :: boolean()
  def should_log?(last_logged, interval \\ @log_interval_ms)

  def should_log?(nil, _interval), do: true

  def should_log?(last_logged, interval) when is_integer(last_logged) do
    System.monotonic_time(:millisecond) - last_logged >= interval
  end

  @doc """
  Get human-readable reason for queue state.

  Returns different messages for sampling vs training rate limits
  to match Python SDK behavior.

  ## Examples

      iex> Tinkex.QueueStateLogger.reason_for_state(:paused_rate_limit, :sampling)
      "concurrent sampler weights limit hit"

      iex> Tinkex.QueueStateLogger.reason_for_state(:paused_rate_limit, :training)
      "concurrent training clients rate limit hit"

      iex> Tinkex.QueueStateLogger.reason_for_state(:paused_capacity, :sampling)
      "Tinker backend is running short on capacity, please wait"

  """
  @spec reason_for_state(queue_state(), client_type()) :: String.t()
  def reason_for_state(:paused_rate_limit, :sampling), do: "concurrent sampler weights limit hit"

  def reason_for_state(:paused_rate_limit, :training),
    do: "concurrent training clients rate limit hit"

  def reason_for_state(:paused_capacity, _),
    do: "Tinker backend is running short on capacity, please wait"

  def reason_for_state(_, _), do: "unknown"

  @doc """
  Combined debouncing and logging in a single call.

  Checks if enough time has passed since `last_logged_at`, and if so,
  logs the queue state change and returns the new timestamp. Otherwise,
  returns the original timestamp unchanged.

  Does not log for `:active` state regardless of timestamp.

  ## Parameters

  - `queue_state` - The current queue state
  - `client_type` - Either `:sampling` or `:training`
  - `identifier` - Session ID or model ID
  - `last_logged_at` - Timestamp of last log, or `nil`
  - `server_reason` - Optional server-supplied reason to log

  ## Returns

  The timestamp to store for next comparison:
  - If logged: new current timestamp
  - If not logged: same `last_logged_at` value

  ## Examples

      iex> old_time = System.monotonic_time(:millisecond) - 61_000
      iex> new_time = Tinkex.QueueStateLogger.maybe_log(:paused_rate_limit, :sampling, "sess-1", old_time)
      iex> new_time > old_time
      true
      # Also logs the warning

      iex> recent = System.monotonic_time(:millisecond) - 30_000
      iex> same = Tinkex.QueueStateLogger.maybe_log(:paused_rate_limit, :sampling, "sess-1", recent)
      iex> same == recent
      true
      # No log output

  """
  @spec maybe_log(queue_state(), client_type(), String.t(), integer() | nil, String.t() | nil) ::
          integer() | nil
  def maybe_log(queue_state, client_type, identifier, last_logged_at, server_reason \\ nil)

  def maybe_log(:active, _client_type, _identifier, last_logged_at, _server_reason),
    do: last_logged_at

  def maybe_log(queue_state, client_type, identifier, last_logged_at, server_reason) do
    if should_log?(last_logged_at) do
      log_state_change(queue_state, client_type, identifier, server_reason)
      System.monotonic_time(:millisecond)
    else
      last_logged_at
    end
  end

  defp client_type_name(:sampling), do: "Sampling"
  defp client_type_name(:training), do: "Training"
end
