# Phase 2B: HTTP Client - Agent Prompt

> **Target:** Build the core HTTP client with retry logic, error handling, and telemetry.
> **Timebox:** Week 2 - Day 2
> **Location:** `S:\tinkex` (pure Elixir library)
> **Prerequisites:** Phase 2A must be complete (PoolKey, Config, Application)
> **Next:** Phase 2C (Endpoints and Testing)

---

## 1. Project Context

This document covers the core `Tinkex.API` module that handles all HTTP communication. This is the most critical part of Phase 2 - the retry logic must be correct.

### 1.1 Critical Requirements

1. **NO Application.get_env at call time** - Config must be threaded through function calls
2. **Config is required** - `Keyword.fetch!(opts, :config)` - no silent defaults
3. **x-should-retry header takes precedence** - `"false"` prevents retry even for 5xx, `"true"` triggers retry even for 4xx
4. **Case-insensitive header parsing** - HTTP headers are case-insensitive per RFC 7230
5. **Total timeout on retries** - Prevent unbounded waits

### 1.2 Retry Logic Requirements

Refer to **Phase 2A, Section 2.2 (Retry Semantics)** for the complete retry specification.

**Important**: The x-should-retry header takes precedence over status-based logic. If server says `x-should-retry: "false"` on a 503, we don't retry. If server says `x-should-retry: "true"` on a 400, we do retry.

### 1.3 max_retry_duration_ms Semantics

The `@max_retry_duration_ms` constant (default 30,000ms) bounds the **retry decision window**, not total wall-clock time.

- The check happens before each retry attempt
- If elapsed time exceeds this value, no more retries are attempted
- Total request time may exceed this by up to `receive_timeout` (for the final in-flight request)
- Example: At 29,900ms elapsed, a retry is allowed. If that request takes 120,000ms (receive_timeout), total time = ~150s

### 1.4 Backoff Schedule

Refer to **Phase 2A, Section 2.4 (Backoff Schedule)** for the approximate timing.

**Note on 429 Retry-After**: When a 429 response includes `Retry-After`, the SDK will `Process.sleep` for that duration. This blocks the calling process. See Section 1.5 for implications.

### 1.5 GenServer Usage Caveat

**Warning**: Calling `Tinkex.API` functions from a GenServer will block that GenServer during retries. If non-blocking behavior is needed, wrap calls in `Task.async/await`:

```elixir
def handle_call({:fetch_data, params}, _from, state) do
  task = Task.async(fn ->
    Tinkex.API.post("/data", params, config: state.config)
  end)

  # Either await with timeout or handle via handle_info
  result = Task.await(task, 60_000)
  {:reply, result, state}
end
```

---

## 2. Implementation Plan

### 2.1 Implementation Order

```
1. Tinkex.API              # Base HTTP module with retry logic
2. Tinkex.HTTPClient       # Behaviour for mockability (optional but recommended)
```

### 2.2 File Structure

```
lib/tinkex/
├── api/
│   └── api.ex            # Tinkex.API (base module)
└── http_client.ex        # Tinkex.HTTPClient behaviour (optional)
```

---

## 3. Detailed Module Specifications

### 3.1 Tinkex.HTTPClient Behaviour (Optional)

Define a behaviour for easier testing and potential future implementations.

```elixir
defmodule Tinkex.HTTPClient do
  @moduledoc """
  Behaviour for HTTP client implementations.

  Allows mocking the HTTP layer in tests without Bypass.
  The default implementation is `Tinkex.API`.
  """

  @callback post(path :: String.t(), body :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, Tinkex.Error.t()}

  @callback get(path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, Tinkex.Error.t()}
end
```

### 3.2 Tinkex.API (Base Module)

The core HTTP module with corrected retry logic. **Pay careful attention to the `with_retries` implementation - the original had a critical bug where clause ordering made 429/5xx branches unreachable.**

