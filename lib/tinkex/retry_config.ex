defmodule Tinkex.RetryConfig do
  @moduledoc """
  User-facing retry configuration for sampling operations.

  Mirrors the Python SDK surface (time-bounded retries with progress timeout,
  backoff tuning, connection limiting, enable/disable toggle). The struct is
  designed to be lightweight and easy to pass through opts.
  """

  @enforce_keys []
  defstruct [
    :max_retries,
    :base_delay_ms,
    :max_delay_ms,
    :jitter_pct,
    :progress_timeout_ms,
    :max_connections,
    :enable_retry_logic
  ]

  @type t :: %__MODULE__{
          max_retries: non_neg_integer() | :infinity,
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          jitter_pct: float(),
          progress_timeout_ms: pos_integer(),
          max_connections: pos_integer(),
          enable_retry_logic: boolean()
        }

  @default_max_retries :infinity
  @default_base_delay_ms 500
  @default_max_delay_ms 10_000
  @default_jitter_pct 0.25
  @default_progress_timeout_ms 7_200_000
  @default_max_connections 1000
  @default_enable_retry_logic true

  @doc """
  Build a retry configuration.

  Accepts keyword options overriding defaults that match the Python RetryConfig
  defaults (0.5s base delay, 10s cap, 25% jitter, 120m progress timeout, and
  no retry cap unless explicitly provided).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      jitter_pct: Keyword.get(opts, :jitter_pct, @default_jitter_pct),
      progress_timeout_ms: Keyword.get(opts, :progress_timeout_ms, @default_progress_timeout_ms),
      max_connections: Keyword.get(opts, :max_connections, @default_max_connections),
      enable_retry_logic: Keyword.get(opts, :enable_retry_logic, @default_enable_retry_logic)
    }
    |> validate!()
  end

  @doc """
  Return the default retry configuration.
  """
  @spec default() :: t()
  def default, do: new()

  @doc """
  Validate a retry configuration, raising on invalid values.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    unless (is_integer(config.max_retries) and config.max_retries >= 0) or
             config.max_retries == :infinity do
      raise ArgumentError,
            "max_retries must be a non-negative integer or :infinity, got: #{inspect(config.max_retries)}"
    end

    unless is_integer(config.base_delay_ms) and config.base_delay_ms > 0 do
      raise ArgumentError,
            "base_delay_ms must be a positive integer, got: #{inspect(config.base_delay_ms)}"
    end

    unless is_integer(config.max_delay_ms) and config.max_delay_ms >= config.base_delay_ms do
      raise ArgumentError,
            "max_delay_ms must be >= base_delay_ms, got: #{inspect(config.max_delay_ms)}"
    end

    unless is_float(config.jitter_pct) and config.jitter_pct >= 0.0 and config.jitter_pct <= 1.0 do
      raise ArgumentError,
            "jitter_pct must be a float between 0.0 and 1.0, got: #{inspect(config.jitter_pct)}"
    end

    unless is_integer(config.progress_timeout_ms) and config.progress_timeout_ms > 0 do
      raise ArgumentError,
            "progress_timeout_ms must be a positive integer, got: #{inspect(config.progress_timeout_ms)}"
    end

    unless is_integer(config.max_connections) and config.max_connections > 0 do
      raise ArgumentError,
            "max_connections must be a positive integer, got: #{inspect(config.max_connections)}"
    end

    unless is_boolean(config.enable_retry_logic) do
      raise ArgumentError,
            "enable_retry_logic must be a boolean, got: #{inspect(config.enable_retry_logic)}"
    end

    config
  end

  @doc """
  Convert to RetryHandler options.
  """
  @spec to_handler_opts(t()) :: keyword()
  def to_handler_opts(%__MODULE__{} = config) do
    [
      max_retries: config.max_retries,
      base_delay_ms: config.base_delay_ms,
      max_delay_ms: config.max_delay_ms,
      jitter_pct: config.jitter_pct,
      progress_timeout_ms: config.progress_timeout_ms
    ]
  end
end
