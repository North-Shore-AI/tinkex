# Elixir Implementation Current State

**Date:** 2025-11-26
**Status:** Analysis Complete
**Elixir SDK Path:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib`

---

## Table of Contents

1. [Overview](#overview)
2. [Current Architecture](#current-architecture)
3. [Tinkex.SamplingClient](#tinkexsamplingclient)
4. [Tinkex.API.Sampling](#tinkexapisampling)
5. [Tinkex.RateLimiter](#tinkexratelimiter)
6. [Tinkex.Retry & Tinkex.RetryHandler (Unused)](#tinkexretry--tinkexretryhandler-unused)
7. [Tinkex.Config](#tinkexconfig)
8. [Request Flow](#request-flow)
9. [Gap Analysis](#gap-analysis)

---

## Overview

The Elixir Tinkex SDK has **partial retry infrastructure** but **lacks user-configurable retry for SamplingClient**:

✅ **Exists:** Basic retry modules (`Tinkex.Retry`, `Tinkex.RetryHandler`)
✅ **Exists:** Rate limiting via `Tinkex.RateLimiter`
✅ **Exists:** Config struct with `max_retries` field
❌ **Missing:** Integration of retry system with `SamplingClient`
❌ **Missing:** Configurable retry behavior via `RetryConfig`
❌ **Missing:** Connection limiting (semaphore)
❌ **Missing:** Progress timeout watchdog
❌ **Missing:** Exponential backoff configuration

**Current behavior:** `Tinkex.API.Sampling` hardcodes `max_retries: 0` (line 34 in `lib/tinkex/api/sampling.ex`)

---

## Current Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   Tinkex.SamplingClient                        │
│  - GenServer for session management                           │
│  - ETS-based lock-free read pattern                           │
│  - No retry configuration parameter                           │
└───────────────────────┬────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────────────┐
│                 Tinkex.SamplingRegistry                        │
│  - ETS table: :tinkex_sampling_clients                        │
│  - Stores: config, rate_limiter, session_id, etc.             │
└───────────────────────┬────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────────────┐
│                    do_sample/4 (private)                       │
│  1. ETS lookup for client config                              │
│  2. RateLimiter.wait_for_backoff()                            │
│  3. Build SampleRequest                                       │
│  4. Call API.Sampling.sample_async()                          │
│  5. Handle 429 → set_backoff                                  │
└───────────────────────┬────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────────────┐
│              Tinkex.API.Sampling.sample_async/2                │
│  - Hardcoded max_retries: 0                                   │
│  - Sets pool_type: :sampling                                  │
│  - Calls Tinkex.API.post()                                    │
└───────────────────────┬────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────────────┐
│                     Tinkex.API.post/3                          │
│  - HTTP request via Finch                                     │
│  - Respects max_retries from opts (currently 0)               │
│  - Telemetry events                                           │
└────────────────────────────────────────────────────────────────┘
```

### Key Components

| Module | Purpose | Status |
|--------|---------|--------|
| `Tinkex.SamplingClient` | Public API for sampling | ✅ Functional |
| `Tinkex.API.Sampling` | HTTP endpoint wrapper | ⚠️ Hardcodes `max_retries: 0` |
| `Tinkex.RateLimiter` | 429 backoff handling | ✅ Functional |
| `Tinkex.Retry` | Generic retry wrapper | ⚠️ Exists but unused by SamplingClient |
| `Tinkex.RetryHandler` | Retry state machine | ⚠️ Exists but unused by SamplingClient |
| `Tinkex.Config` | Client configuration | ⚠️ Has `max_retries` but not used for sampling |

---

## Tinkex.SamplingClient

**File:** `lib/tinkex/sampling_client.ex`
**Lines:** 1-312

### Module Documentation

```elixir
@moduledoc """
Sampling client that performs lock-free reads via ETS.

Init runs in a GenServer to create the sampling session and register state in
`Tinkex.SamplingRegistry`. Once initialized, `sample/4` reads configuration
directly from ETS without touching the GenServer, avoiding bottlenecks under
high load.

For plain-text prompts, build a `Tinkex.Types.ModelInput` via
`Tinkex.Types.ModelInput.from_text/2` with the target model name. Chat
templates are not applied automatically.
"""
```

