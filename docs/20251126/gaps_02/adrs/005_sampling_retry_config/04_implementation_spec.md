# Implementation Specification: Retry Config for Elixir

**Date:** 2025-11-26
**Status:** Ready for Implementation
**Priority:** HIGH

---

## Executive Summary

This document provides **exact specifications** for implementing retry configuration in the Elixir Tinkex SDK to match Python functionality.

**Implementation approach:** Phased rollout with backward compatibility

---

## Phase 1: Fix Existing Modules (1-2 days)

### 1.1 Fix RetryHandler Defaults

**File:** `lib/tinkex/retry_handler.ex`

**Changes:**

```elixir
# Line 9: Change jitter from 100% to 25%
- @default_jitter_pct 1.0
+ @default_jitter_pct 0.25

# Line 10: Change progress timeout from 30 seconds to 30 minutes
- @default_progress_timeout_ms 30_000
+ @default_progress_timeout_ms 1_800_000

# Line 8: Change max delay from 8s to 10s (match Python)
- @default_max_delay_ms 8_000
+ @default_max_delay_ms 10_000
```

### 1.2 Fix Jitter Calculation

**File:** `lib/tinkex/retry_handler.ex`
**Function:** `next_delay/1` (lines 61-72)

**Current (WRONG):**
```elixir
def next_delay(%__MODULE__{} = handler) do
  base = handler.base_delay_ms * :math.pow(2, handler.attempt)
  capped = min(base, handler.max_delay_ms)

  if handler.jitter_pct > 0 do
    jitter = capped * handler.jitter_pct * :rand.uniform()  # WRONG: 0% to 100%
    round(jitter)
  else
    round(capped)
  end
end
```

**New (CORRECT):**
```elixir
@spec next_delay(t()) :: non_neg_integer()
def next_delay(%__MODULE__{} = handler) do
  base = handler.base_delay_ms * :math.pow(2, handler.attempt)
  capped = min(base, handler.max_delay_ms)

  if handler.jitter_pct > 0 do
    # Jitter range: ±jitter_pct (e.g., ±25%)
    jitter = capped * handler.jitter_pct * (2 * :rand.uniform() - 1)
    final_delay = capped + jitter
    # Ensure non-negative and capped
    final_delay
    |> max(0)
    |> min(handler.max_delay_ms)
    |> round()
  else
    round(capped)
  end
end
```

### 1.3 Fix RateLimiter Wait

**File:** `lib/tinkex/rate_limiter.ex`
**Function:** `wait_for_backoff/1` (lines 68-75)

**Current (INEFFICIENT):**
```elixir
def wait_for_backoff(limiter) do
  if should_backoff?(limiter) do
    Process.sleep(100)
    wait_for_backoff(limiter)  # Recursive, inefficient
  else
    :ok
  end
end
```

**New (EFFICIENT):**
```elixir
@doc """
Block until the backoff window has passed.

Calculates exact wait time and sleeps once instead of polling.
"""
@spec wait_for_backoff(limiter()) :: :ok
def wait_for_backoff(limiter) do
  backoff_until = :atomics.get(limiter, 1)

  if backoff_until > 0 do
    now = System.monotonic_time(:millisecond)

    if backoff_until > now do
      wait_ms = backoff_until - now
      Process.sleep(wait_ms)
    end
  end

  :ok
end
```

---

## Phase 2: Create RetryConfig Module (2-3 days)

### 2.1 New File: `lib/tinkex/retry_config.ex`

**Complete implementation:**

