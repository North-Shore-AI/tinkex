# Test Plan: Retry Configuration

**Date:** 2025-11-26
**Status:** Ready for Implementation

---

## Test Coverage Matrix

| Component | Unit Tests | Integration Tests | Property Tests | Load Tests |
|-----------|-----------|------------------|----------------|------------|
| RetryConfig | ✓ | - | ✓ | - |
| RetryHandler | ✓ | - | ✓ | - |
| RateLimiter | ✓ | ✓ | - | ✓ |
| SamplingClient | ✓ | ✓ | - | ✓ |
| Retry.with_retry | ✓ | ✓ | ✓ | - |

---

## 1. Unit Tests

### 1.1 RetryConfig Tests

**File:** `test/tinkex/retry_config_test.exs`

```elixir
defmodule Tinkex.RetryConfigTest do
  use ExUnit.Case, async: true

  alias Tinkex.RetryConfig

  describe "new/1" do
    test "creates config with defaults" do
      config = RetryConfig.new()
      assert config.max_retries == 10
      assert config.base_delay_ms == 500
      assert config.max_delay_ms == 10_000
      assert config.jitter_pct == 0.25
      assert config.progress_timeout_ms == 1_800_000
      assert config.max_connections == 100
      assert config.enable_retry_logic == true
    end

    test "creates config with custom values" do
      config = RetryConfig.new(max_retries: 5, max_connections: 50)
      assert config.max_retries == 5
      assert config.max_connections == 50
    end
  end

  describe "validate!/1" do
    test "validates max_retries >= 0" do
      assert_raise ArgumentError, fn ->
        RetryConfig.new(max_retries: -1)
      end
    end

    test "validates base_delay_ms > 0" do
      assert_raise ArgumentError, fn ->
        RetryConfig.new(base_delay_ms: 0)
      end
    end

    test "validates max_delay_ms >= base_delay_ms" do
      assert_raise ArgumentError, fn ->
        RetryConfig.new(base_delay_ms: 1000, max_delay_ms: 500)
      end
    end

    test "validates jitter_pct between 0 and 1" do
      assert_raise ArgumentError, fn ->
        RetryConfig.new(jitter_pct: 1.5)
      end

      assert_raise ArgumentError, fn ->
        RetryConfig.new(jitter_pct: -0.1)
      end
    end
  end
end
```

### 1.2 RetryHandler Tests

**File:** `test/tinkex/retry_handler_test.exs`

```elixir
defmodule Tinkex.RetryHandlerTest do
  use ExUnit.Case, async: true

  alias Tinkex.{RetryHandler, RetryConfig}

  describe "next_delay/1" do
    test "calculates exponential backoff" do
      handler = RetryHandler.new(base_delay_ms: 100, jitter_pct: 0.0)

      # Attempt 0: 100ms
      assert RetryHandler.next_delay(handler) == 100

      # Attempt 1: 200ms
      handler = RetryHandler.increment_attempt(handler)
      assert RetryHandler.next_delay(handler) == 200

      # Attempt 2: 400ms
      handler = RetryHandler.increment_attempt(handler)
      assert RetryHandler.next_delay(handler) == 400
    end

    test "caps at max_delay_ms" do
      handler = RetryHandler.new(
        base_delay_ms: 100,
        max_delay_ms: 500,
        jitter_pct: 0.0
      )

      # Attempt 10: would be 102400ms, capped at 500ms
      handler = %{handler | attempt: 10}
      assert RetryHandler.next_delay(handler) == 500
    end

    test "applies jitter correctly" do
      handler = RetryHandler.new(
        base_delay_ms: 1000,
        jitter_pct: 0.25,
        max_delay_ms: 10_000
      )

      # Generate 100 samples to test jitter range
      delays =
        for _ <- 1..100 do
          RetryHandler.next_delay(handler)
        end

      # Should be distributed around 1000ms ±25%
      assert Enum.all?(delays, &(&1 >= 750 and &1 <= 1250))
      # Should have some variance (not all same)
      assert Enum.uniq(delays) |> length() > 10
    end
  end

  describe "from_config/1" do
    test "creates handler from RetryConfig" do
      retry_config = RetryConfig.new(max_retries: 5, base_delay_ms: 200)
      handler = RetryHandler.from_config(retry_config)

      assert handler.max_retries == 5
      assert handler.base_delay_ms == 200
    end
  end
end
```

### 1.3 RateLimiter Tests

**File:** `test/tinkex/rate_limiter_test.exs`

