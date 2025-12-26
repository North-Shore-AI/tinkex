defmodule Tinkex.API.RetryConfig do
  @moduledoc """
  Retry configuration with Python SDK parity.

  Implements retry delay calculation and status code classification
  matching the Python SDK's `_base_client.py`.

  ## Python SDK Reference

  From `tinker/_constants.py`:
  - `INITIAL_RETRY_DELAY = 0.5` (seconds)
  - `MAX_RETRY_DELAY = 10.0` (seconds)

  From `tinker/_base_client.py` `_calculate_retry_timeout`:
  - Exponential backoff: `sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)`
  - Jitter: `jitter = 1 - 0.25 * random()` (range 0.75-1.0)
  - Final: `timeout = sleep_seconds * jitter`

  From `tinker/_base_client.py` `_should_retry`:
  - Retries on status codes: 408, 409, 429, 5xx
  - No wall-clock timeout; governed by `max_retries` only
  """

  # Python SDK constants from _constants.py
  @initial_retry_delay_ms 500
  @max_retry_delay_ms 10_000

  # Python jitter range: 1 - 0.25 * random() gives [0.75, 1.0]
  @jitter_min 0.75
  @jitter_max 1.0

  @type t :: %__MODULE__{
          max_retries: non_neg_integer(),
          initial_delay_ms: pos_integer(),
          max_delay_ms: pos_integer()
        }

  @default_max_retries 10

  defstruct max_retries: @default_max_retries,
            initial_delay_ms: @initial_retry_delay_ms,
            max_delay_ms: @max_retry_delay_ms

  @doc """
  Create a new retry config with the given options.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      initial_delay_ms: Keyword.get(opts, :initial_delay_ms, @initial_retry_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @max_retry_delay_ms)
    }
  end

  @doc """
  Calculate retry delay for the given attempt number.

  Uses Python SDK formula:
  - Base delay: `initial_delay * 2^attempt`
  - Capped at max_delay
  - Jitter: multiplied by random value in [0.75, 1.0]

  ## Examples

      iex> delay = Tinkex.API.RetryConfig.retry_delay(0)
      iex> delay >= 375 and delay <= 500
      true

  """
  @spec retry_delay(non_neg_integer()) :: non_neg_integer()
  def retry_delay(attempt) do
    retry_delay(attempt, @initial_retry_delay_ms, @max_retry_delay_ms)
  end

  @doc """
  Calculate retry delay with custom initial and max delays.
  """
  @spec retry_delay(non_neg_integer(), pos_integer(), pos_integer()) :: non_neg_integer()
  def retry_delay(attempt, initial_delay_ms, max_delay_ms) do
    # Python: sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)
    base_delay = initial_delay_ms * :math.pow(2, attempt)
    capped_delay = min(base_delay, max_delay_ms)

    # Python: jitter = 1 - 0.25 * random() -> range [0.75, 1.0]
    jitter = @jitter_min + :rand.uniform() * (@jitter_max - @jitter_min)

    round(capped_delay * jitter)
  end

  @doc """
  Check if a status code is retryable per Python SDK rules.

  Python retries on: 408, 409, 429, 5xx
  """
  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(408), do: true
  def retryable_status?(409), do: true
  def retryable_status?(429), do: true
  def retryable_status?(status) when status >= 500 and status < 600, do: true
  def retryable_status?(_), do: false
end