```elixir
defmodule Tinkex.RetryConfig do
  @moduledoc """
  Retry configuration for SamplingClient.

  Controls retry behavior, connection limiting, and progress timeout.

  ## Example

      retry_config = RetryConfig.new(
        max_retries: 5,
        base_delay_ms: 500,
        max_delay_ms: 10_000,
        jitter_pct: 0.25,
        progress_timeout_ms: 1_800_000,
        max_connections: 100,
        enable_retry_logic: true
      )

      SamplingClient.start_link(
        config: config,
        session_id: session_id,
        base_model: "meta-llama/Llama-3.2-1B",
        retry_config: retry_config
      )
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
          max_retries: non_neg_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          jitter_pct: float(),
          progress_timeout_ms: pos_integer(),
          max_connections: pos_integer(),
          enable_retry_logic: boolean()
        }

  @default_max_retries 10
  @default_base_delay_ms 500
  @default_max_delay_ms 10_000
  @default_jitter_pct 0.25
  @default_progress_timeout_ms 1_800_000  # 30 minutes
  @default_max_connections 100
  @default_enable_retry_logic true

  @doc """
  Create a new retry configuration.

  ## Options

    * `:max_retries` - Maximum retry attempts (default: 10)
    * `:base_delay_ms` - Base delay in milliseconds (default: 500)
    * `:max_delay_ms` - Maximum delay in milliseconds (default: 10,000)
    * `:jitter_pct` - Jitter percentage as decimal (default: 0.25 = ±25%)
    * `:progress_timeout_ms` - Progress timeout in milliseconds (default: 1,800,000 = 30 minutes)
    * `:max_connections` - Maximum concurrent connections (default: 100)
    * `:enable_retry_logic` - Enable retry logic (default: true)

  ## Examples

      iex> RetryConfig.new()
      %RetryConfig{max_retries: 10, ...}

      iex> RetryConfig.new(max_retries: 5, max_connections: 50)
      %RetryConfig{max_retries: 5, max_connections: 50, ...}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    config = %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      jitter_pct: Keyword.get(opts, :jitter_pct, @default_jitter_pct),
      progress_timeout_ms:
        Keyword.get(opts, :progress_timeout_ms, @default_progress_timeout_ms),
      max_connections: Keyword.get(opts, :max_connections, @default_max_connections),
      enable_retry_logic: Keyword.get(opts, :enable_retry_logic, @default_enable_retry_logic)
    }

    validate!(config)
  end

  @doc """
  Validate a retry configuration.

  Raises ArgumentError if invalid.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    unless is_integer(config.max_retries) and config.max_retries >= 0 do
      raise ArgumentError,
            "max_retries must be a non-negative integer, got: #{inspect(config.max_retries)}"
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
  Get default retry configuration.
  """
  @spec default() :: t()
  def default, do: new()

  @doc """
  Convert to RetryHandler options.

  Used internally when creating RetryHandler instances.
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
```

### 2.2 Update RetryHandler to Use RetryConfig

**File:** `lib/tinkex/retry_handler.ex`

**Add to module:**

```elixir
@doc """
Create RetryHandler from RetryConfig.

## Examples

    iex> retry_config = RetryConfig.new(max_retries: 5)
    iex> RetryHandler.from_config(retry_config)
    %RetryHandler{max_retries: 5, ...}
"""
@spec from_config(Tinkex.RetryConfig.t()) :: t()
def from_config(%Tinkex.RetryConfig{} = config) do
  new(Tinkex.RetryConfig.to_handler_opts(config))
end
```

---

## Phase 3: Integrate with SamplingClient (3-4 days)

### 3.1 Update SamplingClient Initialization

**File:** `lib/tinkex/sampling_client.ex`

**Changes to `init/1`:**

```elixir
@impl true
def init(opts) do
  config = Keyword.fetch!(opts, :config)
  session_id = Keyword.fetch!(opts, :session_id)
  sampling_client_id = Keyword.fetch!(opts, :sampling_client_id)
  base_model = Keyword.get(opts, :base_model)
  model_path = Keyword.get(opts, :model_path)
  service_api = Keyword.get(opts, :service_api, Service)
  sampling_api = Keyword.get(opts, :sampling_api, Sampling)

  # NEW: Get retry config
  retry_config =
    case Keyword.get(opts, :retry_config) do
      nil -> Tinkex.RetryConfig.default()
      %Tinkex.RetryConfig{} = rc -> rc
      config_opts when is_list(config_opts) -> Tinkex.RetryConfig.new(config_opts)
    end

  # ... rest of init

  entry = %{
    sampling_session_id: sampling_session_id,
    http_pool: config.http_pool,
    request_id_counter: request_counter,
    rate_limiter: limiter,
    config: config,
    retry_config: retry_config,  # NEW: Store retry config
    sampling_api: sampling_api,
    telemetry_metadata: telemetry_metadata,
    session_id: session_id
  }

  :ok = SamplingRegistry.register(self(), entry)
  # ...
```