### Initialization (lines 92-157)

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

  telemetry_metadata =
    opts
    |> Keyword.get(:telemetry_metadata, %{})
    |> Map.new()
    |> Map.put_new(:session_id, session_id)

  case create_sampling_session(...) do
    {:ok, sampling_session_id} ->
      limiter = RateLimiter.for_key({config.base_url, config.api_key})
      request_counter = :atomics.new(1, signed: false)

      # ...

      entry = %{
        sampling_session_id: sampling_session_id,
        http_pool: config.http_pool,
        request_id_counter: request_counter,
        rate_limiter: limiter,
        config: config,  # <-- Config passed but no retry config
        sampling_api: sampling_api,
        telemetry_metadata: telemetry_metadata,
        session_id: session_id
      }

      :ok = SamplingRegistry.register(self(), entry)
      # ...
```

**Key observations:**
1. **No retry_config parameter** in opts
2. **Config passed as-is** to ETS entry
3. **RateLimiter created** per `{base_url, api_key}` combination
4. **Atomics counter** for request IDs (similar to Python)

### Sample Method (lines 61-64)

```elixir
@spec sample(t(), map(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
def sample(client, prompt, sampling_params, opts \\ []) do
  {:ok, Task.async(fn -> do_sample(client, prompt, sampling_params, opts) end)}
end
```

**Signature:**
- `client`: SamplingClient PID
- `prompt`: `Tinkex.Types.ModelInput`
- `sampling_params`: `Tinkex.Types.SamplingParams`
- `opts`: Keyword list (no retry config options documented)

**Returns:** `{:ok, Task.t()}` (not Future, just Task)

### Core Logic: `do_sample/4` (lines 180-223)

```elixir
defp do_sample(client, prompt, sampling_params, opts) do
  case :ets.lookup(:tinkex_sampling_clients, {:config, client}) do
    [{{:config, ^client}, entry}] ->
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

    [] ->
      {:error, Error.new(:validation, "SamplingClient not initialized")}
  end
end
```

**Key points:**
1. **ETS lookup** for lock-free config access (line 181)
2. **RateLimiter.wait_for_backoff** before request (line 183)
3. **No retry wrapper** around `sample_async` call
4. **429 handling** sets backoff manually (lines 212-214)
5. **Other errors** propagate immediately (lines 216-217)

### Rate Limiting (lines 263-268)

```elixir
defp maybe_set_backoff(limiter, %Error{retry_after_ms: retry_after_ms})
     when is_integer(retry_after_ms) do
  RateLimiter.set_backoff(limiter, retry_after_ms)
end

defp maybe_set_backoff(_limiter, _error), do: :ok
```

**Behavior:**
- Extracts `retry_after_ms` from Error struct
- Sets backoff window in RateLimiter atomics
- Next request will wait via `RateLimiter.wait_for_backoff`

---

## Tinkex.API.Sampling

**File:** `lib/tinkex/api/sampling.ex`
**Lines:** 1-40

### Full Source

```elixir
defmodule Tinkex.API.Sampling do
  @moduledoc """
  Sampling API endpoints.

  Uses :sampling pool (high concurrency).
  Pool size: 100 connections.
  """

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
  rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry
  so that the higher-level client can make intelligent retry decisions based
  on rate limit state.

  Note: Named `sample_async` for consistency with Elixir naming conventions
  (adjective_noun or verb_object patterns). The API endpoint remains /api/v1/asample.

  ## Examples

      Tinkex.API.Sampling.sample_async(
        %{session_id: "...", prompts: [...]},
        config: config
      )
  """
  @spec sample_async(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def sample_async(request, opts) do
    opts =
      opts
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put(:max_retries, 0)
      |> Keyword.put_new(:sampling_backpressure, true)

    Tinkex.API.post("/api/v1/asample", request, opts)
  end
end
```

### Critical Line

**Line 34:** `|> Keyword.put(:max_retries, 0)`

**Comment (lines 13-16):**
> Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
> rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry
> so that the higher-level client can make intelligent retry decisions based
> on rate limit state.

**Analysis:**
- **Intentional decision:** HTTP layer retry disabled
- **Reason:** Allow higher-level intelligent retry (e.g., respect rate limit backoff)
- **Status:** "Phase 4" retry logic **not yet implemented**
- **Gap:** SamplingClient doesn't wrap calls with retry handler

---

## Tinkex.RateLimiter

**File:** `lib/tinkex/rate_limiter.ex`
**Lines:** 1-78

### Full Source

```elixir
defmodule Tinkex.RateLimiter do
  @moduledoc """
  Shared backoff state per `{base_url, api_key}` combination.
  """

  alias Tinkex.PoolKey

  @type limiter :: :atomics.atomics_ref()

  @doc """
  Get or create the limiter for a `{base_url, api_key}` tuple.
  """
  @spec for_key({String.t(), String.t() | nil}) :: limiter()
  def for_key({base_url, api_key}) do
    normalized_base = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized_base, api_key}}

    limiter = :atomics.new(1, signed: true)

    case :ets.insert_new(:tinkex_rate_limiters, {key, limiter}) do
      true ->
        limiter

      false ->
        case :ets.lookup(:tinkex_rate_limiters, key) do
          [{^key, existing}] ->
            existing

          [] ->
            :ets.insert(:tinkex_rate_limiters, {key, limiter})
            limiter
        end
    end
  end

  @doc """
  Determine whether the limiter is currently in a backoff window.
  """
  @spec should_backoff?(limiter()) :: boolean()
  def should_backoff?(limiter) do
    backoff_until = :atomics.get(limiter, 1)

    backoff_until != 0 and System.monotonic_time(:millisecond) < backoff_until
  end

  @doc """
  Set a backoff window in milliseconds.
  """
  @spec set_backoff(limiter(), non_neg_integer()) :: :ok
  def set_backoff(limiter, duration_ms) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    :atomics.put(limiter, 1, backoff_until)
    :ok
  end

  @doc """
  Clear any active backoff window.
  """
  @spec clear_backoff(limiter()) :: :ok
  def clear_backoff(limiter) do
    :atomics.put(limiter, 1, 0)
    :ok
  end

  @doc """
  Block until the backoff window has passed.
  """
  @spec wait_for_backoff(limiter()) :: :ok
  def wait_for_backoff(limiter) do
    if should_backoff?(limiter) do
      Process.sleep(100)
      wait_for_backoff(limiter)
    else
      :ok
    end
  end
end
```

### Design

**Purpose:** Share rate limit state across all SamplingClients using same `{base_url, api_key}`

**Storage:**
- **ETS table:** `:tinkex_rate_limiters`
- **Key:** `{:limiter, {normalized_base_url, api_key}}`
- **Value:** `:atomics.atomics_ref()` with single integer (backoff_until timestamp)

**Operations:**

| Function | Purpose |
|----------|---------|
| `for_key/1` | Get or create limiter (race-safe via ETS) |
| `should_backoff?/1` | Check if in backoff window |
| `set_backoff/2` | Set backoff expiration (current_time + duration_ms) |
| `clear_backoff/1` | Clear backoff (set to 0) |
| `wait_for_backoff/1` | **Blocking wait** (sleeps 100ms repeatedly) |

**Comparison to Python:**

| Aspect | Elixir RateLimiter | Python (InternalClientHolder) |
|--------|-------------------|-------------------------------|
| Scope | Per `{base_url, api_key}` | Per InternalClientHolder instance |
| Storage | ETS + atomics | Instance variable `_sample_backoff_until` |
| Waiting | Recursive blocking `Process.sleep(100)` | `await asyncio.sleep(1)` in loop |
| Trigger | 429 error with `retry_after_ms` | 429 error, sets 1 second backoff |

**Issue with `wait_for_backoff`:**
- **Blocking recursion** not ideal for concurrent system
- Should use `Process.sleep` once after calculating remaining time
- Python version is more efficient (sleeps exact duration)

---

## Tinkex.Retry & Tinkex.RetryHandler (Unused)

### Tinkex.RetryHandler

**File:** `lib/tinkex/retry_handler.ex`
**Lines:** 1-96

```elixir
defmodule Tinkex.RetryHandler do
  @moduledoc false

  alias Tinkex.Error

  @default_max_retries 3
  @default_base_delay_ms 500
  @default_max_delay_ms 8_000
  @default_jitter_pct 1.0
  @default_progress_timeout_ms 30_000

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
      jitter = capped * handler.jitter_pct * :rand.uniform()
      round(jitter)
    else
      round(capped)
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
```

### Comparison to Python RetryConfig

| Feature | Elixir RetryHandler | Python RetryConfig |
|---------|--------------------|--------------------|
| `max_retries` | ✅ 3 (default) | ❌ No limit (uses progress timeout) |
| `base_delay_ms` | ✅ 500ms | ✅ 500ms (`retry_delay_base`) |
| `max_delay_ms` | ✅ 8000ms | ✅ 10000ms (`retry_delay_max`) |
| `jitter_pct` | ⚠️ 1.0 (100% jitter) | ✅ 0.25 (25% jitter) |
| `progress_timeout_ms` | ✅ 30000ms | ✅ 1800000ms (30 min) |
| `max_connections` | ❌ Missing | ✅ 100 (semaphore) |
| `enable_retry_logic` | ❌ Missing | ✅ Boolean flag |
| `retryable_exceptions` | ❌ Missing | ✅ Configurable tuple |

**Issues:**

1. **Jitter percentage:** 1.0 (100%) is too high
   - Python uses 0.25 (±25%)
   - 100% jitter means delay is completely random from 0 to base_delay
   - Should be 0.25 to match Python

2. **Progress timeout:** 30 seconds is too short
   - Python uses 30 **minutes**
   - Current default would kill long-running sampling requests

3. **No connection limiting:** Missing semaphore equivalent

### Tinkex.Retry

**File:** `lib/tinkex/retry.ex`
**Lines:** 1-125

```elixir
defmodule Tinkex.Retry do
  @moduledoc false

  alias Tinkex.Error
  alias Tinkex.RetryHandler

  @telemetry_start [:tinkex, :retry, :attempt, :start]
  @telemetry_stop [:tinkex, :retry, :attempt, :stop]
  @telemetry_retry [:tinkex, :retry, :attempt, :retry]
  @telemetry_failed [:tinkex, :retry, :attempt, :failed]

  @spec with_retry((-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    handler = Keyword.get(opts, :handler, RetryHandler.new())
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    do_retry(fun, handler, metadata)
  end

  defp do_retry(fun, handler, metadata) do
    if RetryHandler.progress_timeout?(handler) do
      {:error, Error.new(:api_timeout, "Progress timeout exceeded")}
    else
      execute_attempt(fun, handler, metadata)
    end
  end

  defp execute_attempt(fun, handler, metadata) do
    attempt_metadata = Map.put(metadata, :attempt, handler.attempt)

    :telemetry.execute(
      @telemetry_start,
      %{system_time: System.system_time()},
      attempt_metadata
    )

    start_time = System.monotonic_time()

    result =
      try do
        fun.()
      rescue
        exception ->
          {:exception, exception, __STACKTRACE__}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, value} ->
        :telemetry.execute(
          @telemetry_stop,
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, value}

      {:error, error} ->
        handle_error(fun, error, handler, metadata, attempt_metadata, duration)

      {:exception, exception, _stacktrace} ->
        handle_exception(fun, exception, handler, metadata, attempt_metadata, duration)
    end
  end

  defp handle_error(fun, error, handler, metadata, attempt_metadata, duration) do
    if RetryHandler.retry?(handler, error) do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{error: error})
      )

      Process.sleep(delay)

      handler =
        handler
        |> RetryHandler.increment_attempt()
        |> RetryHandler.record_progress()

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :failed, error: error})
      )

      {:error, error}
    end
  end

  defp handle_exception(fun, exception, handler, metadata, attempt_metadata, duration) do
    if handler.attempt < handler.max_retries do
      delay = RetryHandler.next_delay(handler)

      :telemetry.execute(
        @telemetry_retry,
        %{duration: duration, delay_ms: delay},
        Map.merge(attempt_metadata, %{exception: exception})
      )

      Process.sleep(delay)

      handler =
        handler
        |> RetryHandler.increment_attempt()
        |> RetryHandler.record_progress()

      do_retry(fun, handler, metadata)
    else
      :telemetry.execute(
        @telemetry_failed,
        %{duration: duration},
        Map.merge(attempt_metadata, %{result: :exception, exception: exception})
      )

      {:error, Error.new(:request_failed, Exception.message(exception))}
    end
  end
end
```

**Key features:**
✅ Telemetry events for retry lifecycle
✅ Progress timeout check
✅ Exception handling (converts to Error)
✅ Exponential backoff via RetryHandler

**Usage pattern:**
```elixir
Retry.with_retry(fn ->
  # Do API call
  {:ok, result}
end, handler: RetryHandler.new(max_retries: 5))
```

**Why unused?**
- No integration point in `SamplingClient.do_sample/4`
- `API.Sampling.sample_async` hardcodes `max_retries: 0`
- Would need wrapper around `entry.sampling_api.sample_async(request, api_opts)`

---

## Tinkex.Config

**File:** `lib/tinkex/config.ex`
**Lines:** 1-157

### Struct Definition (lines 14-31)

```elixir
@enforce_keys [:base_url, :api_key]
defstruct [
  :base_url,
  :api_key,
  :http_pool,
  :timeout,
  :max_retries,
  :user_metadata
]

@type t :: %__MODULE__{
        base_url: String.t(),
        api_key: String.t(),
        http_pool: atom(),
        timeout: pos_integer(),
        max_retries: non_neg_integer(),
        user_metadata: map() | nil
      }
```

### Defaults (lines 33-35)

```elixir
@default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
@default_timeout 120_000  # 120 seconds
@default_max_retries 2
```

### Constructor (lines 44-73)

```elixir
@spec new(keyword()) :: t()
def new(opts \\ []) do
  api_key =
    opts[:api_key] ||
      Application.get_env(:tinkex, :api_key) ||
      System.get_env("TINKER_API_KEY")

  base_url =
    opts[:base_url] ||
      Application.get_env(:tinkex, :base_url, @default_base_url)

  http_pool = opts[:http_pool] || Application.get_env(:tinkex, :http_pool, Tinkex.HTTP.Pool)
  timeout = opts[:timeout] || Application.get_env(:tinkex, :timeout, @default_timeout)

  max_retries =
    opts[:max_retries] || Application.get_env(:tinkex, :max_retries, @default_max_retries)

  config = %__MODULE__{
    base_url: base_url,
    api_key: api_key,
    http_pool: http_pool,
    timeout: timeout,
    max_retries: max_retries,
    user_metadata: opts[:user_metadata]
  }

  # Fail fast on malformed URLs so pool creation does not explode deeper in the stack.
  _ = Tinkex.PoolKey.normalize_base_url(config.base_url)

  validate!(config)
end
```

### Issues

1. **`max_retries` exists but unused for sampling**
   - Comment in `API.Sampling` says retry logic is TODO
   - Config field goes unused for SamplingClient

2. **Missing retry configuration fields:**
   - No `retry_delay_base`
   - No `retry_delay_max`
   - No `jitter_factor`
   - No `progress_timeout`
   - No `max_connections`
   - No `enable_retry_logic`

3. **Config not hashable:** Can't cache retry handlers like Python does

---

## Request Flow

### Current Flow (Without Retry)

```
1. User calls SamplingClient.sample(client, prompt, params)
   └─> Returns {:ok, Task.t()}

2. Task executes do_sample(client, prompt, params, opts)
   ├─> ETS lookup for client config
   ├─> RateLimiter.wait_for_backoff(limiter) [BLOCKING if in backoff]
   ├─> Build SampleRequest
   └─> API.Sampling.sample_async(request, api_opts)
       └─> Keyword.put(:max_retries, 0) [HARDCODED]
       └─> Tinkex.API.post("/api/v1/asample", request, opts)
           └─> Finch HTTP request
               ├─> Success → {:ok, response}
               ├─> 429 → {:error, %Error{status: 429}}
               │         └─> maybe_set_backoff() [Sets RateLimiter backoff]
               │         └─> Propagates error to caller
               └─> Other error → {:error, %Error{}}
                   └─> Propagates error to caller

3. Task result:
   ├─> Success → {:ok, %SampleResponse{}}
   └─> Error → {:error, %Error{}}
```

### What's Missing

```diff
2. Task executes do_sample(client, prompt, params, opts)
   ├─> ETS lookup for client config
+  ├─> Retry.with_retry(fn ->
   ├─> RateLimiter.wait_for_backoff(limiter)
   ├─> Build SampleRequest
   └─> API.Sampling.sample_async(request, api_opts)
-      └─> Keyword.put(:max_retries, 0)
+      └─> Use config.max_retries (or retry_config.max_retries)
       └─> Tinkex.API.post(...)
+  end, handler: get_retry_handler(config))
```

---

## Gap Analysis

### What Exists

| Feature | Module | Status |
|---------|--------|--------|
| Rate limiting (429 backoff) | `RateLimiter` | ✅ Working |
| Retry state machine | `RetryHandler` | ✅ Exists, unused |
| Retry wrapper | `Retry` | ✅ Exists, unused |
| Exponential backoff | `RetryHandler.next_delay/1` | ✅ Implemented |
| Progress timeout check | `RetryHandler.progress_timeout?/1` | ✅ Implemented |
| Telemetry events | `Retry` | ✅ Implemented |
| Config with max_retries | `Config` | ✅ Exists |

### What's Missing

| Feature | Status | Notes |
|---------|--------|-------|
| **Integration with SamplingClient** | ❌ **Critical gap** | No retry wrapper around API calls |
| **Retry configuration struct** | ❌ Missing | Need equivalent of Python's `RetryConfig` |
| **Connection limiting (semaphore)** | ❌ Missing | No concurrency control |
| **Progress timeout watchdog** | ❌ Missing | Check exists but no monitoring Task |
| **Configurable retryable exceptions** | ❌ Missing | Hardcoded in `Error.retryable?/1` |
| **Enable/disable flag** | ❌ Missing | No `enable_retry_logic` equivalent |
| **Handler caching** | ❌ Missing | No LRU cache like Python's `@lru_cache` |
| **User-facing retry_config parameter** | ❌ Missing | SamplingClient doesn't accept retry config |

### Configuration Defaults Comparison

| Setting | Python Default | Elixir Default | Notes |
|---------|---------------|----------------|-------|
| **max_retries** | Unlimited (progress timeout) | 3 | ⚠️ Elixir too conservative |
| **base_delay** | 0.5s | 0.5s | ✅ Match |
| **max_delay** | 10s | 8s | ⚠️ Close but different |
| **jitter** | 25% | **100%** | ❌ **Elixir way too high** |
| **progress_timeout** | 30 min | **30 sec** | ❌ **Elixir way too short** |
| **max_connections** | 100 | N/A | ❌ Missing |

### Code Locations for Implementation

**Files to modify:**

1. **`lib/tinkex/sampling_client.ex`**
   - Line 61-64: Update `sample/4` signature to accept `:retry_config`
   - Line 180-223: Wrap `do_sample/4` with retry logic
   - Add handler caching helper (similar to Python's `_get_retry_handler`)

2. **`lib/tinkex/api/sampling.ex`**
   - Line 34: Remove hardcoded `max_retries: 0`
   - Use `Keyword.get(opts, :max_retries, 0)` instead

3. **`lib/tinkex/retry_handler.ex`**
   - Line 9: Change `@default_jitter_pct` from `1.0` to `0.25`
   - Line 10: Change `@default_progress_timeout_ms` from `30_000` to `1_800_000`
   - Add `max_connections` field
   - Add `enable_retry_logic` field
   - Add `retryable_exceptions` field (or keep in `Error.retryable?/1`)

4. **`lib/tinkex/config.ex`**
   - Add retry-specific fields to struct
   - Add `retry_config` sub-struct option
   - Or: Create new `Tinkex.RetryConfig` module

5. **New file: `lib/tinkex/retry_config.ex`** (recommended)
   - Define retry configuration struct
   - Implement defaults
   - Validation logic

6. **`lib/tinkex/rate_limiter.ex`**
   - Line 68-75: Fix `wait_for_backoff/1` to calculate exact sleep duration
   - Avoid recursive Process.sleep(100) pattern

---

## Summary

### Current State

✅ **Partial infrastructure exists:**
- `Retry` and `RetryHandler` modules implemented
- `RateLimiter` handles 429 backoff
- `Config` has `max_retries` field
- Telemetry events ready

❌ **Critical gaps:**
- **No integration** between retry system and SamplingClient
- **Hardcoded `max_retries: 0`** at API layer
- **No user-facing retry configuration**
- **Missing connection limiting** (no semaphore)
- **Missing progress watchdog** (timeout check exists but no monitoring)
- **Wrong defaults** (100% jitter, 30sec timeout)

### Why Gap Exists

**Intentional design:** Comment in `api/sampling.ex` (lines 13-16) indicates:
> Phase 4's SamplingClient will implement client-side rate limiting and retry logic via RateLimiter

**Phase 4 never completed:**
- Retry modules created but never wired up
- SamplingClient still uses hardcoded `max_retries: 0`
- No retry_config parameter added to public API

### Next Steps

See **04_implementation_spec.md** for detailed implementation plan to close these gaps.
