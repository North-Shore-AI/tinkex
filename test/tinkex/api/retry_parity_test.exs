defmodule Tinkex.API.RetryParityTest do
  @moduledoc """
  Tests for Python SDK parity in retry behavior.

  Reference: tinker/_base_client.py `_should_retry`, `_calculate_retry_timeout`
  Reference: tinker/_constants.py for INITIAL_RETRY_DELAY, MAX_RETRY_DELAY
  """
  use ExUnit.Case, async: true

  alias Tinkex.API.RetryConfig

  # Python constants from _constants.py
  @python_initial_delay 500
  @python_max_delay 10_000

  describe "retry_delay/2 (Python parity)" do
    test "uses Python-style jitter (0.75-1.0 multiplier)" do
      # Python: jitter = 1 - 0.25 * random() -> range [0.75, 1.0]
      # Test many samples to verify jitter bounds
      delays =
        for _ <- 1..100 do
          RetryConfig.retry_delay(0)
        end

      # All delays should be in range [base * 0.75, base * 1.0]
      # At attempt 0: base = 500, so range = [375, 500]
      assert Enum.all?(delays, fn d -> d >= 375 and d <= 500 end),
             "Expected delays in [375, 500], got: #{inspect(Enum.min_max(delays))}"
    end

    test "caps delay at 10 seconds (Python MAX_RETRY_DELAY)" do
      # Python: MAX_RETRY_DELAY = 10.0 seconds = 10_000 ms
      # At high attempt counts, delay should be capped
      delays =
        for _ <- 1..100 do
          # Attempt 10 would give base_delay = 500 * 2^10 = 512_000ms before cap
          RetryConfig.retry_delay(10)
        end

      # All delays should be capped at 10s * jitter_max (10_000 * 1.0 = 10_000)
      assert Enum.all?(delays, fn d -> d <= @python_max_delay end),
             "Expected delays <= #{@python_max_delay}, got max: #{Enum.max(delays)}"

      # And should be at least 10s * jitter_min (10_000 * 0.75 = 7_500)
      assert Enum.all?(delays, fn d -> d >= 7_500 end),
             "Expected delays >= 7500, got min: #{Enum.min(delays)}"
    end

    test "exponential backoff with correct base delay" do
      # Python: sleep_seconds = min(INITIAL_RETRY_DELAY * pow(2.0, nb_retries), MAX_RETRY_DELAY)
      # INITIAL_RETRY_DELAY = 0.5s = 500ms
      #
      # Attempt 0: 500 * 2^0 = 500ms
      # Attempt 1: 500 * 2^1 = 1000ms
      # Attempt 2: 500 * 2^2 = 2000ms
      # Attempt 3: 500 * 2^3 = 4000ms
      # Attempt 4: 500 * 2^4 = 8000ms
      # Attempt 5: 500 * 2^5 = 16000ms -> capped to 10000ms

      for attempt <- 0..4 do
        base_expected = @python_initial_delay * round(:math.pow(2, attempt))
        delays = for _ <- 1..20, do: RetryConfig.retry_delay(attempt)

        min_expected = round(base_expected * 0.75)
        max_expected = round(base_expected * 1.0)

        assert Enum.all?(delays, fn d -> d >= min_expected and d <= max_expected end),
               "Attempt #{attempt}: expected delays in [#{min_expected}, #{max_expected}], got: #{inspect(Enum.min_max(delays))}"
      end
    end
  end

  describe "should_retry?/2 status codes (Python parity)" do
    test "retries 408 (Request Timeout)" do
      assert RetryConfig.retryable_status?(408)
    end

    test "retries 409 (Conflict/Lock Timeout)" do
      # Python parity: _base_client.py line 724-727
      assert RetryConfig.retryable_status?(409)
    end

    test "retries 429 (Rate Limited)" do
      assert RetryConfig.retryable_status?(429)
    end

    test "retries 5xx (Server Errors)" do
      for status <- 500..599 do
        assert RetryConfig.retryable_status?(status), "Expected #{status} to be retryable"
      end
    end

    test "does not retry 4xx (except 408, 409, 429)" do
      non_retryable = Enum.filter(400..499, fn s -> s not in [408, 409, 429] end)

      for status <- non_retryable do
        refute RetryConfig.retryable_status?(status), "Expected #{status} to not be retryable"
      end
    end

    test "does not retry 2xx" do
      for status <- 200..299 do
        refute RetryConfig.retryable_status?(status), "Expected #{status} to not be retryable"
      end
    end

    test "does not retry 3xx" do
      for status <- 300..399 do
        refute RetryConfig.retryable_status?(status), "Expected #{status} to not be retryable"
      end
    end
  end

  describe "no wall-clock timeout (Python parity)" do
    test "retry governed by max_retries only, not wall clock" do
      # Python SDK does NOT have a 30s wall-clock cutoff.
      # It retries up to max_retries times regardless of total elapsed time.
      # This is tested via the API.post tests with slow responses,
      # but we verify the config doesn't enforce a wall-clock limit.
      config = RetryConfig.new(max_retries: 10)
      refute Map.has_key?(config, :max_retry_duration_ms)
    end
  end
end