### 3.2 Add Retry Wrapper to do_sample

**File:** `lib/tinkex/sampling_client.ex`

**Replace `do_sample/4` function:**

```elixir
defp do_sample(client, prompt, sampling_params, opts) do
  case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
    [{{:config, ^client}, entry}] ->
      # Fast path: skip retry if disabled
      if entry.retry_config.enable_retry_logic do
        do_sample_with_retry(entry, prompt, sampling_params, opts)
      else
        do_sample_once(entry, prompt, sampling_params, opts)
      end

    [] ->
      {:error, Error.new(:validation, "SamplingClient not initialized")}
  end
end

defp do_sample_with_retry(entry, prompt, sampling_params, opts) do
  handler = RetryHandler.from_config(entry.retry_config)

  Retry.with_retry(
    fn ->
      do_sample_once(entry, prompt, sampling_params, opts)
    end,
    handler: handler,
    telemetry_metadata: Map.new(entry.telemetry_metadata)
  )
end

defp do_sample_once(entry, prompt, sampling_params, opts) do
  RateLimiter.wait_for_backoff(entry.rate_limiter)
  seq_id = next_seq_id(entry.request_id_counter)

  request =
    %SampleRequest{
      sampling_session_id: entry.sampling_session_id,
      seq_id: seq_id,
      prompt: prompt,
      sampling_params: sampling_params,
      num_samples: Keyword.get(opts, :num_samples, 1),
      prompt_logprobs: Keyword.get(opts, :prompt_logprobs),
      topk_prompt_logprobs: Keyword.get(opts, :topk_prompt_logprobs, 0)
    }

  api_opts =
    opts
    |> Keyword.put(:config, entry.config)
    |> Keyword.put(:tinker_request_type, "Sample")
    |> Keyword.put(:tinker_request_iteration, seq_id)
    |> Keyword.put(
      :telemetry_metadata,
      merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata])
    )

  case entry.sampling_api.sample_async(request, api_opts) do
    {:ok, resp} ->
      RateLimiter.clear_backoff(entry.rate_limiter)
      handle_sample_response(resp, entry, seq_id, opts)

    {:error, %Error{status: 429} = error} ->
      maybe_set_backoff(entry.rate_limiter, error)
      {:error, error}

    {:error, %Error{} = error} ->
      {:error, error}
  end
end
```

### 3.3 Update API.Sampling to Use Config Max Retries

**File:** `lib/tinkex/api/sampling.ex`

**Change line 34:**

```elixir
def sample_async(request, opts) do
  # Use max_retries from opts (passed from retry_config), default to 0 for backward compat
  max_retries = Keyword.get(opts, :max_retries, 0)

  opts =
    opts
    |> Keyword.put(:pool_type, :sampling)
    |> Keyword.put(:max_retries, max_retries)  # Use variable, not hardcoded 0
    |> Keyword.put_new(:sampling_backpressure, true)

  Tinkex.API.post("/api/v1/asample", request, opts)
end
```

---

## Phase 4: Add Connection Limiting (Optional, 2-3 days)

### 4.1 Add Semaphore Dependency

**File:** `mix.exs`

```elixir
defp deps do
  [
    # ... existing deps
    {:semaphore, "~> 1.3"}  # Add this
  ]
end
```

### 4.2 Create Semaphore Manager

**New file:** `lib/tinkex/retry_semaphore.ex`