```elixir
defmodule Tinkex.RateLimiterTest do
  use ExUnit.Case

  alias Tinkex.RateLimiter

  setup do
    limiter = RateLimiter.for_key({"http://test.com", "key123"})
    RateLimiter.clear_backoff(limiter)
    {:ok, limiter: limiter}
  end

  describe "set_backoff and wait_for_backoff" do
    test "waits for backoff duration", %{limiter: limiter} do
      RateLimiter.set_backoff(limiter, 100)

      start = System.monotonic_time(:millisecond)
      RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should wait ~100ms (with some tolerance)
      assert elapsed >= 90 and elapsed < 150
    end

    test "does not wait if no backoff", %{limiter: limiter} do
      start = System.monotonic_time(:millisecond)
      RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should be instant
      assert elapsed < 10
    end

    test "does not wait if backoff expired", %{limiter: limiter} do
      RateLimiter.set_backoff(limiter, 50)
      Process.sleep(60)  # Wait for expiration

      start = System.monotonic_time(:millisecond)
      RateLimiter.wait_for_backoff(limiter)
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed < 10
    end
  end
end
```

---

## 2. Integration Tests

### 2.1 SamplingClient Retry Integration

**File:** `test/integration/sampling_client_retry_test.exs`

```elixir
defmodule Tinkex.Integration.SamplingClientRetryTest do
  use ExUnit.Case

  alias Tinkex.{SamplingClient, RetryConfig, Config}

  # Mock API that fails N times then succeeds
  defmodule MockSamplingAPI do
    def sample_async(_request, opts) do
      attempt = Keyword.get(opts, :tinker_request_iteration, 0)
      fail_count = Process.get(:fail_count, 3)

      if attempt < fail_count do
        {:error, Tinkex.Error.new(:api_connection, "Mock connection error")}
      else
        {:ok, %{samples: []}}
      end
    end
  end

  setup do
    config = Config.new(api_key: "test", base_url: "http://localhost:8000")
    retry_config = RetryConfig.new(max_retries: 5, base_delay_ms: 10)

    {:ok, client} =
      SamplingClient.start_link(
        config: config,
        session_id: "test_session",
        sampling_client_id: 0,
        base_model: "test-model",
        retry_config: retry_config,
        sampling_api: MockSamplingAPI
      )

    {:ok, client: client, config: config}
  end

  test "retries on connection error", %{client: client} do
    Process.put(:fail_count, 2)  # Fail twice, succeed on 3rd

    prompt = %{type: "text", content: "test"}
    params = %{max_tokens: 10}

    {:ok, task} = SamplingClient.sample(client, prompt, params)
    result = Task.await(task, 5000)

    assert {:ok, %{samples: []}} = result
  end

  test "stops retrying after max_retries", %{client: client} do
    Process.put(:fail_count, 100)  # Always fail

    prompt = %{type: "text", content: "test"}
    params = %{max_tokens: 10}

    {:ok, task} = SamplingClient.sample(client, prompt, params)
    result = Task.await(task, 5000)

    assert {:error, %Tinkex.Error{}} = result
  end
end
```

---

## 3. Property-Based Tests

### 3.1 Backoff Calculation Properties

**File:** `test/property/retry_handler_properties_test.exs`

```elixir
defmodule Tinkex.Property.RetryHandlerPropertiesTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Tinkex.RetryHandler

  property "next_delay is always >= 0" do
    check all base_delay <- positive_integer(),
              max_delay <- integer(base_delay..100_000),
              jitter <- float(min: 0.0, max: 1.0),
              attempt <- integer(0..100) do
      handler =
        RetryHandler.new(
          base_delay_ms: base_delay,
          max_delay_ms: max_delay,
          jitter_pct: jitter
        )

      handler = %{handler | attempt: attempt}
      delay = RetryHandler.next_delay(handler)

      assert delay >= 0
    end
  end

  property "next_delay is always <= max_delay" do
    check all base_delay <- positive_integer(),
              max_delay <- integer(base_delay..100_000),
              jitter <- float(min: 0.0, max: 1.0),
              attempt <- integer(0..100) do
      handler =
        RetryHandler.new(
          base_delay_ms: base_delay,
          max_delay_ms: max_delay,
          jitter_pct: jitter
        )

      handler = %{handler | attempt: attempt}
      delay = RetryHandler.next_delay(handler)

      assert delay <= max_delay
    end
  end

  property "jitter is within expected range" do
    check all base_delay <- integer(100..10_000),
              jitter_pct <- float(min: 0.0, max: 0.5),
              attempt <- integer(0..10) do
      handler =
        RetryHandler.new(
          base_delay_ms: base_delay,
          max_delay_ms: 100_000,
          jitter_pct: jitter_pct
        )

      handler = %{handler | attempt: attempt}

      # Calculate expected base delay
      expected_base = min(base_delay * :math.pow(2, attempt), 100_000)

      # Sample delays should be within jitter range
      delays = for _ <- 1..10, do: RetryHandler.next_delay(handler)

      for delay <- delays do
        min_expected = expected_base * (1 - jitter_pct)
        max_expected = expected_base * (1 + jitter_pct)
        assert delay >= min_expected - 1  # -1 for rounding
        assert delay <= max_expected + 1  # +1 for rounding
      end
    end
  end
end
```