```elixir
defmodule Tinkex.API do
  @moduledoc """
  High-level HTTP API client for Tinkex.

  This module is the primary abstraction over Finch, handling:
  - Retry logic with exponential backoff and jitter
  - Server-provided backoff via Retry-After headers
  - x-should-retry header support for server-controlled retry decisions
  - Error categorization for Tinker's API
  - Pool routing based on operation type
  - Telemetry events for observability

  All functions require config in opts - NO Application.get_env at call time.

  ## Retry Semantics

  See Phase 2A, Section 2.2 for complete specification.

  The x-should-retry header takes precedence over all status-based logic:

  1. `x-should-retry: "false"` -> Never retry, even for 5xx
  2. `x-should-retry: "true"` -> Always retry (up to max), even for 4xx
  3. If header absent, fall back to status-based logic:
     - 429: Use Retry-After header
     - 408, 5xx: Exponential backoff
     - Other 4xx: No retry

  ## Telemetry Events

  Events reflect the **final outcome after all retries**, not per-attempt metrics:
  - `[:tinkex, :http, :request, :start]` - Request initiated
  - `[:tinkex, :http, :request, :stop]` - Request completed (success or failure)
  - `[:tinkex, :http, :request, :exception]` - Unexpected exception raised

  For per-attempt observability, enable debug logging.
  """

  @behaviour Tinkex.HTTPClient

  require Logger

  # Initial delay for exponential backoff (milliseconds)
  # Chosen to balance responsiveness with server load
  @initial_retry_delay 500

  # Maximum delay cap to prevent unbounded waiting
  # Aligned with typical API timeout windows
  @max_retry_delay 8_000

  # Maximum total time for retry decisions (prevents unbounded waits)
  # Note: Actual wall-clock may exceed this by receive_timeout
  @max_retry_duration_ms 30_000

  # Telemetry event names
  @telemetry_start [:tinkex, :http, :request, :start]
  @telemetry_stop [:tinkex, :http, :request, :stop]
  @telemetry_exception [:tinkex, :http, :request, :exception]

  @doc """
  POST request with retry logic.

  Config MUST be passed via opts[:config].

  ## Options

    * `:config` - Required. Tinkex.Config struct
    * `:pool_type` - Pool to use (:training, :sampling, etc.)
    * `:timeout` - Override config timeout
    * `:max_retries` - Override config max_retries
    * `:headers` - Additional headers

  ## Examples

      Tinkex.API.post("/api/v1/sample", request, [
        config: config,
        pool_type: :sampling
      ])
  """
  @impl true
  @spec post(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def post(path, body, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    metadata = %{
      method: :post,
      path: path,
      pool_type: pool_type,
      base_url: config.base_url
    }

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    execute_with_telemetry(
      fn ->
        with_retries(
          fn ->
            Finch.request(request, config.http_pool,
              receive_timeout: timeout,
              pool: Tinkex.PoolKey.build(config.base_url, pool_type)
            )
          end,
          max_retries
        )
      end,
      metadata
    )
    |> handle_response()
  end

  @doc """
  GET request with retry logic.
  """
  @impl true
  @spec get(String.t(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get(path, opts) do
    config = Keyword.fetch!(opts, :config)

    url = build_url(config.base_url, path)
    headers = build_headers(config.api_key, opts)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    max_retries = Keyword.get(opts, :max_retries, config.max_retries)
    pool_type = Keyword.get(opts, :pool_type, :default)

    metadata = %{
      method: :get,
      path: path,
      pool_type: pool_type,
      base_url: config.base_url
    }

    request = Finch.build(:get, url, headers)

    execute_with_telemetry(
      fn ->
        with_retries(
          fn ->
            Finch.request(request, config.http_pool,
              receive_timeout: timeout,
              pool: Tinkex.PoolKey.build(config.base_url, pool_type)
            )
          end,
          max_retries
        )
      end,
      metadata
    )
    |> handle_response()
  end

  # Telemetry wrapper
  defp execute_with_telemetry(fun, metadata) do
    start_time = System.monotonic_time()

    :telemetry.execute(@telemetry_start, %{system_time: System.system_time()}, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      result_type = case result do
        {:ok, %Finch.Response{status: status}} when status >= 200 and status < 300 -> :ok
        {:ok, %Finch.Response{}} -> :error
        {:error, _} -> :error
      end

      :telemetry.execute(
        @telemetry_stop,
        %{duration: duration},
        Map.put(metadata, :result, result_type)
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          @telemetry_exception,
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e, stacktrace: __STACKTRACE__})
        )

        reraise e, __STACKTRACE__
    end
  end

  # URL building - use URI.merge for proper path handling
  defp build_url(base_url, "/" <> _ = path) do
    URI.merge(base_url, path) |> URI.to_string()
  end

  defp build_url(base_url, path) do
    # Ensure path starts with /
    URI.merge(base_url, "/" <> path) |> URI.to_string()
  end

  # Header building
  defp build_headers(api_key, opts) do
    base_headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    base_headers ++ custom_headers
  end

  # ============================================================================
  # Response Handling
  # ============================================================================

  # Success response
  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status >= 200 and status < 300 do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        {:error, build_error(
          "JSON decode error: #{inspect(reason)}",
          :validation,
          nil,
          nil,
          %{body: body}
        )}
    end
  end

  # 429 Rate limit - parse Retry-After
  defp handle_response({:ok, %Finch.Response{status: 429, headers: headers, body: body}}) do
    error_data = decode_error_body(body)
    retry_after_ms = parse_retry_after(headers)

    {:error, build_error(
      error_data["message"] || "Rate limited",
      :api_status,
      429,
      :server,
      error_data,
      retry_after_ms
    )}
  end

  # Other error responses
  defp handle_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
    error_data = decode_error_body(body)

    # Parse error category from response, fall back to status-based inference
    # Note: RequestErrorCategory.parse/1 MUST return an atom, never {:error, _}
    category = case error_data["category"] do
      cat when is_binary(cat) ->
        Tinkex.Types.RequestErrorCategory.parse(cat)
      _ ->
        if status >= 400 and status < 500, do: :user, else: :server
    end

    # Check for retry-after on any response
    retry_after_ms = parse_retry_after(headers)

    {:error, build_error(
      error_data["message"] || error_data["error"] || "HTTP #{status}",
      :api_status,
      status,
      category,
      error_data,
      retry_after_ms
    )}
  end

  # Connection/transport errors
  defp handle_response({:error, %Mint.TransportError{} = exception}) do
    Logger.warning("Transport error: #{Exception.message(exception)}")

    {:error, build_error(
      Exception.message(exception),
      :api_connection,
      nil,
      nil,
      %{exception: exception}
    )}
  end

  defp handle_response({:error, %Mint.HTTPError{} = exception}) do
    Logger.warning("HTTP error: #{Exception.message(exception)}")

    {:error, build_error(
      Exception.message(exception),
      :api_connection,
      nil,
      nil,
      %{exception: exception}
    )}
  end

  # Generic error handling - safely handle both Exception structs and other terms
  # Some libraries return {:error, :timeout} or {:error, :closed}
  defp handle_response({:error, exception}) do
    message = case exception do
      %_{} -> Exception.message(exception)
      atom when is_atom(atom) -> Atom.to_string(atom)
      other -> inspect(other)
    end

    Logger.warning("Request error: #{message}")

    {:error, build_error(
      message,
      :api_connection,
      nil,
      nil,
      %{exception: exception}
    )}
  end

  # Helper to build error struct consistently
  defp build_error(message, type, status, category, data, retry_after_ms \\ nil) do
    %Tinkex.Error{
      message: message,
      type: type,
      status: status,
      category: category,
      data: data,
      retry_after_ms: retry_after_ms
    }
  end

  # Helper to decode error body
  defp decode_error_body(body) do
    case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{"message" => body}
    end
  end

  # ============================================================================
  # Retry Logic
  # ============================================================================

  # Main retry entry point
  #
  # Note on Process.sleep: This blocks the calling process. If calling from a
  # GenServer, the GenServer will be blocked during retries. For non-blocking
  # retries, consider wrapping calls in Task.async/await.
  defp with_retries(fun, max_retries) do
    start_time = System.monotonic_time(:millisecond)
    do_retry(fun, max_retries, 0, start_time)
  end

  # Recursive retry implementation with total timeout checking
  defp do_retry(fun, max_retries, attempt, start_time) do
    # Check total timeout to prevent unbounded waits
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= @max_retry_duration_ms do
      Logger.warning("Retry timeout exceeded after #{elapsed}ms")

      {:error, %Tinkex.Error{
        message: "Retry timeout exceeded (#{@max_retry_duration_ms}ms)",
        type: :api_connection,
        data: %{elapsed_ms: elapsed, attempts: attempt}
      }}
    else
      case fun.() do
        # All HTTP responses go through should_retry? helper
        # This fixes the critical bug where clause ordering made 429/5xx unreachable
        {:ok, %Finch.Response{status: status, headers: headers}} = response ->
          case should_retry?(status, headers, attempt, max_retries) do
            {:retry, delay_ms} ->
              Logger.debug("Retrying request (attempt #{attempt + 1}/#{max_retries}), status: #{status}, delay: #{delay_ms}ms")
              Process.sleep(delay_ms)
              do_retry(fun, max_retries, attempt + 1, start_time)

            :no_retry ->
              response
          end

        # Connection/transport errors - always retry if under limit
        {:error, %Mint.TransportError{reason: reason}} = error ->
          if attempt < max_retries do
            delay = retry_delay(attempt)
            Logger.debug("Retrying after transport error: #{inspect(reason)}, delay: #{delay}ms")
            Process.sleep(delay)
            do_retry(fun, max_retries, attempt + 1, start_time)
          else
            error
          end

        {:error, %Mint.HTTPError{reason: reason}} = error ->
          if attempt < max_retries do
            delay = retry_delay(attempt)
            Logger.debug("Retrying after HTTP error: #{inspect(reason)}, delay: #{delay}ms")
            Process.sleep(delay)
            do_retry(fun, max_retries, attempt + 1, start_time)
          else
            error
          end

        # Timeout errors - retry if under limit
        {:error, :timeout} = error ->
          if attempt < max_retries do
            delay = retry_delay(attempt)
            Logger.debug("Retrying after timeout, delay: #{delay}ms")
            Process.sleep(delay)
            do_retry(fun, max_retries, attempt + 1, start_time)
          else
            error
          end

        # All other responses - no retry
        other ->
          other
      end
    end
  end

  # Determine if response should be retried based on status and headers
  # x-should-retry header takes precedence over all other logic
  defp should_retry?(status, headers, attempt, max_retries) do
    if attempt >= max_retries do
      :no_retry
    else
      # x-should-retry header takes precedence
      case get_header(headers, "x-should-retry") do
        "false" ->
          # Server explicitly says don't retry - respect it even for 5xx
          :no_retry

        "true" ->
          # Server explicitly says retry - respect it even for 4xx
          {:retry, retry_delay(attempt)}

        nil ->
          # No header - use status-based logic
          cond do
            status == 429 ->
              {:retry, parse_retry_after(headers)}

            status == 408 or (status >= 500 and status < 600) ->
              {:retry, retry_delay(attempt)}

            true ->
              :no_retry
          end
      end
    end
  end

  # Helper to get header value (case-insensitive per RFC 7230)
  defp get_header(headers, name) do
    name_lower = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == name_lower, do: v
    end)
  end

  # Exponential backoff with full jitter (AWS style)
  # Full jitter uses 0-1.0x range to better spread out retry storms
  # Reference: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
  defp retry_delay(attempt) do
    base_delay = @initial_retry_delay * :math.pow(2, attempt)
    # Full jitter: random value between 0 and base_delay
    jitter = :rand.uniform()

    delay = base_delay * jitter
    delay = min(delay, @max_retry_delay)

    round(delay)
  end

  # Parse Retry-After header (case-insensitive)
  # Supports both retry-after-ms (milliseconds) and retry-after (seconds)
  defp parse_retry_after(headers) do
    # Try retry-after-ms first (milliseconds)
    case get_header(headers, "retry-after-ms") do
      nil ->
        # Fall back to retry-after (seconds)
        case get_header(headers, "retry-after") do
          nil ->
            # Default 1 second if no header
            1000

          value ->
            case Integer.parse(value) do
              {seconds, _} -> seconds * 1000
              # HTTP Date format not supported in v1.0, use default
              :error -> 1000
            end
        end

      ms_str ->
        case Integer.parse(ms_str) do
          {ms, _} -> ms
          :error -> 1000
        end
    end
  end
end
```

