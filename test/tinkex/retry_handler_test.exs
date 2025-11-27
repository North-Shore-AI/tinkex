defmodule Tinkex.RetryHandlerTest do
  use ExUnit.Case, async: true

  alias Tinkex.RetryHandler

  describe "new/1" do
    test "creates handler with defaults" do
      handler = RetryHandler.new()
      assert handler.max_retries == 3
      assert handler.base_delay_ms == 500
      assert handler.max_delay_ms == 8000
      assert handler.jitter_pct == 1.0
      assert handler.progress_timeout_ms == 30_000
      assert handler.attempt == 0
      assert is_integer(handler.start_time)
    end

    test "accepts custom options" do
      handler = RetryHandler.new(max_retries: 5, base_delay_ms: 1000)
      assert handler.max_retries == 5
      assert handler.base_delay_ms == 1000
    end
  end

  describe "retry?/2" do
    test "returns false for user errors" do
      handler = RetryHandler.new()
      user_error = %Tinkex.Error{type: :api_status, status: 400, message: "bad request"}
      assert RetryHandler.retry?(handler, user_error) == false
    end

    test "returns true for retryable errors when under max_retries" do
      handler = RetryHandler.new(max_retries: 3)
      system_error = %Tinkex.Error{type: :api_status, status: 500, message: "server error"}
      assert RetryHandler.retry?(handler, system_error) == true
    end

    test "returns false when at max_retries" do
      handler = RetryHandler.new(max_retries: 3) |> Map.put(:attempt, 3)
      system_error = %Tinkex.Error{type: :api_status, status: 500, message: "server error"}
      assert RetryHandler.retry?(handler, system_error) == false
    end

    test "returns true for 408 timeout" do
      handler = RetryHandler.new()
      timeout = %Tinkex.Error{type: :api_status, status: 408, message: "timeout"}
      assert RetryHandler.retry?(handler, timeout) == true
    end

    test "returns true for 429 rate limit" do
      handler = RetryHandler.new()
      rate_limit = %Tinkex.Error{type: :api_status, status: 429, message: "rate limited"}
      assert RetryHandler.retry?(handler, rate_limit) == true
    end

    test "returns true for 5xx errors" do
      handler = RetryHandler.new()
      server_error = %Tinkex.Error{type: :api_status, status: 503, message: "unavailable"}
      assert RetryHandler.retry?(handler, server_error) == true
    end
  end

  describe "next_delay/1" do
    test "calculates exponential backoff" do
      handler = RetryHandler.new(base_delay_ms: 500, max_delay_ms: 8000, jitter_pct: 0.0)

      delay0 = RetryHandler.next_delay(handler)
      assert delay0 == 500

      handler1 = %{handler | attempt: 1}
      delay1 = RetryHandler.next_delay(handler1)
      assert delay1 == 1000

      handler2 = %{handler | attempt: 2}
      delay2 = RetryHandler.next_delay(handler2)
      assert delay2 == 2000
    end

    test "respects max_delay_ms" do
      handler = RetryHandler.new(base_delay_ms: 500, max_delay_ms: 1000, jitter_pct: 0.0)
      handler10 = %{handler | attempt: 10}
      delay = RetryHandler.next_delay(handler10)
      assert delay == 1000
    end

    test "adds jitter when jitter_pct > 0" do
      handler = RetryHandler.new(base_delay_ms: 1000, jitter_pct: 1.0)

      delays =
        for _ <- 1..10 do
          RetryHandler.next_delay(handler)
        end

      # With jitter, delays should vary
      assert length(Enum.uniq(delays)) > 1
      # All delays should be in valid range [0, base * 2]
      assert Enum.all?(delays, fn d -> d >= 0 and d <= 2000 end)
    end
  end

  describe "record_progress/1" do
    test "updates last_progress_at" do
      handler = RetryHandler.new()
      Process.sleep(10)
      updated = RetryHandler.record_progress(handler)
      assert updated.last_progress_at > handler.last_progress_at
    end
  end

  describe "progress_timeout?/1" do
    test "returns false when within timeout" do
      handler = RetryHandler.new(progress_timeout_ms: 30_000)
      assert RetryHandler.progress_timeout?(handler) == false
    end

    test "returns true when past timeout" do
      handler =
        RetryHandler.new(progress_timeout_ms: 10)
        |> Map.put(:last_progress_at, System.monotonic_time(:millisecond) - 100)

      assert RetryHandler.progress_timeout?(handler) == true
    end

    test "returns false when last_progress_at is nil" do
      handler = RetryHandler.new() |> Map.put(:last_progress_at, nil)
      assert RetryHandler.progress_timeout?(handler) == false
    end
  end

  describe "increment_attempt/1" do
    test "increments attempt counter" do
      handler = RetryHandler.new()
      assert handler.attempt == 0
      handler1 = RetryHandler.increment_attempt(handler)
      assert handler1.attempt == 1
      handler2 = RetryHandler.increment_attempt(handler1)
      assert handler2.attempt == 2
    end
  end

  describe "elapsed_ms/1" do
    test "returns elapsed time since start" do
      handler = RetryHandler.new()
      Process.sleep(10)
      elapsed = RetryHandler.elapsed_ms(handler)
      assert elapsed >= 10
    end
  end
end