```elixir
defmodule Tinkex.RetrySemaphore do
  @moduledoc """
  Manages semaphores for connection limiting per retry config.

  Each unique retry_config gets its own semaphore to limit
  concurrent requests.
  """

  use GenServer

  @doc """
  Start the semaphore manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get or create semaphore for max_connections limit.
  """
  @spec get_semaphore(pos_integer()) :: Semaphore.t()
  def get_semaphore(max_connections) do
    key = {:semaphore, max_connections}

    case :ets.lookup(:tinkex_retry_semaphores, key) do
      [{^key, semaphore}] ->
        semaphore

      [] ->
        GenServer.call(__MODULE__, {:create_semaphore, max_connections})
    end
  end

  @doc """
  Acquire semaphore, execute function, release semaphore.
  """
  @spec with_semaphore(pos_integer(), (() -> term())) :: term()
  def with_semaphore(max_connections, fun) do
    semaphore = get_semaphore(max_connections)
    Semaphore.call(semaphore, fun)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    :ets.new(:tinkex_retry_semaphores, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_semaphore, max_connections}, _from, state) do
    key = {:semaphore, max_connections}

    case :ets.lookup(:tinkex_retry_semaphores, key) do
      [{^key, existing}] ->
        {:reply, existing, state}

      [] ->
        {:ok, semaphore} = Semaphore.start_link(max_count: max_connections)
        :ets.insert(:tinkex_retry_semaphores, {key, semaphore})
        {:reply, semaphore, state}
    end
  end
end
```

### 4.3 Integrate Semaphore with Retry

**File:** `lib/tinkex/sampling_client.ex`

**Update `do_sample_with_retry/4`:**

```elixir
defp do_sample_with_retry(entry, prompt, sampling_params, opts) do
  handler = RetryHandler.from_config(entry.retry_config)

  # Wrap with semaphore if max_connections > 0
  if entry.retry_config.max_connections > 0 do
    Tinkex.RetrySemaphore.with_semaphore(
      entry.retry_config.max_connections,
      fn ->
        Retry.with_retry(
          fn -> do_sample_once(entry, prompt, sampling_params, opts) end,
          handler: handler,
          telemetry_metadata: Map.new(entry.telemetry_metadata)
        )
      end
    )
  else
    # No connection limiting
    Retry.with_retry(
      fn -> do_sample_once(entry, prompt, sampling_params, opts) end,
      handler: handler,
      telemetry_metadata: Map.new(entry.telemetry_metadata)
    )
  end
end
```

---

## Testing Requirements

See `05_test_plan.md` for comprehensive test plan.

**Minimum tests:**

1. **RetryConfig validation**
2. **Jitter calculation correctness**
3. **RateLimiter wait efficiency**
4. **SamplingClient retry integration**
5. **Backward compatibility** (no retry_config provided)

---

## Backward Compatibility

### Breaking Changes: NONE

All changes are **additive and opt-in**:

- Existing SamplingClient calls work unchanged (default retry config)
- New `retry_config` parameter is optional
- Default behavior: retry enabled with sensible defaults

### Migration Guide

**Before (still works):**
```elixir
{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "meta-llama/Llama-3.2-1B"
)
```

**After (with custom retry):**
```elixir
retry_config = Tinkex.RetryConfig.new(max_retries: 5)

{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "meta-llama/Llama-3.2-1B",
  retry_config: retry_config  # NEW
)
```

---

## Summary

### Files to Create

1. `lib/tinkex/retry_config.ex` (new)
2. `lib/tinkex/retry_semaphore.ex` (new, optional)

### Files to Modify

1. `lib/tinkex/retry_handler.ex` - Fix defaults, jitter, add from_config/1
2. `lib/tinkex/rate_limiter.ex` - Fix wait_for_backoff/1
3. `lib/tinkex/sampling_client.ex` - Add retry_config param, wrap do_sample
4. `lib/tinkex/api/sampling.ex` - Use opts max_retries instead of hardcoded 0
5. `mix.exs` - Add semaphore dependency (optional)

### Estimated Effort

- **Phase 1 (Fixes):** 1-2 days
- **Phase 2 (RetryConfig):** 2-3 days
- **Phase 3 (Integration):** 3-4 days
- **Phase 4 (Semaphore):** 2-3 days (optional)
- **Testing:** 2-3 days

**Total:** 10-15 days (8-12 days without semaphore)

### Priority Order

1. **Critical:** Phase 1 (fixes) + Phase 2 (RetryConfig)
2. **High:** Phase 3 (integration)
3. **Medium:** Phase 4 (semaphore)
4. **Ongoing:** Testing throughout

This completes the implementation specification.