---

## 4. Test-Driven Development

### 4.1 Test Structure

```
test/tinkex/
└── api/
    └── api_test.exs
```

### 4.2 API Tests

**Important**: All tests use request counters to verify retry behavior, NOT timing assertions. Tests should be deterministic without `Process.sleep` dependencies.

Note: See Phase 2C for complete test examples with test helpers. Here are the critical tests for the API module:

```elixir
defmodule Tinkex.APITest do
  # NOT async: true - Bypass works better with sequential tests
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    config = Tinkex.Config.new(
      api_key: "test-key",
      base_url: "http://localhost:#{bypass.port}"
    )
    {:ok, bypass: bypass, config: config}
  end

  describe "post/3 retry logic" do
    test "retries on 5xx errors", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        count = Agent.get_and_update(counter, &{&1, &1 + 1})

        if count < 2 do
          Plug.Conn.resp(conn, 503, ~s({"error": "Service unavailable"}))
        else
          Plug.Conn.resp(conn, 200, ~s({"result": "success"}))
        end
      end)

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 3
    end

    test "retries on 429 with Retry-After", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        count = Agent.get_and_update(counter, &{&1, &1 + 1})

        if count < 1 do
          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "100")
          |> Plug.Conn.resp(429, ~s({"error": "Rate limited"}))
        else
          Plug.Conn.resp(conn, 200, ~s({"result": "success"}))
        end
      end)

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2  # Verifies retry happened
    end

    test "honors x-should-retry: false even on 5xx", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-should-retry", "false")
        |> Plug.Conn.resp(503, ~s({"error": "Don't retry"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "x-should-retry: true overrides normal 4xx no-retry", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        count = Agent.get_and_update(counter, &{&1, &1 + 1})

        if count < 1 do
          conn
          |> Plug.Conn.put_resp_header("x-should-retry", "true")
          |> Plug.Conn.resp(400, ~s({"error": "Bad request but retry"}))
        else
          Plug.Conn.resp(conn, 200, ~s({"result": "success"}))
        end
      end)

      # Despite being 400, header says retry
      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "does not retry 4xx errors without x-should-retry", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error": "Bad request"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 400
      assert error.category == :user
    end

    test "handles case-insensitive headers", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("X-Should-Retry", "false")
        |> Plug.Conn.resp(503, ~s({"error": "Don't retry"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "respects max_retries limit", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        Agent.get_and_update(counter, &{&1, &1 + 1})
        Plug.Conn.resp(conn, 503, ~s({"error": "Service unavailable"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config, max_retries: 1)
      assert error.status == 503
      # Initial request + 1 retry = 2 attempts
      assert Agent.get(counter, & &1) == 2
    end

    test "raises without config" do
      assert_raise KeyError, fn ->
        Tinkex.API.post("/test", %{}, [])
      end
    end
  end

  describe "error categorization" do
    test "parses error category from response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 400, ~s({"error": "Bad input", "category": "user"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers category from status code", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"error": "Internal error"}))
      end)

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )
      assert error.category == :server
    end
  end

  describe "error handling" do
    test "handles non-Exception error terms", %{bypass: bypass, config: config} do
      # Close the bypass to force a connection error
      Bypass.down(bypass)

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )

      assert error.type == :api_connection
    end
  end
end
```