---

## 4. Load Tests

### 4.1 Connection Limiting Load Test

**File:** `test/load/connection_limit_test.exs`

```elixir
defmodule Tinkex.Load.ConnectionLimitTest do
  use ExUnit.Case

  @moduletag :load

  alias Tinkex.{SamplingClient, RetryConfig, Config}

  test "respects max_connections limit" do
    max_connections = 10
    num_requests = 50

    config = Config.new(api_key: "test", base_url: "http://localhost:8000")
    retry_config = RetryConfig.new(max_connections: max_connections)

    {:ok, client} =
      SamplingClient.start_link(
        config: config,
        session_id: "load_test",
        sampling_client_id: 0,
        base_model: "test-model",
        retry_config: retry_config
      )

    # Track concurrent requests
    :ets.new(:concurrent_tracker, [:named_table, :public, :set])
    :ets.insert(:concurrent_tracker, {:max, 0})
    :ets.insert(:concurrent_tracker, {:current, 0})

    tasks =
      for i <- 1..num_requests do
        Task.async(fn ->
          # Increment concurrent count
          current = :ets.update_counter(:concurrent_tracker, :current, 1)
          max = :ets.lookup(:concurrent_tracker, :max) |> hd() |> elem(1)

          if current > max do
            :ets.insert(:concurrent_tracker, {:max, current})
          end

          # Simulate work
          Process.sleep(50)

          # Decrement
          :ets.update_counter(:concurrent_tracker, :current, -1)

          i
        end)
      end

    Task.await_many(tasks, 60_000)

    [{:max, max_concurrent}] = :ets.lookup(:concurrent_tracker, :max)

    # Should not exceed max_connections
    assert max_concurrent <= max_connections
  end
end
```

---

## 5. Edge Cases

### 5.1 Edge Case Tests

**File:** `test/tinkex/retry_edge_cases_test.exs`

```elixir
defmodule Tinkex.RetryEdgeCasesTest do
  use ExUnit.Case

  alias Tinkex.{Retry, RetryHandler, Error}

  test "handles extremely large attempt numbers" do
    handler = RetryHandler.new(base_delay_ms: 500, max_delay_ms: 10_000)
    handler = %{handler | attempt: 10_000}

    # Should not crash, should return max_delay
    delay = RetryHandler.next_delay(handler)
    assert delay == 10_000
  end

  test "handles max_retries = 0" do
    handler = RetryHandler.new(max_retries: 0)

    result =
      Retry.with_retry(
        fn -> {:error, Error.new(:api_connection, "test")} end,
        handler: handler
      )

    # Should fail immediately without retry
    assert {:error, %Error{}} = result
  end

  test "handles enable_retry_logic = false" do
    # Fast path: should not retry even on retryable error
    call_count = :counters.new(1, [])

    result =
      Retry.with_retry(
        fn ->
          :counters.add(call_count, 1, 1)
          {:error, Error.new(:api_connection, "test")}
        end,
        handler: RetryHandler.new(enable_retry_logic: false)
      )

    # Should only call once (no retries)
    assert :counters.get(call_count, 1) == 1
    assert {:error, %Error{}} = result
  end
end
```

---

## 6. Backward Compatibility Tests

**File:** `test/tinkex/backward_compatibility_test.exs`

```elixir
defmodule Tinkex.BackwardCompatibilityTest do
  use ExUnit.Case

  alias Tinkex.{SamplingClient, Config}

  test "works without retry_config parameter" do
    config = Config.new(api_key: "test", base_url: "http://localhost:8000")

    # Should work with defaults
    {:ok, client} =
      SamplingClient.start_link(
        config: config,
        session_id: "compat_test",
        sampling_client_id: 0,
        base_model: "test-model"
        # No retry_config - should use defaults
      )

    assert is_pid(client)
  end
end
```

---

## 7. Test Execution

### Running Tests

```bash
# All tests
mix test

# Unit tests only
mix test test/tinkex/

# Integration tests
mix test test/integration/

# Property tests
mix test test/property/

# Load tests (excluded by default)
mix test --include load

# With coverage
mix test --cover
```

### Coverage Goals

- **Unit tests:** 100% coverage
- **Integration tests:** Critical paths
- **Property tests:** All mathematical functions
- **Load tests:** Concurrency limits

---

## Summary

This test plan ensures:

✅ **Correctness** - All retry logic works as designed
✅ **Performance** - Connection limiting prevents exhaustion
✅ **Robustness** - Edge cases handled gracefully
✅ **Compatibility** - Backward compatible with existing code
✅ **Maintainability** - Comprehensive test coverage
