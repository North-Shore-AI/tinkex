defmodule Tinkex.RetryHandler do
  @moduledoc false

  alias Tinkex.Error

  @default_max_retries 3
  @default_base_delay_ms 500
  @default_max_delay_ms 10_000
  @default_jitter_pct 0.25
  @default_progress_timeout_ms 1_800_000

  defstruct [
    :max_retries,
    :base_delay_ms,
    :max_delay_ms,
    :jitter_pct,
    :progress_timeout_ms,
    :attempt,
    :last_progress_at,
    :start_time
  ]

  @type t :: %__MODULE__{
          max_retries: non_neg_integer(),
          base_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          jitter_pct: float(),
          progress_timeout_ms: non_neg_integer(),
          attempt: non_neg_integer(),
          last_progress_at: integer() | nil,
          start_time: integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = System.monotonic_time(:millisecond)

    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      jitter_pct: Keyword.get(opts, :jitter_pct, @default_jitter_pct),
      progress_timeout_ms: Keyword.get(opts, :progress_timeout_ms, @default_progress_timeout_ms),
      attempt: 0,
      last_progress_at: now,
      start_time: now
    }
  end

  @spec retry?(t(), Error.t() | term()) :: boolean()
  def retry?(%__MODULE__{attempt: attempt, max_retries: max}, _error) when attempt >= max do
    false
  end

  def retry?(%__MODULE__{}, %Error{} = error) do
    Error.retryable?(error)
  end

  def retry?(%__MODULE__{}, _error), do: true

  @spec next_delay(t()) :: non_neg_integer()
  def next_delay(%__MODULE__{} = handler) do
    base = handler.base_delay_ms * :math.pow(2, handler.attempt)
    capped = min(base, handler.max_delay_ms)

    if handler.jitter_pct > 0 do
      # Jitter in the range [-jitter_pct, +jitter_pct] of the capped delay
      jitter = capped * handler.jitter_pct * (2 * :rand.uniform() - 1)

      capped
      |> Kernel.+(jitter)
      |> max(0)
      |> min(handler.max_delay_ms)
      |> round()
    else
      round(capped)
    end
  end

  @doc """
  Build a RetryHandler from a RetryConfig-like struct that implements
  `to_handler_opts/1`.
  """
  @spec from_config(struct()) :: t()
  def from_config(config) when is_struct(config) do
    config
    |> maybe_to_handler_opts()
    |> new()
  end

  defp maybe_to_handler_opts(%mod{} = config) do
    if function_exported?(mod, :to_handler_opts, 1) do
      apply(mod, :to_handler_opts, [config])
    else
      raise ArgumentError,
            "retry config struct #{inspect(mod)} must implement to_handler_opts/1"
    end
  end

  @spec record_progress(t()) :: t()
  def record_progress(%__MODULE__{} = handler) do
    %{handler | last_progress_at: System.monotonic_time(:millisecond)}
  end

  @spec progress_timeout?(t()) :: boolean()
  def progress_timeout?(%__MODULE__{last_progress_at: nil}), do: false

  def progress_timeout?(%__MODULE__{} = handler) do
    elapsed = System.monotonic_time(:millisecond) - handler.last_progress_at
    elapsed > handler.progress_timeout_ms
  end

  @spec increment_attempt(t()) :: t()
  def increment_attempt(%__MODULE__{} = handler) do
    %{handler | attempt: handler.attempt + 1}
  end

  @spec elapsed_ms(t()) :: non_neg_integer()
  def elapsed_ms(%__MODULE__{} = handler) do
    System.monotonic_time(:millisecond) - handler.start_time
  end
end