---

## 5. Quality Gates for Phase 2B

Phase 2B is **complete** when ALL of the following are true:

### 5.1 Implementation Checklist

- [ ] `Tinkex.API` - Base module with corrected retry logic
- [ ] Retry logic handles 5xx, 408, 429, connection errors
- [ ] x-should-retry header takes precedence over status codes
- [ ] Case-insensitive header parsing
- [ ] Full jitter (0-1.0x) for exponential backoff
- [ ] Total timeout to prevent unbounded waits
- [ ] Telemetry events emitted (reflect final outcome, not per-attempt)
- [ ] Structured logging for debugging
- [ ] Generic error clause handles non-Exception terms
- [ ] `Tinkex.HTTPClient` behaviour (optional)

### 5.2 Testing Checklist

- [ ] Retry logic tests (5xx, 408, 429, connection errors) - use counters, not timing
- [ ] x-should-retry header tests (both true and false)
- [ ] x-should-retry on 400 test (must retry)
- [ ] Retry-After parsing tests (retry-after-ms, numeric seconds)
- [ ] Case-insensitive header tests
- [ ] Error categorization tests
- [ ] Config threading tests (no Application.get_env at call time)
- [ ] All tests pass: `mix test test/tinkex/api/`

### 5.3 Type Safety Checklist

- [ ] All modules have `@spec` for public functions
- [ ] `Tinkex.Error` struct properly typed
- [ ] Dialyzer passes: `mix dialyzer`

---

## 6. Common Pitfalls to Avoid

1. **Don't use Application.get_env at call time** - Only in Config.new/1
2. **Don't forget :config in opts** - It's required, not optional
3. **Don't retry on 4xx without x-should-retry: true** - Only 408/429 are exceptions
4. **Don't ignore x-should-retry header** - It takes precedence over everything
5. **Don't use case-sensitive header matching** - Headers are case-insensitive per RFC 7230
6. **Don't forget total timeout** - Prevents unbounded waits
7. **Don't assume exception is always an Exception struct** - Handle :timeout, :closed, etc.
8. **Don't put 429/5xx branches after general {:ok, %Finch.Response{}}** - They become unreachable
9. **Don't use Process.sleep in tests** - Use request counters for deterministic tests
10. **Don't use timing assertions in tests** - Verify behavior via state, not elapsed time

---

## 7. Execution Commands

```bash
# Run Phase 2B tests
mix test test/tinkex/api/api_test.exs

# Check types
mix dialyzer

# Full verification
mix compile --warnings-as-errors && mix test test/tinkex/api/ && mix dialyzer
```

---

## 8. Dependencies and Next Steps

### Dependencies

Phase 2B requires Phase 2A to be complete:
- `Tinkex.PoolKey` for pool key generation in requests
- `Tinkex.Config` for config validation
- `Tinkex.Application` running Finch pools

### Required Before Phase 2C

Phase 2C (Endpoints and Testing) requires Phase 2B to be complete:
- `Tinkex.API.post/3` and `get/2` functions
- All retry logic working correctly

---

## Summary

Phase 2B implements the core HTTP client:

1. **Correct Retry Logic** - Fixed clause ordering, proper x-should-retry semantics
2. **Error Handling** - Handles all error types including non-Exception terms
3. **Telemetry** - Events for observability (final outcome after retries)
4. **Logging** - Structured logging for debugging
5. **Mockability** - HTTPClient behaviour for testing

The critical fix is in `with_retries` - all HTTP responses go through the `should_retry?` helper function, avoiding the clause ordering bug that made 429/5xx branches unreachable.
